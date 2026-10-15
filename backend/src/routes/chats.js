const express = require("express");
const rateLimit = require("express-rate-limit");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
const { notifyCompany, companyUserIds } = require("../lib/teamNotify");
const {
  loadParties,
  swipeInfo,
  toWith,
  companyName,
  hasRightSwipe,
  companyContacted,
  toChatMessage,
  iso,
} = require("../lib/pairSerializers");

// Chat between a company (a recruiter user) and a candidate. One thread per
// pair across all jobs. The company side may message anyone it right-swiped;
// the candidate may only answer once the company has reached out.

const router = express.Router();
router.use(requireAuth);

const MAX_TEXT = 2000;
const THREAD_LIMIT = 200;

// 30 messages a minute per user, 20 group sends an hour. Keyed by user id (these
// routes sit behind requireAuth), not IP, so one office network is not one bucket.
const sendLimiter = rateLimit({
  windowMs: 60 * 1000,
  limit: Number(process.env.CHAT_SEND_RATE_LIMIT) || 30,
  keyGenerator: (req) => req.user.id,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  message: { error: "You are sending messages too fast, please slow down" },
});

const bulkLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  limit: Number(process.env.CHAT_BULK_RATE_LIMIT) || 20,
  keyGenerator: (req) => req.user.id,
  standardHeaders: "draft-8",
  legacyHeaders: false,
  message: { error: "You have sent a lot of group messages, please try again in an hour" },
});

const isCompany = (user) => user.role === "recruiter";

// `{ companyId, candidateId }` for the pair, from the viewer's point of view.
// A team member talks as the company (the owner's id).
function pairOf(viewer, otherId) {
  return isCompany(viewer) ? { companyId: viewer.companyId, candidateId: otherId } : { companyId: otherId, candidateId: viewer.id };
}

// The id the viewer's side of the pair goes by: the company id for any
// teammate, the user id for a candidate.
const selfIdOf = (viewer) => (isCompany(viewer) ? viewer.companyId : viewer.id);

// "What the other side sent": for a company viewer that is the candidate's
// messages (any teammate's are the company's own); for a candidate it is
// everything they did not send themselves.
function incomingFilter(viewer, otherId) {
  return isCompany(viewer) ? { senderId: otherId } : { senderId: { not: viewer.id } };
}

async function senderNames(rows) {
  const ids = [...new Set(rows.map((r) => r.senderId))];
  if (!ids.length) return new Map();
  const users = await prisma.user.findMany({ where: { id: { in: ids } }, select: { id: true, name: true } });
  return new Map(users.map((u) => [u.id, u.name]));
}

function validText(raw) {
  const text = typeof raw === "string" ? raw.trim() : "";
  if (!text) return { error: "Message cannot be empty" };
  if (text.length > MAX_TEXT) return { error: `Message is too long (max ${MAX_TEXT} characters)` };
  return { text };
}

// The other side must be a user of the opposite role.
async function findOther(viewer, otherId) {
  const other = await prisma.user.findUnique({
    where: { id: String(otherId) },
    select: {
      id: true,
      name: true,
      role: true,
      company: true,
      candidateProfile: { select: { desiredRole: true, photoUrl: true } },
      companyProfile: { select: { name: true, industry: true, logoUrl: true, verificationStatus: true } },
    },
  });
  if (!other || other.role === viewer.role) return null;
  return other;
}

// Stores the message and does every side effect of a send (stage move,
// notification). Callers have already checked permission.
async function deliver({ sender, recipientId, text, senderName }) {
  const senderIsCompany = isCompany(sender);
  const { companyId, candidateId } = pairOf(sender, recipientId);
  // The other side knows this conversation by the company id (owner) or the candidate id.
  const link = `/messages?with=${senderIsCompany ? companyId : candidateId}`;

  // One unread `message` notification per sender at a time: while the last
  // one is still unread, further messages only push, they don't fill the
  // bell and don't email again.
  const alreadyUnread = senderIsCompany
    ? await prisma.notification.findFirst({
        where: { userId: recipientId, type: "message", link, readAt: null },
        select: { id: true },
      })
    : null;

  const message = await prisma.chatMessage.create({
    data: { companyId, candidateId, senderId: sender.id, text },
  });

  if (senderIsCompany) {
    await prisma.candidateSwipe.updateMany({
      where: { recruiterId: companyId, candidateId, action: "right", stage: "shortlisted" },
      data: { stage: "contacted" },
    });
  }

  // The bell row is written before returning so the next message in a quick
  // exchange sees it; push and email follow in the background.
  const title = `New message from ${senderName}`;
  const body = text.slice(0, 120);
  if (senderIsCompany) {
    if (!alreadyUnread) {
      await prisma.notification.create({ data: { userId: recipientId, type: "message", title, body, link } });
    }
    inBackground(notify(recipientId, { title, body, type: "message", link, inbox: false, email: !alreadyUnread }));
  } else {
    // A candidate wrote to the company: the owner and every teammate hear
    // about it (each with the same once-while-unread rule).
    await notifyCompany(companyId, { title, body, type: "message", link, email: true }, { dedupeUnread: true });
  }
  return message;
}

