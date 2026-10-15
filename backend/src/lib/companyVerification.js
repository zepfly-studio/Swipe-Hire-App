// Company verification (phase 4): GST review by an admin, and the instant
// work-email code. The automatic domain check (lib/company.js) still runs on
// every profile save by the owner.
//
// State lives on the Company row:
//   verificationStatus  unverified | pending | verified | rejected
//   verificationMethod  email | gst | ""
//   gstin               the GSTIN of the last request
//   verificationOtp     { hash, expires, sentAt, tries, sends, fails, windowStart,
//                         gstRequestedAt }   (hash = sha256 of the 6-digit code)

const crypto = require("crypto");
const { prisma } = require("./prisma");
const { notify } = require("./notify");
const mailer = require("./mailer");
const { domainFromEmail, domainFromUrl, domainsMatch, isFreeMail } = require("./company");

const GSTIN_RE = /^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$/;
const CODE_TTL_MS = 10 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_TRIES_PER_CODE = 5;
const MAX_SENDS_PER_DAY = 5;
const MAX_FAILS_PER_DAY = 15;

const MESSAGES = {
  alreadyVerified: "Your company is already verified",
  freeMail: "Your login email is a personal email. Use GST verification, or sign up with your work email.",
  noWebsite: "Add your company website in your company profile first, so we can match your email to it.",
  tooManyCodes: "Too many codes requested today. Please try again tomorrow, or use GST verification.",
  expired: "Code expired, please request a new one",
  tooManyTries: "Too many wrong attempts, please request a new code",
  wrong: "Wrong code, please check and try again",
  sendFailed: "We couldn't send the email right now. Please try again in a minute.",
};

const fail = (status, error, field) => ({ error: { status, message: error, field } });

function hashCode(code) {
  return crypto.createHash("sha256").update(String(code)).digest("hex");
}

function normalizeGstin(value) {
  return typeof value === "string" ? value.trim().toUpperCase() : "";
}

function isValidGstin(gstin) {
  return GSTIN_RE.test(gstin);
}

// What the app and the admin list read: "unverified" is shown as "none".
function publicStatus(company) {
  return company.verificationStatus === "unverified" ? "none" : company.verificationStatus;
}

function methodOf(company) {
  if (company.verificationMethod) return company.verificationMethod;
  // Companies verified by the domain check before methods existed.
  return company.verificationStatus === "verified" && company.verificationNote === "domain" ? "email" : "";
}

function verificationView(company) {
  return {
    status: publicStatus(company),
    method: methodOf(company),
    verifiedAt: company.verifiedAt ? company.verifiedAt.toISOString() : null,
  };
}

/** Ids of the owner and every team member (everyone who should hear about the company). */
async function teamUserIds(companyId) {
  const members = await prisma.user.findMany({ where: { companyOwnerId: companyId }, select: { id: true } });
  return [companyId, ...members.map((m) => m.id)];
}

async function notifyTeam(companyId, event) {
  const ids = await teamUserIds(companyId);
  await Promise.all(ids.map((id) => notify(id, event)));
}

const VERIFIED_EVENT = (name) => ({
  type: "verified",
  title: "Your company is verified ✓",
  body: `${name} now has the verified badge. Candidates will see it on your jobs and profile.`,
  link: "/company/verify",
  email: true,
});

const REJECTED_EVENT = (name) => ({
  type: "verified",
  title: "Verification was not approved",
  body: `We could not verify ${name} with the details you submitted. Please check your GSTIN, or verify with your work email.`,
  link: "/company/verify",
  email: true,
});

function isoOrNull(ms) {
  return ms ? new Date(ms).toISOString() : null;
}

// The daily counters of an OTP state, rolled over when the 24h window ended.
function withWindow(state, now) {
  const start = state?.windowStart ? Date.parse(state.windowStart) : 0;
  if (!start || now - start >= DAY_MS) {
    return { ...(state || {}), windowStart: new Date(now).toISOString(), sends: 0, fails: 0 };
  }
  return { ...state, sends: state.sends ?? 0, fails: state.fails ?? 0 };
}

/** A GST review request: the company becomes `pending` until an admin decides. */
async function requestGst(company, gstin) {
  const state = company.verificationOtp && typeof company.verificationOtp === "object" ? company.verificationOtp : {};
  const updated = await prisma.company.update({
    where: { id: company.id },
    data: {
      verificationStatus: "pending",
      verificationMethod: "gst",
      gstin,
      verifiedAt: null,
      verificationOtp: { ...state, gstRequestedAt: new Date().toISOString() },
    },
  });
  return updated;
}

/**
 * Emails a 6-digit code to the caller's login email.
 * @returns {{ sentTo, devCode? } | { error: { status, message, field? } }}
 */
