// Teams (phase 4). A recruiter account owns a company; the owner can invite
// other people who then work inside it with their own login. Members share
// everything keyed by the owner's id (see "Team rule" in
// docs/PHASE4_CONTRACT.md); only the owner invites/removes people.
//
//   team  -> mounted at /team  (list, invite, remove)
//   auth  -> mounted at /auth  (GET /auth/invite/:token, POST /auth/accept-invite)

const crypto = require("crypto");
const express = require("express");
const bcrypt = require("bcryptjs");
const jwt = require("jsonwebtoken");
const { Prisma } = require("@prisma/client");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { requireRole } = require("../lib/validate");
const { toProfile } = require("../lib/serializers");
const { mintFirebaseToken, ensureFirebaseUser, deleteFirebaseUser } = require("../lib/firebase");
const { emailConfigured, sendNotificationEmail } = require("../lib/mailer");

const team = express.Router();
const auth = express.Router();

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_TEAM_SIZE = 10;
const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MIN_PASSWORD_LENGTH = 8;
const INVALID_INVITE = "This invite link is invalid or has expired. Ask your team for a new one.";
const OWNER_ONLY = "Only the account owner can invite or remove people.";

const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");

function ownerOnly(req, res, next) {
  if (!req.user.isOwner) return res.status(403).json({ error: OWNER_ONLY });
  next();
}

async function companyNameOf(owner) {
  const company = await prisma.company.findUnique({ where: { ownerId: owner.id }, select: { name: true } });
  return company?.name || owner.company || owner.name || "your company";
}

// ------------------------------------------------------------ /team --

team.use(requireAuth, requireRole("recruiter"));

// GET /team -> { isOwner, members, invites }
team.get("/", async (req, res) => {
  const companyId = req.user.companyId;
  const [owner, members, invites] = await Promise.all([
    prisma.user.findUnique({ where: { id: companyId } }),
    prisma.user.findMany({ where: { companyOwnerId: companyId }, orderBy: { createdAt: "asc" } }),
    prisma.teamInvite.findMany({
      where: { ownerId: companyId, acceptedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: "asc" },
    }),
  ]);
  const people = [...(owner ? [{ user: owner, role: "owner" }] : []), ...members.map((user) => ({ user, role: "recruiter" }))];
  res.json({
    isOwner: req.user.isOwner,
    members: people.map(({ user, role }) => ({
      id: user.id,
      name: user.name,
      email: user.email,
      role,
      you: user.id === req.user.id,
      joinedAt: user.createdAt.toISOString(),
    })),
    invites: invites.map((i) => ({ id: i.id, email: i.email, expires: i.expiresAt.toISOString() })),
  });
});

// POST /team/invite { email } -> 201 { ok, inviteCode? }
team.post("/invite", ownerOnly, async (req, res) => {
  const email = String(req.body?.email || "").trim().toLowerCase();
  if (!EMAIL_PATTERN.test(email) || email.length > 200) {
    return res.status(400).json({ error: "Enter a valid email address", field: "email" });
  }
  if (await prisma.user.findUnique({ where: { email }, select: { id: true } })) {
    return res.status(409).json({ error: "This email already has a Swipe Hire account", field: "email" });
  }

  const ownerId = req.user.id;
  const now = new Date();
  // A new invite for the same address replaces the older pending one.
  await prisma.teamInvite.deleteMany({ where: { ownerId, email, acceptedAt: null } });

  const [members, pending] = await Promise.all([
    prisma.user.count({ where: { companyOwnerId: ownerId } }),
    prisma.teamInvite.count({ where: { ownerId, acceptedAt: null, expiresAt: { gt: now } } }),
  ]);
  if (1 + members + pending >= MAX_TEAM_SIZE) {
    return res.status(400).json({ error: `Your team can have up to ${MAX_TEAM_SIZE} people.` });
  }

  const token = crypto.randomBytes(24).toString("base64url");
  await prisma.teamInvite.create({
    data: {
      ownerId,
      email,
      tokenHash: sha256(token),
      invitedById: req.user.id,
      expiresAt: new Date(now.getTime() + INVITE_TTL_MS),
    },
  });

  const companyName = await companyNameOf(req.user);
  let emailed = false;
  if (emailConfigured()) {
    try {
      await sendNotificationEmail({
        to: email,
        subject: `${req.user.name} invited you to join ${companyName} on Swipe Hire`,
        heading: `Join ${companyName} on Swipe Hire`,
        body: [
          `${req.user.name} invited you to hire together as part of ${companyName}.`,
          "Open the Swipe Hire app, tap \"Join a team\" and enter this code:",
          token,
          "The invite is valid for 7 days.",
        ].join("\n"),
      });
      emailed = true;
    } catch (err) {
      console.warn(`[team] invite email to ${email} not sent: ${err.message}`);
    }
  }

  const showCode = !emailConfigured() || process.env.OTP_DEV_FALLBACK === "true";
  return res.status(201).json({ ok: true, ...(showCode || !emailed ? { inviteCode: token } : {}) });
});

