const express = require("express");
const { prisma } = require("../lib/prisma");
const { deleteFirebaseUser } = require("../lib/firebase");
const bcrypt = require("bcryptjs");
const { requireAuth } = require("../middleware/requireAuth");
const { signToken, MIN_PASSWORD_LENGTH } = require("./auth");
const { str, bool, requireRole } = require("../lib/validate");
const {
  toProfile,
  toCandidateProfile,
  toJobPosting,
  toOpportunity,
  OPPORTUNITY_INCLUDE,
  POSTING_INCLUDE,
} = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

// GET /users/me
router.get("/me", (req, res) => {
  res.json(toProfile(req.user));
});

// PATCH /users/me { name, company, designation, phone, profileComplete }
router.patch("/me", async (req, res) => {
  const data = {};
  for (const field of ["name", "company", "designation", "phone"]) {
    if (typeof req.body?.[field] === "string") data[field] = str(req.body[field], 200);
  }
  // The company name belongs to the hiring account (see PUT /company/me); a
  // team member's own account does not get to change it.
  if (req.user.role === "recruiter" && !req.user.isOwner) delete data.company;
  if (data.phone && !/^\+?\d{10,13}$/.test(data.phone.replace(/[\s\-()]/g, ""))) {
    return res.status(400).json({ error: "Enter a valid phone number (10 digits)." });
  }
  if (data.designation && !/^[A-Za-z][A-Za-z0-9 .,&/'()-]{1,59}$/.test(data.designation)) {
    return res.status(400).json({ error: "Enter a valid designation, e.g. HR Manager." });
  }
  if (typeof req.body?.profileComplete === "boolean") {
    data.profileComplete = bool(req.body.profileComplete);
  }
  if (typeof req.body?.emailNotifications === "boolean") {
    data.emailNotifications = req.body.emailNotifications;
  }

  const user = await prisma.user.update({ where: { id: req.user.id }, data });
  res.json(toProfile(user));
});

// PUT /users/me/password { current, next } -> { ok:true, token }
// Bumps tokenVersion, so every other device is signed out; this one keeps
// working with the fresh `token` in the response.
router.put("/me/password", async (req, res) => {
  const current = typeof req.body?.current === "string" ? req.body.current : "";
  const next = typeof req.body?.next === "string" ? req.body.next : "";

  if (next.length < MIN_PASSWORD_LENGTH || next.length > 200) {
    return res
      .status(400)
      .json({ error: `New password must be at least ${MIN_PASSWORD_LENGTH} characters`, field: "next" });
  }
  if (!(await bcrypt.compare(current, req.user.passwordHash))) {
    return res.status(400).json({ error: "Your current password is not correct", field: "current" });
  }

  const passwordHash = await bcrypt.hash(next, 10);
  const user = await prisma.user.update({
    where: { id: req.user.id },
    data: { passwordHash, tokenVersion: { increment: 1 } },
  });
  res.json({ ok: true, token: signToken(user) });
});

// PUT /users/me/fcm-token { token } -- device registration for push.
router.put("/me/fcm-token", async (req, res) => {
  const token = str(req.body?.token, 4096);
  await prisma.user.update({ where: { id: req.user.id }, data: { fcmToken: token || null } });
  res.json({ saved: true });
});

// GET /users/me/export -- everything this account owns, for "Export my data".
router.get("/me/export", async (req, res) => {
  const uid = req.user.id;
  const out = {
    exportedAt: new Date().toISOString(),
    account: {
      uid,
      email: req.user.email,
      emailVerified: req.user.emailVerified,
      createdAt: req.user.createdAt.toISOString(),
    },
    profile: toProfile(req.user),
  };

  if (req.user.role === "candidate") {
    const profile = await prisma.candidateProfile.findUnique({ where: { userId: uid } });
    out.candidateProfile = profile ? toCandidateProfile(profile) : null;
    const opportunities = await prisma.opportunity.findMany({
      where: { candidateId: uid },
      include: OPPORTUNITY_INCLUDE,
      orderBy: { updatedAt: "desc" },
    });
    out.hiringActivity = opportunities.map(toOpportunity);
    const saved = await prisma.savedJob.findMany({ where: { candidateId: uid } });
    out.savedJobIds = saved.map((s) => s.jobPostingId);
  } else {
    const opportunities = await prisma.opportunity.findMany({
      where: { recruiterId: uid },
      include: OPPORTUNITY_INCLUDE,
      orderBy: { updatedAt: "desc" },
    });
    out.pipeline = opportunities.map(toOpportunity);
    // Postings belong to the hiring account (the owner's id for a team member).
    const postings = await prisma.jobPosting.findMany({ where: { recruiterId: req.user.companyId }, include: POSTING_INCLUDE });
    out.jobPostings = postings.map(toJobPosting);
    const swipes = await prisma.swipe.findMany({ where: { recruiterId: uid } });
    out.swipes = swipes.map((s) => ({ candidateUid: s.candidateId, state: s.state, at: s.updatedAt.toISOString() }));
  }

  res.json(out);
});

// GET /users/candidates/lookup?email= -- recruiter finds a candidate account
// by exact email to start a pipeline entry with.
router.get("/candidates/lookup", requireRole("recruiter"), async (req, res) => {
  const email = str(req.query.email, 320).toLowerCase();
  if (!email) return res.status(400).json({ error: "email is required." });
  const user = await prisma.user.findFirst({ where: { email, role: "candidate" } });
  if (!user) return res.status(404).json({ error: "No candidate account uses that email." });
  res.json(toProfile(user));
});

// DELETE /users/me -- Postgres cascades delete the profile, postings,
// opportunities, messages, saved jobs and swipes; then the Firebase Auth
// record goes too.
router.delete("/me", async (req, res) => {
  await prisma.user.delete({ where: { id: req.user.id } });
  await deleteFirebaseUser(req.user.id);
  res.json({ deleted: true });
});

module.exports = router;