// -------------------------------------------------------------- lists --

// GET /chats -> { conversations }
router.get("/", async (req, res) => {
  const viewer = req.user;
  const viewerIsCompany = isCompany(viewer);
  const mine = viewerIsCompany ? { companyId: viewer.companyId } : { candidateId: viewer.id };
  const otherField = viewerIsCompany ? "candidateId" : "companyId";

  const lastMessages = await prisma.chatMessage.findMany({
    where: mine,
    orderBy: { createdAt: "desc" },
    distinct: [otherField],
    take: 200,
  });
  if (!lastMessages.length) return res.json({ conversations: [] });

  const otherIds = lastMessages.map((m) => m[otherField]);
  const teamIds = viewerIsCompany ? await companyUserIds(viewer.companyId) : [];
  const [unreadRows, parties, swipes] = await Promise.all([
    prisma.chatMessage.groupBy({
      by: [otherField],
      // From the other side: for a company, anyone who is not on the team.
      where: { ...mine, senderId: viewerIsCompany ? { notIn: teamIds } : { not: viewer.id }, readAt: null },
      _count: { _all: true },
    }),
    loadParties(otherIds),
    swipeInfo(selfIdOf(viewer), viewerIsCompany, otherIds),
  ]);
  const unread = new Map(unreadRows.map((r) => [r[otherField], r._count._all]));

  const conversations = lastMessages.map((m) => {
    const otherId = m[otherField];
    const info = swipes.get(otherId);
    return {
      id: otherId,
      ...toWith(parties.get(otherId), viewerIsCompany, { jobTitle: info?.jobTitle || "" }),
      stage: info?.stage ?? null,
      lastMessage: {
        text: m.text,
        at: iso(m.createdAt),
        mine: viewerIsCompany ? m.senderId !== m.candidateId : m.senderId === viewer.id,
      },
      unread: unread.get(otherId) ?? 0,
      updatedAt: iso(m.createdAt),
    };
  });
  res.json({ conversations });
});

// GET /chats/contacts -> { contacts }: everyone this user may start / continue a chat with.
router.get("/contacts", async (req, res) => {
  const viewer = req.user;
  const viewerIsCompany = isCompany(viewer);
  const mine = viewerIsCompany ? { companyId: viewer.companyId } : { candidateId: viewer.id };
  const otherField = viewerIsCompany ? "candidateId" : "companyId";

  let otherIds;
  if (viewerIsCompany) {
    const rows = await prisma.candidateSwipe.findMany({
      where: { recruiterId: viewer.companyId, action: "right" },
      select: { candidateId: true },
      distinct: ["candidateId"],
    });
    otherIds = rows.map((r) => r.candidateId);
  } else {
    // Companies that have reached out: a message from them, an interview or a task.
    const [msgs, interviews, tasks] = await Promise.all([
      prisma.chatMessage.findMany({
        where: { candidateId: viewer.id, NOT: { senderId: viewer.id } },
        select: { companyId: true },
        distinct: ["companyId"],
      }),
      prisma.interview.findMany({ where: { candidateId: viewer.id }, select: { companyId: true }, distinct: ["companyId"] }),
      prisma.hiringTask.findMany({ where: { candidateId: viewer.id }, select: { companyId: true }, distinct: ["companyId"] }),
    ]);
    otherIds = [...new Set([...msgs, ...interviews, ...tasks].map((r) => r.companyId))];
  }
  if (!otherIds.length) return res.json({ contacts: [] });

  const [parties, swipes, lastRows] = await Promise.all([
    loadParties(otherIds),
    swipeInfo(selfIdOf(viewer), viewerIsCompany, otherIds),
    prisma.chatMessage.groupBy({
      by: [otherField],
      where: { ...mine, [otherField]: { in: otherIds } },
      _max: { createdAt: true },
    }),
  ]);
  const lastAt = new Map(lastRows.map((r) => [r[otherField], r._max.createdAt]));

  const contacts = otherIds
    .filter((id) => parties.has(id))
    .map((id) => {
      const info = swipes.get(id);
      const last = lastAt.get(id) || null;
      const touched = [info?.updatedAt, last].filter(Boolean).sort((a, b) => b - a)[0] || null;
      return {
        id,
        ...toWith(parties.get(id), viewerIsCompany, { jobTitle: info?.jobTitle || "" }),
        stage: info?.stage ?? null,
        updatedAt: iso(touched),
        hasChat: last != null,
      };
    })
    .sort((a, b) => String(b.updatedAt).localeCompare(String(a.updatedAt)));
  res.json({ contacts });
});

// GET /chats/unread-count -> { count }
router.get("/unread-count", async (req, res) => {
  const company = isCompany(req.user);
  const mine = company ? { companyId: req.user.companyId } : { candidateId: req.user.id };
  const teamIds = company ? await companyUserIds(req.user.companyId) : [];
  const count = await prisma.chatMessage.count({
    where: { ...mine, senderId: company ? { notIn: teamIds } : { not: req.user.id }, readAt: null },
  });
  res.json({ count });
});

