const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { str, int, requireRole } = require("../lib/validate");
const { toNotification } = require("../lib/serializers");

// The notification bell and the task templates -- small account-level
// resources that don't belong to one opportunity.
const notifications = express.Router();
notifications.use(requireAuth);

// GET /notifications?limit=50&unread=1 -> { notifications, unreadCount }
notifications.get("/", async (req, res) => {
  const limit = Math.min(Math.max(int(req.query.limit, 50), 1), 100);
  const unreadOnly = String(req.query.unread) === "1";
  const rows = await prisma.notification.findMany({
    where: { userId: req.user.id, ...(unreadOnly ? { readAt: null } : {}) },
    orderBy: { createdAt: "desc" },
    take: limit,
  });
  const unreadCount = await prisma.notification.count({ where: { userId: req.user.id, readAt: null } });
  res.json({ notifications: rows.map(toNotification), unreadCount });
});

// GET /notifications/summary -> the two numbers the app's badges show.
notifications.get("/summary", async (req, res) => {
  const unreadNotifications = await prisma.notification.count({ where: { userId: req.user.id, readAt: null } });
  const rows = await prisma.$queryRaw`
    SELECT COUNT(*)::int AS n
    FROM "messages" m
    JOIN "opportunities" o ON o."id" = m."opportunityId"
    WHERE m."senderId" <> ${req.user.id}
      AND m."kind" = 'text'
      AND (
        (o."candidateId" = ${req.user.id} AND (o."candidateReadAt" IS NULL OR m."sentAt" > o."candidateReadAt"))
        OR
        (o."recruiterId" = ${req.user.id} AND (o."recruiterReadAt" IS NULL OR m."sentAt" > o."recruiterReadAt"))
      )`;
  res.json({ unreadNotifications, unreadMessages: rows[0]?.n ?? 0 });
});

// POST /notifications/read { ids?: [] } -- marks those (or all) as read.
notifications.post("/read", async (req, res) => {
  const ids = Array.isArray(req.body?.ids) ? req.body.ids.map((i) => str(i, 100)).filter(Boolean).slice(0, 200) : null;
  const { count } = await prisma.notification.updateMany({
    where: { userId: req.user.id, readAt: null, ...(ids ? { id: { in: ids } } : {}) },
    data: { readAt: new Date() },
  });
  res.json({ updated: count });
});

const templates = express.Router();
templates.use(requireAuth, requireRole("recruiter"));

// GET /templates -> { templates } the recruiter's saved tasks, newest first.
templates.get("/", async (req, res) => {
  const rows = await prisma.taskTemplate.findMany({
    where: { recruiterId: req.user.id },
    orderBy: { createdAt: "desc" },
    take: 50,
  });
  res.json({
    templates: rows.map((t) => ({ id: t.id, title: t.title, description: t.description, link: t.link })),
  });
});

// POST /templates { title, description, link }
templates.post("/", async (req, res) => {
  const title = str(req.body?.title, 200);
  if (!title) return res.status(400).json({ error: "Give the template a title." });
  const row = await prisma.taskTemplate.create({
    data: {
      recruiterId: req.user.id,
      title,
      description: str(req.body?.description, 4000),
      link: str(req.body?.link, 1000),
    },
  });
  res.status(201).json({ id: row.id, title: row.title, description: row.description, link: row.link });
});

// DELETE /templates/:id
templates.delete("/:id", async (req, res) => {
  await prisma.taskTemplate.deleteMany({ where: { id: req.params.id, recruiterId: req.user.id } });
  res.json({ deleted: true });
});

module.exports = { notifications, templates };
