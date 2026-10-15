const express = require("express");
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { prisma } = require("../lib/prisma");
const { mintFirebaseToken, ensureFirebaseUser, deleteFirebaseUser, verifyIdToken } = require("../lib/firebase");
const { emailConfigured, sendOtpEmail } = require("../lib/mailer");
const { requireAuth } = require("../middleware/requireAuth");
const { toProfile } = require("../lib/serializers");

const router = express.Router();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const OTP_TTL_MINUTES = 10;
const OTP_RESEND_COOLDOWN_SECONDS = 45;
const MAX_OTP_ATTEMPTS = 5;
const OTP_VERIFIED_WINDOW_MINUTES = 30;
const MIN_PASSWORD_LENGTH = 8;
const PASSWORD_MESSAGE = `Choose a password of at least ${MIN_PASSWORD_LENGTH} characters.`;

// Compared against when an email isn't registered, so a login for an unknown
// address takes as long as one for a real account and can't be told apart.
const DUMMY_HASH = bcrypt.hashSync("not-a-real-password", 10);

// Cryptographically secure; Math.random() is predictable and must never
// generate a code that guards an account.
function generateOtp() {
  return String(crypto.randomInt(100000, 1000000));
}

function signToken(user) {
  return jwt.sign({ sub: user.id, role: user.role, v: user.tokenVersion ?? 0 }, process.env.JWT_SECRET, { expiresIn: "30d" });
}

async function sessionResponse(user) {
  return {
    token: signToken(user),
    firebaseToken: await mintFirebaseToken(user),
    user: toProfile(user),
  };
}

// Emails the code when Resend is configured. Without it (local dev only)
// the code is logged and returned as `devOtp` so the app can show it.
async function issueOtp(email, purpose) {
  const recent = await prisma.otpCode.findFirst({
    where: { email, purpose },
    orderBy: { createdAt: "desc" },
  });
  if (recent && Date.now() - recent.createdAt.getTime() < OTP_RESEND_COOLDOWN_SECONDS * 1000) {
    return { error: { status: 429, message: "Please wait a moment before requesting another code." } };
  }

  const otp = generateOtp();
  const record = await prisma.otpCode.create({
    data: { email, code: otp, purpose, expiresAt: new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000) },
  });

  if (!emailConfigured()) {
    console.log(`[otp] ${purpose} code for ${email}: ${otp}`);
    return { devOtp: otp };
  }

  try {
    await sendOtpEmail({ to: email, otp, purpose });
  } catch (err) {
    // Resend's shared test sender (onboarding@resend.dev) can only deliver to
    // the Resend account owner's own inbox and answers 403 for anyone else.
    // In development that shouldn't block testing with other addresses, so
    // fall back to showing the code in the app. In production this only
    // applies when OTP_DEV_FALLBACK=true is set explicitly (staging/testing a
    // deployed build before a sending domain is verified in Resend).
    const testSenderRestriction = err.response?.body?.statusCode === 403;
    const fallbackAllowed = process.env.NODE_ENV !== "production" || process.env.OTP_DEV_FALLBACK === "true";
    if (testSenderRestriction && fallbackAllowed) {
      console.warn(`[otp] Resend test sender can't deliver to ${email}; returning the code to the app (dev only).`);
      console.log(`[otp] ${purpose} code for ${email}: ${otp}`);
      return { devOtp: otp };
    }
    // Drop the record so the resend cooldown doesn't lock the user out of
    // retrying a send that never happened.
    await prisma.otpCode.delete({ where: { id: record.id } });
    console.error(`[otp] email send failed for ${email}:`, err.response?.body || err.message);
    return { error: { status: 502, message: "Could not send the email right now. Please try again." } };
  }
  return {};
}

async function checkOtp(email, purpose, otp) {
  const record = await prisma.otpCode.findFirst({
    where: { email, purpose, consumed: false },
    orderBy: { createdAt: "desc" },
  });
  if (!record) return { error: "No active code for this email. Please request a new one." };
  if (record.expiresAt.getTime() < Date.now()) return { error: "This code has expired. Please request a new one." };
  if (record.attempts >= MAX_OTP_ATTEMPTS) return { error: "Too many attempts. Please request a new code." };
  if (record.code !== otp) {
    await prisma.otpCode.update({ where: { id: record.id }, data: { attempts: { increment: 1 } } });
    return { error: "Incorrect code." };
  }
  await prisma.otpCode.update({ where: { id: record.id }, data: { consumed: true } });
  return {};
}

// POST /auth/otp/send { email }
router.post("/otp/send", async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ error: "A valid email is required." });
  }
  if (await prisma.user.findUnique({ where: { email } })) {
    return res.status(409).json({ error: "An account already exists with that email. Try logging in instead." });
  }

  const { devOtp, error } = await issueOtp(email, "signup");
  if (error) return res.status(error.status).json({ error: error.message });
  return res.json({ sent: true, otp: devOtp });
});

// POST /auth/otp/verify { email, otp }
router.post("/otp/verify", async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  const otp = String(req.body?.otp || "").trim();

  const { error } = await checkOtp(email, "signup", otp);
  if (error) return res.status(400).json({ error });
  return res.json({ verified: true });
});