async function sendEmailCode(company, email) {
  if (company.verificationStatus === "verified") return fail(409, MESSAGES.alreadyVerified);

  const emailDomain = domainFromEmail(email);
  if (!emailDomain || isFreeMail(emailDomain)) return fail(400, MESSAGES.freeMail);
  const siteDomain = domainFromUrl(company.website);
  if (!siteDomain) return fail(400, MESSAGES.noWebsite);
  if (!domainsMatch(siteDomain, emailDomain)) {
    return fail(400, `Your email (@${emailDomain}) does not match your website (${siteDomain}).`);
  }

  const now = Date.now();
  const previous = company.verificationOtp && typeof company.verificationOtp === "object" ? company.verificationOtp : {};
  const windowed = withWindow(previous, now);
  if (windowed.sends >= MAX_SENDS_PER_DAY || windowed.fails >= MAX_FAILS_PER_DAY) {
    return fail(429, MESSAGES.tooManyCodes);
  }

  const code = String(crypto.randomInt(100000, 1000000));
  const next = {
    ...windowed,
    hash: hashCode(code),
    expires: isoOrNull(now + CODE_TTL_MS),
    sentAt: isoOrNull(now),
    tries: 0,
    sends: windowed.sends + 1,
  };

  const production = process.env.NODE_ENV === "production";
  const mayShowCode = !production || process.env.OTP_DEV_FALLBACK === "true";
  let devCode;

  if (!mailer.emailConfigured()) {
    if (!mayShowCode) return fail(502, MESSAGES.sendFailed);
    console.log(`[verification] code for ${email}: ${code}`);
    devCode = code;
  } else {
    try {
      await mailer.sendNotificationEmail({
        to: email,
        subject: `${code} is your GlideRecruit code`,
        heading: "Verify your company email",
        body: `Your GlideRecruit verification code is ${code}\nIt expires in 10 minutes. If you did not ask for this, you can ignore this email.`,
      });
    } catch (err) {
      // Resend's shared test sender only delivers to the account owner.
      const testSenderRestriction = err.response?.body?.statusCode === 403;
      if (testSenderRestriction && mayShowCode) {
        console.warn(`[verification] email to ${email} refused by the test sender; returning the code to the app.`);
        console.log(`[verification] code for ${email}: ${code}`);
        devCode = code;
      } else {
        console.error(`[verification] email send failed for ${email}:`, err.response?.body || err.message);
        return fail(502, MESSAGES.sendFailed);
      }
    }
  }

  await prisma.company.update({ where: { id: company.id }, data: { verificationOtp: next } });
  const result = { sentTo: email };
  if (devCode) result.devCode = devCode;
  return result;
}

/**
 * Checks a code. Every attempt is counted BEFORE the code is compared, with a
 * compare-and-set on the stored state, so parallel guesses cannot exceed the
 * per-code limit.
 * @returns {{ company } | { error }}
 */
async function confirmEmailCode(companyId, code) {
  const submitted = typeof code === "string" ? code.trim() : "";

  for (let attempt = 0; attempt < 5; attempt++) {
    const company = await prisma.company.findUnique({ where: { id: companyId } });
    if (!company) return fail(404, "Company not found.");
    if (company.verificationStatus === "verified") return { company };

    const state = company.verificationOtp;
    if (!state || typeof state !== "object" || !state.hash || !state.expires || Date.parse(state.expires) < Date.now()) {
      return fail(400, MESSAGES.expired);
    }
    if ((state.tries ?? 0) >= MAX_TRIES_PER_CODE) return fail(429, MESSAGES.tooManyTries);

    const claimed = { ...state, tries: (state.tries ?? 0) + 1, fails: (state.fails ?? 0) + 1 };
    const { count } = await prisma.company.updateMany({
      where: { id: company.id, verificationOtp: { equals: state } },
      data: { verificationOtp: claimed },
    });
    if (count === 0) continue; // somebody else changed the state; look again

    if (!submitted || hashCode(submitted) !== state.hash) return fail(400, MESSAGES.wrong, "code");

    const updated = await prisma.company.update({
      where: { id: company.id },
      data: {
        verificationStatus: "verified",
        verificationMethod: "email",
        verificationNote: "email",
        verifiedAt: new Date(),
        // Keep the daily counters, drop the code itself.
        verificationOtp: { windowStart: state.windowStart, sends: state.sends ?? 0, fails: claimed.fails },
      },
    });
    return { company: updated };
  }
  return fail(429, MESSAGES.tooManyTries);
}

module.exports = {
  MESSAGES,
  hashCode,
  normalizeGstin,
  isValidGstin,
  verificationView,
  teamUserIds,
  notifyTeam,
  VERIFIED_EVENT,
  REJECTED_EVENT,
  requestGst,
  sendEmailCode,
  confirmEmailCode,
};
