// Helpers for the phase 4 team tests. Members join through the real invite
// endpoints; every account uses h.emailFor(), so h.stop() removes them.

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const h = require("./helpers");
const hc = require("./hiring-helpers");

// Lets POST /team/invite hand the code back even though email "works" in tests.
process.env.OTP_DEV_FALLBACK = "true";

const { api, prisma } = h;

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");

/** An invite code for `email`, issued by the owner. */
async function invite(owner, email = h.emailFor("recruiter")) {
  const res = await api("POST", "/team/invite", { token: owner.token, body: { email } });
  assert.equal(res.status, 201, JSON.stringify(res.json));
  assert.ok(res.json.inviteCode, "the dev fallback returns the invite code");
  return { email, code: res.json.inviteCode };
}

/** Invite + accept. Returns { token, uid, email, name, user, firebaseToken }. */
async function joinTeam(owner, name = "Mia Member", { password = "password123" } = {}) {
  const { email, code } = await invite(owner);
  const res = await api("POST", "/auth/accept-invite", { body: { token: code, name, password } });
  assert.equal(res.status, 201, JSON.stringify(res.json));
  return { token: res.json.token, uid: res.json.user.uid, email, name, password, user: res.json.user, firebaseToken: res.json.firebaseToken };
}

/** A recruiter owner with a job and plenty of swipes. */
async function ownerWithJob(name = "Olivia Owner", options = {}) {
  const { rec, job } = await hc.recruiterWithJob(name, options);
  return { owner: rec, job };
}

const notificationsFor = (userId, type) =>
  prisma.notification.findMany({ where: { userId, ...(type ? { type } : {}) }, orderBy: { createdAt: "asc" } });

module.exports = { ...hc, h, sha256, invite, joinTeam, ownerWithJob, notificationsFor };
