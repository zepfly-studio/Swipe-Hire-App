const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
const { notifyCompany } = require("../lib/teamNotify");
const {
  loadParties,
  companyName,
  hasRightSwipe,
  moveStage,
  latestSwipedJob,
  toTask,
  formatWhen,
} = require("../lib/pairSerializers");

// Take-home tasks a company sends to a shortlisted candidate: a brief, a
// deadline, and a live link and/or GitHub repo back from the candidate.

const router = express.Router();
router.use(requireAuth);

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const INCLUDE = { jobPosting: { select: { title: true } } };

const isCompany = (user) => user.role === "recruiter";

function onlyCompany(req, res, next) {
  if (!isCompany(req.user)) return res.status(403).json({ error: "Only companies can do this" });
  next();
}
function onlyCandidate(req, res, next) {
  if (isCompany(req.user)) return res.status(403).json({ error: "Only candidates can do this" });
  next();
}

function fail(res, status, error, field) {
  return res.status(status).json(field ? { error, field } : { error });
}

// A web link as people type it: "my-app.vercel.app" gets https://, only
// http/https survive, max 300 characters. Returns "" when it isn't a link.
function normalizeUrl(raw) {
  const s = typeof raw === "string" ? raw.trim() : "";
  if (!s) return "";
  const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(s) ? s : `https://${s}`;
  let url;
  try {
    url = new URL(withScheme);
  } catch {
    return "";
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return "";
  if (!url.hostname.includes(".") && url.hostname !== "localhost") return "";
  return withScheme;
}

// The 1 hour .. 30 days deadline window. Returns { dueAt } or { error }.
function parseDeadline(raw, now = Date.now()) {
  const d = typeof raw === "string" || typeof raw === "number" ? new Date(raw) : null;
  if (!raw || !d || Number.isNaN(d.getTime())) return { error: "Please choose a deadline" };
  if (d.getTime() < now + HOUR) return { error: "The deadline must be at least 1 hour from now" };
  if (d.getTime() > now + 30 * DAY) return { error: "The deadline can be at most 30 days away" };
  return { dueAt: d };
}

async function companyDisplayName(user) {
  const profile = await prisma.company.findUnique({ where: { ownerId: user.companyId || user.id }, select: { name: true } });
  return companyName({ ...user, companyProfile: profile });
}

// GET /tasks[?candidateId=] -> { tasks }  max 200, newest first
router.get("/", async (req, res) => {
  const viewerIsCompany = isCompany(req.user);
  const candidateFilter =
    viewerIsCompany && typeof req.query.candidateId === "string" && req.query.candidateId ? { candidateId: req.query.candidateId } : {};
  const rows = await prisma.hiringTask.findMany({
    where: viewerIsCompany
      ? { companyId: req.user.companyId, ...candidateFilter }
      : { candidateId: req.user.id, status: { not: "cancelled" } },
    include: INCLUDE,
    orderBy: { createdAt: "desc" },
    take: 200,
  });
  const parties = await loadParties(rows.map((r) => (viewerIsCompany ? r.candidateId : r.companyId)));
  const now = new Date();
  res.json({
    tasks: rows.map((r) => toTask(r, parties.get(viewerIsCompany ? r.candidateId : r.companyId), viewerIsCompany, now)),
  });
});

// POST /tasks -> 201 { id }
router.post("/", onlyCompany, async (req, res) => {
  const body = req.body || {};

  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (!title) return fail(res, 400, "Please give the task a title", "title");
  if (title.length > 120) return fail(res, 400, "Title is too long (max 120 characters)", "title");

  const description = typeof body.description === "string" ? body.description.trim() : "";
  if (!description) return fail(res, 400, "Please describe what the candidate should build", "description");
  if (description.length > 5000) return fail(res, 400, "Description is too long (max 5000 characters)", "description");

  let briefUrl = "";
  if (typeof body.briefUrl === "string" && body.briefUrl.trim()) {
    briefUrl = normalizeUrl(body.briefUrl);
    if (!briefUrl) return fail(res, 400, "Please enter a valid reference link", "briefUrl");
    if (briefUrl.length > 300) return fail(res, 400, "Reference link is too long (max 300 characters)", "briefUrl");
  }

  const deadline = parseDeadline(body.dueAt);
  if (deadline.error) return fail(res, 400, deadline.error, "dueAt");

  const candidateId = typeof body.candidateId === "string" ? body.candidateId.trim() : "";
  if (!candidateId) return fail(res, 400, "Choose a candidate", "candidateId");
  const candidate = await prisma.user.findUnique({ where: { id: candidateId }, select: { id: true, role: true } });
  if (!candidate || candidate.role !== "candidate") return fail(res, 404, "Candidate not found");

  const jobId = typeof body.jobId === "string" && body.jobId.trim() ? body.jobId.trim() : "";
  if (jobId) {
    if (!(await hasRightSwipe(req.user.companyId, candidateId, jobId))) {
      return fail(res, 403, "This candidate is not shortlisted for that job");
    }
  } else if (!(await hasRightSwipe(req.user.companyId, candidateId))) {
    return fail(res, 403, "Shortlist this candidate before sending a task");
  }

  const job = jobId ? { id: jobId } : await latestSwipedJob(req.user.companyId, candidateId);
  const task = await prisma.hiringTask.create({
    data: {
      companyId: req.user.companyId,
      candidateId,
      jobPostingId: job?.id || null,
      createdById: req.user.id,
      title,
      description,
      briefUrl,
      dueAt: deadline.dueAt,
    },
  });

  await moveStage({ companyId: req.user.companyId, candidateId, jobId: jobId || null, to: "task", from: ["shortlisted", "contacted"] });

  const company = await companyDisplayName(req.user);
  inBackground(
    notify(candidateId, {
      title: `${company} sent you a task`,
      body: `"${title}" is due ${formatWhen(task.dueAt, { withYear: true })}. Open SwipeHire to see the details and submit your work.`,
      type: "task",
      link: "/tasks",
      email: { subject: `New task from ${company}` },
    }),
  );

  res.status(201).json({ id: task.id });
});

// POST /tasks/:id/submit { liveUrl?, repoUrl?, note? } -> { ok }
router.post("/:id/submit", onlyCandidate, async (req, res) => {
  const task = await prisma.hiringTask.findFirst({ where: { id: req.params.id, candidateId: req.user.id } });
  if (!task) return fail(res, 404, "Task not found");
  if (task.status === "cancelled") return fail(res, 409, "This task was cancelled");
  if (task.dueAt.getTime() <= Date.now()) return fail(res, 409, "The deadline for this task has passed");

  const body = req.body || {};
  const rawLive = typeof body.liveUrl === "string" ? body.liveUrl.trim() : "";
  const rawRepo = typeof body.repoUrl === "string" ? body.repoUrl.trim() : "";
  if (!rawLive && !rawRepo) return fail(res, 400, "Add your live link or GitHub repo link");

  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (note.length > 1000) return fail(res, 400, "Note is too long (max 1000 characters)", "note");

  let liveUrl = "";
  if (rawLive) {
    liveUrl = normalizeUrl(rawLive);
    if (!liveUrl) return fail(res, 400, "Please enter a valid live link", "liveUrl");
    if (liveUrl.length > 300) return fail(res, 400, "The live link is too long (max 300 characters)", "liveUrl");
  }
  let repoUrl = "";
  if (rawRepo) {
    repoUrl = normalizeUrl(rawRepo);
    if (!repoUrl) return fail(res, 400, "Please enter a valid GitHub repo link", "repoUrl");
    if (repoUrl.length > 300) return fail(res, 400, "The repo link is too long (max 300 characters)", "repoUrl");
    const host = new URL(repoUrl).hostname.toLowerCase();
    if (host !== "github.com" && !host.endsWith(".github.com")) {
      return fail(res, 400, "The repo link must be a github.com link", "repoUrl");
    }
  }

  const now = new Date();
  const claimed = await prisma.hiringTask.updateMany({
    where: { id: task.id, status: { in: ["assigned", "submitted"] }, dueAt: { gt: now } },
    data: { status: "submitted", liveUrl, repoUrl, submissionNote: note, submittedAt: now },
  });
  if (claimed.count !== 1) return fail(res, 409, "The deadline for this task has passed");

  const updated = task.submittedAt != null;
  inBackground(
    notifyCompany(task.companyId, {
      title: `${req.user.name} ${updated ? "updated their submission" : "submitted a task"}`,
      body: `"${task.title}" was ${updated ? "updated" : "submitted"}.${liveUrl ? `\nLive: ${liveUrl}` : ""}${repoUrl ? `\nRepo: ${repoUrl}` : ""}`,
      type: "task",
      link: "/tasks",
      email: { subject: `${req.user.name} ${updated ? "updated" : "submitted"} "${task.title}"` },
    }),
  );

  res.json({ ok: true });
});

// PATCH /tasks/:id { dueAt } -> { ok }
router.patch("/:id", onlyCompany, async (req, res) => {
  const task = await prisma.hiringTask.findFirst({ where: { id: req.params.id, companyId: req.user.companyId } });
  if (!task) return fail(res, 404, "Task not found");
  if (task.status === "cancelled") return fail(res, 409, "This task was cancelled");

  const deadline = parseDeadline(req.body?.dueAt);
  if (deadline.error) return fail(res, 400, deadline.error, "dueAt");

  // A new deadline earns a fresh "due soon" reminder.
  const claimed = await prisma.hiringTask.updateMany({
    where: { id: task.id, status: { not: "cancelled" } },
    data: { dueAt: deadline.dueAt, reminderSentAt: null },
  });
  if (claimed.count !== 1) return fail(res, 409, "This task was cancelled");

  const company = await companyDisplayName(req.user);
  inBackground(
    notify(task.candidateId, {
      title: `${company} changed a task deadline`,
      body: `"${task.title}" is now due ${formatWhen(deadline.dueAt, { withYear: true })}.`,
      type: "task",
      link: "/tasks",
      email: { subject: `Deadline changed: ${task.title}` },
    }),
  );

  res.json({ ok: true });
});

// POST /tasks/:id/cancel -> { ok }   (idempotent; the candidate is told without an email)
router.post("/:id/cancel", onlyCompany, async (req, res) => {
  const task = await prisma.hiringTask.findFirst({ where: { id: req.params.id, companyId: req.user.companyId } });
  if (!task) return fail(res, 404, "Task not found");
  if (task.status === "cancelled") return res.json({ ok: true });

  const claimed = await prisma.hiringTask.updateMany({
    where: { id: task.id, status: { not: "cancelled" } },
    data: { status: "cancelled" },
  });
  if (claimed.count === 1) {
    const company = await companyDisplayName(req.user);
    inBackground(
      notify(task.candidateId, {
        title: `${company} cancelled a task`,
        body: `You don't need to submit "${task.title}" any more.`,
        type: "task",
        link: "/tasks",
        email: false,
      }),
    );
  }
  res.json({ ok: true });
});

module.exports = router;