// ------------------------------------------------------------- bulk --

// POST /chats/bulk { text, candidateIds[1..50] } -> 201 { sent, skipped }
router.post(
  "/bulk",
  (req, res, next) =>
    isCompany(req.user) ? next() : res.status(403).json({ error: "Only companies can message several candidates at once" }),
  bulkLimiter,
  async (req, res) => {
    const checked = validText(req.body?.text);
    if (checked.error) return res.status(400).json({ error: checked.error, field: "text" });

    const raw = Array.isArray(req.body?.candidateIds) ? req.body.candidateIds : [];
    const ids = [...new Set(raw.filter((v) => typeof v === "string" && v.trim()).map((v) => v.trim()))];
    if (ids.length < 1 || ids.length > 50) {
      return res.status(400).json({ error: "Choose between 1 and 50 candidates", field: "candidateIds" });
    }

    const allowedRows = await prisma.candidateSwipe.findMany({
      where: { recruiterId: req.user.companyId, candidateId: { in: ids }, action: "right" },
      select: { candidateId: true },
      distinct: ["candidateId"],
    });
    const allowed = new Set(allowedRows.map((r) => r.candidateId));
    const skipped = ids.filter((id) => !allowed.has(id));
    const targets = ids.filter((id) => allowed.has(id));

    const senderName = companyName({ ...req.user, companyProfile: await prisma.company.findUnique({ where: { ownerId: req.user.companyId } }) });
    let sent = 0;
    for (const candidateId of targets) {
      await deliver({ sender: req.user, recipientId: candidateId, text: checked.text, senderName });
      sent += 1;
    }
    res.status(201).json({ sent, skipped });
  },
);

// ----------------------------------------------------------- thread --

// GET /chats/:otherId -> { with, messages }  (marks the other side's messages read)
router.get("/:otherId", async (req, res) => {
  const viewer = req.user;
  const viewerIsCompany = isCompany(viewer);
  const other = await findOther(viewer, req.params.otherId);
  if (!other) return res.status(404).json({ error: "Conversation not found" });

  const pair = pairOf(viewer, other.id);
  const hasMessages = await prisma.chatMessage.findFirst({ where: pair, select: { id: true } });
  if (!hasMessages) {
    // Opening an empty thread is fine only for pairs that are allowed to talk.
    const allowed = viewerIsCompany
      ? await hasRightSwipe(viewer.companyId, other.id)
      : await companyContacted(other.id, viewer.id);
    if (!allowed) {
      return res.status(403).json({
        error: viewerIsCompany ? "You can only message candidates you have shortlisted" : "This company has not contacted you yet",
      });
    }
  }

  const readAt = new Date();
  await Promise.all([
    prisma.chatMessage.updateMany({ where: { ...pair, ...incomingFilter(viewer, other.id), readAt: null }, data: { readAt } }),
    // The bell entry for this conversation is handled too; the next message
    // from them raises a fresh one.
    prisma.notification.updateMany({
      where: { userId: viewer.id, type: "message", link: `/messages?with=${other.id}`, readAt: null },
      data: { readAt },
    }),
  ]);

  const rows = await prisma.chatMessage.findMany({ where: pair, orderBy: { createdAt: "desc" }, take: THREAD_LIMIT });
  const info = (await swipeInfo(selfIdOf(viewer), viewerIsCompany, [other.id])).get(other.id);
  const names = viewerIsCompany ? await senderNames(rows) : null;
  res.json({
    with: toWith(other, viewerIsCompany, { jobTitle: info?.jobTitle || "" }),
    messages: rows.reverse().map((m) => toChatMessage(m, viewer.id, { company: viewerIsCompany, names })),
  });
});

// POST /chats/:otherId { text } -> 201 { message }
router.post("/:otherId", sendLimiter, async (req, res) => {
  const viewer = req.user;
  const viewerIsCompany = isCompany(viewer);
  const other = await findOther(viewer, req.params.otherId);
  if (!other) return res.status(404).json({ error: "Conversation not found" });

  const checked = validText(req.body?.text);
  if (checked.error) return res.status(400).json({ error: checked.error, field: "text" });

  if (viewerIsCompany) {
    if (!(await hasRightSwipe(viewer.companyId, other.id))) {
      return res.status(403).json({ error: "You can only message candidates you have shortlisted" });
    }
  } else if (!(await companyContacted(other.id, viewer.id))) {
    return res.status(403).json({ error: "This company has not contacted you yet" });
  }

  const senderName = viewerIsCompany
    ? companyName({ ...viewer, companyProfile: await prisma.company.findUnique({ where: { ownerId: viewer.companyId } }) })
    : viewer.name;
  const message = await deliver({ sender: viewer, recipientId: other.id, text: checked.text, senderName });
  res.status(201).json({ message: toChatMessage(message, viewer.id, { company: viewerIsCompany }) });
});

module.exports = router;