// DELETE /team/invites/:id (owner)
team.delete("/invites/:id", ownerOnly, async (req, res) => {
  const result = await prisma.teamInvite.deleteMany({ where: { id: req.params.id, ownerId: req.user.id, acceptedAt: null } });
  if (result.count === 0) return res.status(404).json({ error: "Invite not found" });
  res.json({ ok: true });
});

// DELETE /team/members/:id (owner) -- the person's login is deleted, so
// their token stops working at once (401 "User no longer exists").
team.delete("/members/:id", ownerOnly, async (req, res) => {
  if (req.params.id === req.user.id) return res.status(400).json({ error: "You cannot remove yourself" });
  const member = await prisma.user.findFirst({ where: { id: req.params.id, companyOwnerId: req.user.id } });
  if (!member) return res.status(404).json({ error: "Team member not found" });

  await prisma.$transaction([
    // Chat history belongs to the company: keep what they wrote (it would
    // otherwise cascade away with their login) under the owner.
    prisma.chatMessage.updateMany({ where: { senderId: member.id }, data: { senderId: req.user.id } }),
    prisma.hiringTask.updateMany({ where: { createdById: member.id }, data: { createdById: req.user.id } }),
    prisma.user.delete({ where: { id: member.id } }),
  ]);
  try {
    await deleteFirebaseUser(member.id);
  } catch (err) {
    console.warn(`[team] could not delete the Firebase record of ${member.id}: ${err.message}`);
  }
  res.json({ ok: true });
});

// ------------------------------------------------------------ /auth --

async function findInvite(token) {
  const raw = String(token || "").trim();
  if (!raw || raw.length > 200) return null;
  return prisma.teamInvite.findUnique({ where: { tokenHash: sha256(raw) }, include: { owner: true } });
}

// GET /auth/invite/:token (public) -> { email, companyName }
auth.get("/invite/:token", async (req, res) => {
  const invite = await findInvite(req.params.token);
  if (!invite || invite.acceptedAt || invite.expiresAt.getTime() <= Date.now()) {
    return res.status(404).json({ error: INVALID_INVITE });
  }
  res.json({ email: invite.email, companyName: await companyNameOf(invite.owner) });
});

// POST /auth/accept-invite { token, name, password } -> 201 { token, firebaseToken, user }
auth.post("/accept-invite", async (req, res) => {
  const invite = await findInvite(req.body?.token);
  if (!invite) return res.status(404).json({ error: INVALID_INVITE });
  if (invite.acceptedAt) return res.status(409).json({ error: "This invite was already used" });
  if (invite.expiresAt.getTime() <= Date.now()) return res.status(404).json({ error: INVALID_INVITE });

  const name = String(req.body?.name || "").trim().slice(0, 100);
  const password = String(req.body?.password || "");
  if (!name) return res.status(400).json({ error: "Enter your name.", field: "name" });
  if (password.length < MIN_PASSWORD_LENGTH || password.length > 200) {
    return res.status(400).json({ error: `Choose a password of at least ${MIN_PASSWORD_LENGTH} characters.`, field: "password" });
  }

  const email = invite.email;
  const exists = () => res.status(409).json({ error: "An account with this email already exists" });
  if (await prisma.user.findUnique({ where: { email }, select: { id: true } })) return exists();

  const passwordHash = await bcrypt.hash(password, 10);
  const companyName = await companyNameOf(invite.owner);

  let user;
  try {
    user = await prisma.$transaction(async (tx) => {
      // Claiming the invite and creating the login commit together, so an
      // invite can never be used twice.
      const claimed = await tx.teamInvite.updateMany({
        where: { id: invite.id, acceptedAt: null, expiresAt: { gt: new Date() } },
        data: { acceptedAt: new Date() },
      });
      if (claimed.count !== 1) return null;
      return tx.user.create({
        data: {
          name,
          email,
          passwordHash,
          role: "recruiter",
          company: companyName,
          companyOwnerId: invite.ownerId,
          emailVerified: true,
          profileComplete: true,
        },
      });
    });
  } catch (err) {
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") return exists();
    throw err;
  }
  if (!user) return res.status(409).json({ error: "This invite was already used" });

  // Other pending invites for this address (from other companies) are void now.
  await prisma.teamInvite.deleteMany({ where: { email, acceptedAt: null } });
  await ensureFirebaseUser(user);

  const token = jwt.sign({ sub: user.id, role: user.role, v: user.tokenVersion ?? 0 }, process.env.JWT_SECRET, { expiresIn: "30d" });
  return res.status(201).json({ token, firebaseToken: await mintFirebaseToken(user), user: toProfile(user) });
});

module.exports = { team, auth };