// POST /auth/signup { name, email, password, role, company }
router.post("/signup", async (req, res) => {
  const name = String(req.body?.name || "").trim();
  const email = String(req.body?.email || "").trim().toLowerCase();
  const password = String(req.body?.password || "");
  const role = req.body?.role === "recruiter" ? "recruiter" : "candidate";
  const company = String(req.body?.company || "").trim();

  if (!name || !EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ error: "Enter your name and a valid email address." });
  }
  if (password.length < MIN_PASSWORD_LENGTH || password.length > 200) {
    return res.status(400).json({ error: PASSWORD_MESSAGE });
  }

  const verifiedOtp = await prisma.otpCode.findFirst({
    where: {
      email,
      purpose: "signup",
      consumed: true,
      createdAt: { gte: new Date(Date.now() - OTP_VERIFIED_WINDOW_MINUTES * 60 * 1000) },
    },
  });
  if (!verifiedOtp) {
    return res.status(400).json({ error: "Please verify your email with the code before signing up." });
  }
  if (await prisma.user.findUnique({ where: { email } })) {
    return res.status(409).json({ error: "An account already exists with that email. Try logging in instead." });
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const user = await prisma.user.create({
    data: { name, email, passwordHash, role, company, emailVerified: true },
  });
  await ensureFirebaseUser(user);
  await prisma.otpCode.deleteMany({ where: { email, purpose: "signup" } });

  return res.status(201).json(await sessionResponse(user));
});

// POST /auth/login { email, password }
router.post("/login", async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  const password = String(req.body?.password || "");

  const user = await prisma.user.findUnique({ where: { email } });
  const passwordOk = await bcrypt.compare(password, user ? user.passwordHash : DUMMY_HASH);
  if (!user || !passwordOk) {
    return res.status(401).json({ error: "Incorrect email or password." });
  }

  return res.json(await sessionResponse(user));
});

// POST /auth/google { idToken, role? }
// The app signs into Firebase with Google and sends that Firebase ID token.
// An existing account is signed in; a new one needs `role` (the app asks the
// person to choose, then retries). Either way the app gets the same session
// as a password login, keyed by the account's own id.
router.post("/google", async (req, res) => {
  const idToken = String(req.body?.idToken || "");
  if (!idToken) return res.status(400).json({ error: "A Google sign-in token is required." });

  let claims;
  try {
    claims = await verifyIdToken(idToken);
  } catch {
    return res.status(401).json({ error: "Google sign-in could not be verified. Please try again." });
  }
  const email = String(claims.email || "").trim().toLowerCase();
  if (!email || claims.email_verified === false) {
    return res.status(400).json({ error: "Your Google account has no verified email address." });
  }

  let user = await prisma.user.findUnique({ where: { email } });
  if (!user) {
    const role = req.body?.role;
    if (role !== "candidate" && role !== "recruiter") {
      return res.status(409).json({ error: "Choose how you want to use GlideRecruit.", needsRole: true });
    }
    // The account has no password of its own; a long random one keeps the
    // column filled and unguessable. "Forgot password" can set a real one.
    const passwordHash = await bcrypt.hash(crypto.randomBytes(32).toString("hex"), 10);
    const name = String(claims.name || email.split("@")[0]).trim().slice(0, 100) || "GlideRecruit user";
    user = await prisma.user.create({
      data: { name, email, passwordHash, role, emailVerified: true },
    });
  }

  // The Firebase user Google created has its own uid; our session uses the
  // account id, so drop the temporary one (best effort).
  if (claims.uid && claims.uid !== user.id) {
    await deleteFirebaseUser(claims.uid).catch(() => {});
  }
  await ensureFirebaseUser(user);

  return res.json(await sessionResponse(user));
});

// POST /auth/reauth { password } -- confirms the password for a sensitive
// action and hands back a fresh Firebase token.
router.post("/reauth", requireAuth, async (req, res) => {
  const password = String(req.body?.password || "");
  if (!(await bcrypt.compare(password, req.user.passwordHash))) {
    return res.status(401).json({ error: "Incorrect password." });
  }
  return res.json({ firebaseToken: await mintFirebaseToken(req.user) });
});

// POST /auth/password/forgot { email }
router.post("/password/forgot", async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email)) {
    return res.status(400).json({ error: "A valid email is required." });
  }

  // The answer is the same whether or not the address has an account, so
  // this endpoint can't be used to find out who is registered.
  if (!(await prisma.user.findUnique({ where: { email } }))) {
    return res.json({ sent: true });
  }

  const { devOtp, error } = await issueOtp(email, "reset");
  if (error) return res.status(error.status).json({ error: error.message });
  return res.json({ sent: true, otp: devOtp });
});

// POST /auth/password/reset { email, otp, newPassword }
router.post("/password/reset", async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  const otp = String(req.body?.otp || "").trim();
  const newPassword = String(req.body?.newPassword || "");
  if (newPassword.length < MIN_PASSWORD_LENGTH || newPassword.length > 200) {
    return res.status(400).json({ error: PASSWORD_MESSAGE });
  }

  const { error } = await checkOtp(email, "reset", otp);
  if (error) return res.status(400).json({ error });

  const passwordHash = await bcrypt.hash(newPassword, 10);
  // A reset also signs the account out everywhere (tokenVersion + 1).
  const { count } = await prisma.user.updateMany({
    where: { email },
    data: { passwordHash, tokenVersion: { increment: 1 } },
  });
  if (count === 0) return res.status(400).json({ error: "That code is not valid. Please request a new one." });
  await prisma.otpCode.deleteMany({ where: { email, purpose: "reset" } });
  return res.json({ reset: true });
});

// POST /auth/logout -- nothing to do server side (the app drops its token);
// kept so every client can call the same pair of endpoints.
router.post("/logout", (req, res) => {
  res.json({ ok: true });
});

// POST /auth/logout-all -- signs the account out on every device, this one
// included: every token issued so far carries the old tokenVersion.
router.post("/logout-all", requireAuth, async (req, res) => {
  await prisma.user.update({ where: { id: req.user.id }, data: { tokenVersion: { increment: 1 } } });
  res.json({ ok: true });
});

module.exports = router;
// Shared with routes/users.js (password change returns a fresh token).
module.exports.signToken = signToken;
module.exports.MIN_PASSWORD_LENGTH = MIN_PASSWORD_LENGTH;
