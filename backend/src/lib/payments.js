// Swipe-pack plans and the Razorpay plumbing. Configuration is read from the
// environment at call time:
//   RAZORPAY_KEY_ID / RAZORPAY_KEY_SECRET  -> real payments (orders over REST)
//   RAZORPAY_WEBHOOK_SECRET                -> /payment/webhook signature
//   DEMO_PAYMENTS=true                     -> demo orders even when NODE_ENV=production
// Without Razorpay keys, demo orders are allowed outside production, or when
// DEMO_PAYMENTS=true.

const crypto = require("node:crypto");
const { prisma } = require("./prisma");
const { creditOrder, FREE_SWIPES } = require("./credits");

const PLANS = [
  {
    id: "starter",
    name: "Starter",
    price: 399,
    swipes: 150,
    perks: ["150 candidate swipes", "Full resume & intro video access", "Unlimited wishlist", "Contact details on shortlist"],
  },
];

function planById(id) {
  return PLANS.find((p) => p.id === id) || null;
}

function razorpayKeys() {
  const keyId = process.env.RAZORPAY_KEY_ID || "";
  const keySecret = process.env.RAZORPAY_KEY_SECRET || "";
  return keyId && keySecret ? { keyId, keySecret } : null;
}

function razorpayEnabled() {
  return razorpayKeys() !== null;
}

function demoAllowed() {
  if (razorpayEnabled()) return false;
  return process.env.NODE_ENV !== "production" || process.env.DEMO_PAYMENTS === "true";
}

function hmacHex(secret, data) {
  return crypto.createHmac("sha256", secret).update(data).digest("hex");
}

function safeEqualHex(a, b) {
  const x = Buffer.from(String(a || ""), "utf8");
  const y = Buffer.from(String(b || ""), "utf8");
  return x.length === y.length && x.length > 0 && crypto.timingSafeEqual(x, y);
}

/** Creates an order on Razorpay. Throws on any failure. */
async function createRazorpayOrder({ plan, recruiterId }) {
  const keys = razorpayKeys();
  const auth = Buffer.from(`${keys.keyId}:${keys.keySecret}`).toString("base64");
  const res = await globalThis.fetch("https://api.razorpay.com/v1/orders", {
    method: "POST",
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      amount: plan.price * 100,
      currency: "INR",
      receipt: `sh_${crypto.randomBytes(8).toString("hex")}`,
      notes: { recruiterId, planId: plan.id },
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok || !json.id) throw new Error(`Razorpay order failed (${res.status})`);
  return json.id;
}

function verifyCheckoutSignature(orderId, paymentId, signature) {
  const keys = razorpayKeys();
  if (!keys || !orderId || !paymentId || !signature) return false;
  return safeEqualHex(hmacHex(keys.keySecret, `${orderId}|${paymentId}`), signature);
}

/** Marks the payment paid and credits the pack (once). */
async function settle(payment, paymentId) {
  const result = await creditOrder(payment.recruiterId, payment.orderId, payment.swipes);
  await prisma.payment.updateMany({
    where: { id: payment.id },
    data: { status: "paid", ...(paymentId ? { paymentId } : {}) },
  });
  return result;
}

/**
 * Razorpay webhook body (raw bytes) + the x-razorpay-signature header.
 * @returns {{ status: number, body: object }}
 */
async function handleWebhook(rawBody, signature) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET || "";
  if (!secret) return { status: 503, body: { error: "Webhook is not configured." } };
  if (!Buffer.isBuffer(rawBody)) return { status: 501, body: { error: "Raw request body is not available." } };
  if (!safeEqualHex(hmacHex(secret, rawBody), signature)) return { status: 400, body: { error: "Invalid signature." } };

  let event;
  try {
    event = JSON.parse(rawBody.toString("utf8"));
  } catch {
    return { status: 400, body: { error: "Invalid payload." } };
  }
  if (event.event !== "payment.captured" && event.event !== "order.paid") return { status: 200, body: { ok: true } };

  const paymentEntity = event.payload?.payment?.entity;
  const orderEntity = event.payload?.order?.entity;
  const orderId = paymentEntity?.order_id || orderEntity?.id;
  const amount = Number(paymentEntity?.amount ?? orderEntity?.amount_paid ?? orderEntity?.amount);
  if (!orderId) return { status: 200, body: { ok: true } };

  const payment = await prisma.payment.findUnique({ where: { orderId } });
  // Unknown order, or an amount that is not this plan's price: acknowledge but do not credit.
  if (!payment || payment.mode !== "razorpay" || amount !== payment.amountRupees * 100) {
    return { status: 200, body: { ok: true } };
  }
  await settle(payment, paymentEntity?.id);
  return { status: 200, body: { ok: true } };
}

module.exports = {
  PLANS,
  FREE_SWIPES,
  planById,
  razorpayKeys,
  razorpayEnabled,
  demoAllowed,
  createRazorpayOrder,
  verifyCheckoutSignature,
  settle,
  handleWebhook,
  hmacHex,
};
