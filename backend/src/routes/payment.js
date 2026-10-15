const crypto = require("node:crypto");
const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { str, requireRole } = require("../lib/validate");
const { ensureCompany } = require("../lib/credits");
const payments = require("../lib/payments");

const router = express.Router();

const UNAVAILABLE = { error: "Payments are not available right now" };

// GET /payment/plans (public)
router.get("/plans", (req, res) => {
  res.json({ plans: payments.PLANS, freeSwipes: payments.FREE_SWIPES, demoMode: payments.demoAllowed() });
});

// POST /payment/webhook -- Razorpay -> us. Authenticated by signature, not a
// bearer token. The signature covers the raw bytes, so this needs
// `req.rawBody` (set by the JSON parser's `verify` hook in app.js) or a body
// that is still a Buffer. If neither exists we answer 501 rather than check a
// re-serialised body, which would not match the signed bytes.
router.post("/webhook", express.raw({ type: "*/*", limit: "256kb" }), async (req, res) => {
  const raw = Buffer.isBuffer(req.rawBody) ? req.rawBody : Buffer.isBuffer(req.body) ? req.body : null;
  const result = await payments.handleWebhook(raw, req.get("x-razorpay-signature") || "");
  res.status(result.status).json(result.body);
});

router.use(requireAuth);

// POST /payment/order { planId } -> { mode, orderId, amount, currency, keyId, plan }
router.post("/order", requireRole("recruiter"), async (req, res) => {
  const plan = payments.planById(str(req.body?.planId, 50));
  if (!plan) return res.status(400).json({ error: "Please choose a valid plan", field: "planId" });

  let mode;
  let orderId;
  if (payments.razorpayEnabled()) {
    mode = "razorpay";
    try {
      orderId = await payments.createRazorpayOrder({ plan, recruiterId: req.user.id });
    } catch (err) {
      console.error("[payment] could not create the Razorpay order:", err.message);
      return res.status(502).json({ error: "Could not start the payment. Please try again." });
    }
  } else if (payments.demoAllowed()) {
    mode = "demo";
    orderId = `demo_${crypto.randomBytes(8).toString("hex")}`;
  } else {
    return res.status(503).json(UNAVAILABLE);
  }

  await ensureCompany(req.user);
  await prisma.payment.create({
    data: {
      recruiterId: req.user.id,
      planId: plan.id,
      amountRupees: plan.price,
      swipes: plan.swipes,
      orderId,
      mode,
    },
  });

  res.json({
    mode,
    orderId,
    amount: plan.price * 100,
    currency: "INR",
    keyId: mode === "razorpay" ? payments.razorpayKeys().keyId : "",
    plan,
  });
});

// POST /payment/verify { orderId, paymentId?, signature? } -> { swipesLeft, added }
// Idempotent: a second call (or the webhook arriving first) adds 0.
router.post("/verify", requireRole("recruiter"), async (req, res) => {
  const orderId = str(req.body?.orderId, 100);
  if (!orderId) return res.status(400).json({ error: "Payment verification failed" });

  const payment = await prisma.payment.findUnique({ where: { orderId } });
  if (!payment || payment.recruiterId !== req.user.id) return res.status(404).json({ error: "Order not found" });

  let paymentId = "";
  if (payment.mode === "razorpay") {
    paymentId = str(req.body?.paymentId, 100);
    const signature = str(req.body?.signature, 200);
    if (!payments.verifyCheckoutSignature(orderId, paymentId, signature)) {
      return res.status(400).json({ error: "Payment verification failed" });
    }
  } else if (!payments.demoAllowed()) {
    // A demo order is only creditable while demo payments are on; never once
    // real keys are configured.
    return res.status(503).json(UNAVAILABLE);
  }

  await ensureCompany(req.user);
  const result = await payments.settle(payment, paymentId);
  res.json({ swipesLeft: result.swipesLeft, added: result.added });
});

module.exports = router;
