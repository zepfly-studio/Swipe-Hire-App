const express = require("express");
const rateLimit = require("express-rate-limit");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
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
function pairOf(viewer, otherId) {
  return isCompany(viewer) ? { companyId: viewer.id, candidateId: otherId } : { companyId: otherId, candidateId: viewer.id };
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
  const link = `/messages?with=${sender.id}`;

  // One unread `message` notification per sender at a time: while the last
  // one is still unread, further messages only push, they don't fill the
  // bell and don't email again.
  const alreadyUnread = await prisma.notification.findFirst({
    where: { userId: recipientId, type: "message", link, readAt: null },
    select: { id: true },
  });

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
  if (!alreadyUnread) {
    await prisma.notification.create({ data: { userId: recipientId, type: "message", title, body, link } });
  }
  inBackground(notify(recipientId, { title, body, type: "message", link, inbox: false, email: !alreadyUnread }));
  return message;
}

// -------------------------------------------------------------- lists --

// GET /chats -> { conversations }
router.get("/", async (req, res) => {
  const viewer = req.user;
  const viewerIsCompany = isCompany(viewer);
  const mine = viewerIsCompany ? { companyId: viewer.id } : { candidateId: viewer.id };
  const otherField = viewerIsCompany ? "candidateId" : "companyId";

  const lastMessages = await prisma.chatMessage.findMany({
    where: mine,
    orderBy: { createdAt: "desc" },
    distinct: [otherField],
    take: 200,
  });
  if (!lastMessages.length) return res.json({ conversations: [] });

  const otherIds = lastMessages.map((m) => m[otherField]);
  const [unreadRows, parties, swipes] = await Promise.all([
    prisma.chatMessage.groupBy({
      by: [otherField],
      where: { ...mine, senderId: { not: viewer.id }, readAt: null },
      _count: { _all: true },
    }),
    loadParties(otherIds),
    swipeInfo(viewer.id, viewerIsCompany, otherIds),
  ]);
  const unread = new Map(unreadRows.map((r) => [r[otherField], r._count._all]));

  const conversations = lastMessages.map((m) => {
    const otherId = m[otherField];
    const info = swipes.get(otherId);
    return {
      id: otherId,
      ...toWith(parties.get(otherId), viewerIsCompany, { jobTitle: info?.jobTitle || "" }),
      stage: info?.stage ?? null,
      lastMessage: { text: m.text, at: iso(m.createdAt), mine: m.senderId === viewer.id },
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
  const mine = viewerIsCompany ? { companyId: viewer.id } : { candidateId: viewer.id };
  const otherField = viewerIsCompany ? "candidateId" : "companyId";

  let otherIds;
  if (viewerIsCompany) {
    const rows = await prisma.candidateSwipe.findMany({
      where: { recruiterId: viewer.id, action: "right" },
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
    swipeInfo(viewer.id, viewerIsCompany, otherIds),
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
  const mine = isCompany(req.user) ? { companyId: req.user.id } : { candidateId: req.user.id };
  const count = await prisma.chatMessage.count({ where: { ...mine, senderId: { not: req.user.id }, readAt: null } });
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
      where: { recruiterId: req.user.id, candidateId: { in: ids }, action: "right" },
      select: { candidateId: true },
      distinct: ["candidateId"],
    });
    const allowed = new Set(allowedRows.map((r) => r.candidateId));
    const skipped = ids.filter((id) => !allowed.has(id));
    const targets = ids.filter((id) => allowed.has(id));

    const senderName = companyName({ ...req.user, companyProfile: await prisma.company.findUnique({ where: { ownerId: req.user.id } }) });
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
      ? await hasRightSwipe(viewer.id, other.id)
      : await companyContacted(other.id, viewer.id);
    if (!allowed) {
      return res.status(403).json({
        error: viewerIsCompany ? "You can only message candidates you have shortlisted" : "This company has not contacted you yet",
      });
    }
  }

  const readAt = new Date();
  await Promise.all([
    prisma.chatMessage.updateMany({ where: { ...pair, senderId: other.id, readAt: null }, data: { readAt } }),
    // The bell entry for this conversation is handled too; the next message
    // from them raises a fresh one.
    prisma.notification.updateMany({
      where: { userId: viewer.id, type: "message", link: `/messages?with=${other.id}`, readAt: null },
      data: { readAt },
    }),
  ]);

  const rows = await prisma.chatMessage.findMany({ where: pair, orderBy: { createdAt: "desc" }, take: THREAD_LIMIT });
  const info = (await swipeInfo(viewer.id, viewerIsCompany, [other.id])).get(other.id);
  res.json({
    with: toWith(other, viewerIsCompany, { jobTitle: info?.jobTitle || "" }),
    messages: rows.reverse().map((m) => toChatMessage(m, viewer.id)),
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
    if (!(await hasRightSwipe(viewer.id, other.id))) {
      return res.status(403).json({ error: "You can only message candidates you have shortlisted" });
    }
  } else if (!(await companyContacted(other.id, viewer.id))) {
    return res.status(403).json({ error: "This company has not contacted you yet" });
  }

  const senderName = viewerIsCompany
    ? companyName({ ...viewer, companyProfile: await prisma.company.findUnique({ where: { ownerId: viewer.id } }) })
    : viewer.name;
  const message = await deliver({ sender: viewer, recipientId: other.id, text: checked.text, senderName });
  res.status(201).json({ message: toChatMessage(message, viewer.id) });
});

module.exports = router;
