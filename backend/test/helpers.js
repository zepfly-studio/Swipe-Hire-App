// Shared test harness: fakes for Firebase and Resend (installed before the
// app is loaded), an in-process server, and small request helpers.
//
// Needs DATABASE_URL pointing at a DEVELOPMENT database; every account the
// tests create is named e2e.* and removed afterwards.

process.env.NODE_ENV = "test";
process.env.JWT_SECRET = process.env.JWT_SECRET || "test-secret-test-secret-test-secret!!";

require("dotenv").config();
process.env.RESEND_API_KEY = "test-key";
process.env.RESEND_FROM_EMAIL = "no-reply@test.invalid";
// The suite signs up dozens of accounts from one address.
process.env.AUTH_RATE_LIMIT = "100000";
process.env.API_RATE_LIMIT = "100000";

const path = require("path");
const assert = require("node:assert/strict");

function installFake(relativePath, exports) {
  const resolved = require.resolve(path.join(__dirname, "..", relativePath));
  require.cache[resolved] = { id: resolved, filename: resolved, loaded: true, exports };
}

/** Everything the app tried to push / email / delete in Firebase. */
const pushes = [];
const emails = [];
const deletedFirebaseUsers = [];
/** Set by a test to what `verifyIdToken` should return (or throw). */
const googleClaims = { next: null };

installFake("src/lib/firebase.js", {
  mintFirebaseToken: async (user) => `firebase-token-${user.id}`,
  ensureFirebaseUser: async () => {},
  deleteFirebaseUser: async (uid) => {
    deletedFirebaseUsers.push(uid);
  },
  verifyIdToken: async () => {
    if (!googleClaims.next) throw new Error("invalid token");
    return googleClaims.next;
  },
  sendPush: async (token, payload) => {
    pushes.push({ token, ...payload });
  },
});

installFake("src/lib/mailer.js", {
  emailConfigured: () => true,
  sendOtpEmail: async (message) => {
    emails.push({ kind: "otp", ...message });
  },
  sendNotificationEmail: async (message) => {
    emails.push({ kind: "notification", ...message });
  },
});

const { createApp } = require("../src/app");
const { prisma } = require("../src/lib/prisma");
const { idle } = require("../src/lib/notify");

const PREFIX = `e2e.${Date.now()}`;
let server;
let base;
let counter = 0;

async function start() {
  server = createApp().listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  base = `http://127.0.0.1:${server.address().port}`;
}

async function stop() {
  await prisma.user.deleteMany({ where: { email: { startsWith: PREFIX } } });
  await new Promise((resolve) => server.close(resolve));
  await prisma.$disconnect();
}

async function api(method, route, { body, token } = {}) {
  const res = await fetch(base + route, {
    method,
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

// The most recent code the app issued for this address, read straight from
// the database (the HTTP response never carries it when email is configured).
async function latestOtp(email, purpose = "signup") {
  const row = await prisma.otpCode.findFirst({ where: { email, purpose }, orderBy: { createdAt: "desc" } });
  return row?.code;
}

function emailFor(role, domain = "example.net") {
  return `${PREFIX}.${role}.${++counter}@${domain}`;
}

async function signup(role, name, { password = "password123", domain, company } = {}) {
  const email = emailFor(role, domain);
  const sent = await api("POST", "/auth/otp/send", { body: { email } });
  assert.equal(sent.status, 200, JSON.stringify(sent.json));
  const verified = await api("POST", "/auth/otp/verify", { body: { email, otp: await latestOtp(email) } });
  assert.equal(verified.status, 200);
  const res = await api("POST", "/auth/signup", {
    body: { name, email, password, role, company: company ?? (role === "recruiter" ? "FlowCorp" : "") },
  });
  assert.equal(res.status, 201, JSON.stringify(res.json));
  return { token: res.json.token, uid: res.json.user.uid, email, password, name };
}

const profileBody = {
  age: 26,
  qualification: "B.Tech, VIT",
  experience: "3 years",
  desiredRole: "Flutter Developer",
  location: "Pune",
  skills: ["Flutter", "Dart"],
  expectedSalaryLpa: 12,
  noticePeriod: "30 days",
};

/** A candidate with a finished profile, ready to show up on the deck. */
async function candidateWithProfile(name, overrides = {}) {
  const user = await signup("candidate", name);
  const put = await api("PUT", "/candidates/me/profile", { token: user.token, body: { ...profileBody, ...overrides } });
  assert.equal(put.status, 200, JSON.stringify(put.json));
  await api("PATCH", "/users/me", { token: user.token, body: { profileComplete: true } });
  return user;
}

async function postJob(recruiter, overrides = {}) {
  const res = await api("POST", "/jobs", {
    token: recruiter.token,
    body: {
      title: "Flutter Developer",
      description: "Build mobile apps",
      skills: ["Flutter", "Dart"],
      location: "Pune",
      employmentType: "Full-time",
      salaryMinLpa: 8,
      salaryMaxLpa: 15,
      minExperienceYears: 2,
      ...overrides,
    },
  });
  assert.equal(res.status, 201, JSON.stringify(res.json));
  return res.json;
}

module.exports = {
  prisma,
  pushes,
  emails,
  deletedFirebaseUsers,
  googleClaims,
  PREFIX,
  start,
  stop,
  api,
  latestOtp,
  emailFor,
  signup,
  profileBody,
  candidateWithProfile,
  postJob,
  /** Waits for notifications sent in the background (push, email). */
  idle,
  getBase: () => base,
};
