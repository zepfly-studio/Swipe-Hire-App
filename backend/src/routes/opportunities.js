const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
const { buildInterviewIcs } = require("../lib/ics");
const { str, num, date, requireRole } = require("../lib/validate");
const { toOpportunity, toTask, toMessage, OPPORTUNITY_INCLUDE } = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

const STATUSES = [
  "applied",
  "shortlisted",
  "taskAssigned",
  "taskSubmitted",
  "interviewScheduled",
  "offered",
  "rejected",
  "hired",
  "withdrawn",
];

// Set by the task routes (and by the candidate), never picked by hand, so a
// stray status edit can't leave "task assigned" with no task behind it.
const SYSTEM_DRIVEN = ["taskAssigned", "taskSubmitted", "withdrawn"];

// A task can be assigned while the candidate is still being considered.
const CAN_ASSIGN_FROM = ["applied", "shortlisted", "taskAssigned", "taskSubmitted"];

// Nothing more for the candidate to do, or for the recruiter to change.
const FINAL_STATUSES = ["hired", "withdrawn"];

const MAX_OPEN_TASKS = 5;
const CLOUDINARY_FILE = /^https:\/\/res\.cloudinary\.com\//i;

const STATUS_ACTIONS = {
  shortlisted: "shortlisted you",
  interviewScheduled: "scheduled an interview with you",
  offered: "sent you an offer",
  hired: "marked you as hired",
  rejected: "updated your application status",
};

const NOTIFY_TYPE = {
  shortlisted: "shortlisted",
  interviewScheduled: "interviewScheduled",
  offered: "offered",
  hired: "hired",
  rejected: "rejected",
};

// Status-dependent fields are only kept when the status still uses them
// (mirrors Opportunity.copyWithStatus in the app).
function opportunityData(b) {
  const status = STATUSES.includes(b.status) ? b.status : "shortlisted";
  const keepsInterview = status === "interviewScheduled";
  const keepsOffer = status === "offered" || status === "hired";
  const offerSalary = b.offerSalaryLpa == null ? null : num(b.offerSalaryLpa);
  return {
    role: str(b.role, 200),
    status,
    interviewDate: keepsInterview ? date(b.interviewDate) : null,
    interviewMode: keepsInterview ? str(b.interviewMode, 100) : "",
    interviewDetails: keepsInterview ? str(b.interviewDetails, 2000) : "",
    offerSalaryLpa: keepsOffer ? offerSalary : null,
    offerJoiningDate: keepsOffer ? date(b.offerJoiningDate) : null,
    offerNotes: keepsOffer ? str(b.offerNotes, 2000) : "",
  };
}

// "Thu, 16 Oct 2026, 3:00 pm IST" -- the app's users are in India.
function formatWhen(d) {
  if (!d) return "";
  return `${d.toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    weekday: "short",
    day: "numeric",
    month: "short",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })} IST`;
}

function formatDay(d) {
  if (!d) return "";
  return d.toLocaleDateString("en-IN", { timeZone: "Asia/Kolkata", weekday: "short", day: "numeric", month: "short", year: "numeric" });
}

// Writes an automatic line into the opportunity's chat thread so both sides
// have a record of the task / interview details next to the conversation.
function postSystemMessage(tx, { opportunityId, senderId, text, kind }) {
  return tx.message.create({ data: { opportunityId, senderId, text, kind } });
}

// What the entry's status should be once its tasks change: waiting on the
// candidate beats waiting on the recruiter beats "all reviewed".
function statusFromTasks(tasks, fallback) {
  if (tasks.some((t) => t.status === "assigned")) return "taskAssigned";
  if (tasks.some((t) => t.status === "submitted")) return "taskSubmitted";
  return fallback;
}

function interviewMessage(row) {
  const lines = [`Interview scheduled for ${row.role || "your application"}`];
  if (row.interviewDate) lines.push(`When: ${formatWhen(row.interviewDate)}`);
  if (row.interviewMode) lines.push(`Mode: ${row.interviewMode}`);
  if (row.interviewDetails) lines.push(`Details: ${row.interviewDetails}`);
  return lines.join("\n");
}

function companyOf(row) {
  return row.recruiter?.companyProfile?.name || row.recruiter?.company || "A recruiter";
}

// Chat messages from the other side that this user hasn't opened yet, per
// opportunity, in one query.
async function unreadCounts(userId) {
  const rows = await prisma.$queryRaw`
    SELECT m."opportunityId" AS id, COUNT(*)::int AS n
    FROM "messages" m
    JOIN "opportunities" o ON o."id" = m."opportunityId"
    WHERE m."senderId" <> ${userId}
      AND m."kind" = 'text'
      AND (
        (o."candidateId" = ${userId} AND (o."candidateReadAt" IS NULL OR m."sentAt" > o."candidateReadAt"))
        OR
        (o."recruiterId" = ${userId} AND (o."recruiterReadAt" IS NULL OR m."sentAt" > o."recruiterReadAt"))
      )
    GROUP BY m."opportunityId"`;
  return new Map(rows.map((r) => [r.id, r.n]));
}

async function unreadFor(userId, opportunityId) {
  const map = await unreadCounts(userId);
  return map.get(opportunityId) ?? 0;
}

async function notifyCandidateOfStatus(opportunity, previous) {
  const company = companyOf(opportunity);
  const role = opportunity.role || "a role";
  let body;
  let attachments;

  if (opportunity.status === "interviewScheduled") {
    const when = opportunity.interviewDate ? ` on ${formatWhen(opportunity.interviewDate)}` : "";
    const resched = previous && previous.status === "interviewScheduled" ? "rescheduled your interview" : "scheduled an interview with you";
    body = `${company} ${resched} for ${role}${when}.`;
    if (opportunity.interviewDate) {
      const ics = buildInterviewIcs({
        uid: opportunity.id,
        start: opportunity.interviewDate,
        summary: `Interview: ${role} at ${company}`,
        description: [opportunity.interviewMode && `Mode: ${opportunity.interviewMode}`, opportunity.interviewDetails && `Details: ${opportunity.interviewDetails}`]
          .filter(Boolean)
          .join("\n"),
        location: opportunity.interviewDetails || opportunity.interviewMode || "",
        organizer: company,
      });
      attachments = [{ filename: "interview.ics", content: Buffer.from(ics, "utf8") }];
    }
    const lines = [body];
    if (opportunity.interviewMode) lines.push(`Mode: ${opportunity.interviewMode}`);
    if (opportunity.interviewDetails) lines.push(`Details: ${opportunity.interviewDetails}`);
    body = lines.join("\n");
  } else {
    const action = STATUS_ACTIONS[opportunity.status] || "updated your application";
    body = `${company} ${action} for ${role}.`;
  }

  await notify(opportunity.candidateId, {
    title: company,
    body,
    type: NOTIFY_TYPE[opportunity.status] || "status",
    opportunityId: opportunity.id,
    email: {
      subject: `${company}: ${opportunity.status === "interviewScheduled" ? "interview scheduled" : "an update on your application"}`,
      attachments,
    },
  });
}

async function withUnread(userId, rows) {
  const unread = await unreadCounts(userId);
  return rows.map((o) => toOpportunity(o, { unreadCount: unread.get(o.id) ?? 0 }));
}

// GET /opportunities -- mine, newest update first: a candidate's "Hiring
// Activity" or a recruiter's "Pipeline".
router.get("/", async (req, res) => {
  const where = req.user.role === "recruiter" ? { recruiterId: req.user.id } : { candidateId: req.user.id };
  const rows = await prisma.opportunity.findMany({ where, include: OPPORTUNITY_INCLUDE, orderBy: { updatedAt: "desc" } });
  res.json({ opportunities: await withUnread(req.user.id, rows) });
});

// GET /opportunities/with/:candidateId -- the existing entry between this
// recruiter and that candidate, if any (so wishlist -> pipeline doesn't
// create a duplicate of an application that already exists).
router.get("/with/:candidateId", requireRole("recruiter"), async (req, res) => {
  const row = await prisma.opportunity.findFirst({
    where: { recruiterId: req.user.id, candidateId: req.params.candidateId },
    include: OPPORTUNITY_INCLUDE,
    orderBy: { updatedAt: "desc" },
  });
  res.json({ opportunity: row ? toOpportunity(row, { unreadCount: await unreadFor(req.user.id, row.id) }) : null });
});

// POST /opportunities { candidateUid, role, status, interview*, offer* }
router.post("/", requireRole("recruiter"), async (req, res) => {
  const b = req.body || {};
  const candidateId = str(b.candidateUid, 100);
  const candidate = await prisma.user.findFirst({ where: { id: candidateId, role: "candidate" } });
  if (!candidate) return res.status(404).json({ error: "Candidate not found." });

  const data = opportunityData(b);
  if (data.status === "applied" || SYSTEM_DRIVEN.includes(data.status)) data.status = "shortlisted";

  const row = await prisma.$transaction(async (tx) => {
    const created = await tx.opportunity.create({
      data: { candidateId, recruiterId: req.user.id, ...data },
      include: OPPORTUNITY_INCLUDE,
    });
    if (created.status === "interviewScheduled") {
      await postSystemMessage(tx, { opportunityId: created.id, senderId: req.user.id, text: interviewMessage(created), kind: "interview" });
    }
    return created;
  });
  inBackground(notifyCandidateOfStatus(row, null));
  res.status(201).json(toOpportunity(row));
});

async function loadOpportunity(req, res, { include = OPPORTUNITY_INCLUDE } = {}) {
  const row = await prisma.opportunity.findUnique({ where: { id: req.params.id }, include });
  if (!row) {
    res.status(404).json({ error: "Opportunity not found." });
    return null;
  }
  return row;
}

async function ownOpportunity(req, res) {
  const row = await loadOpportunity(req, res);
  if (!row) return null;
  if (row.recruiterId !== req.user.id) {
    res.status(403).json({ error: "Only the recruiter who owns this entry can change it." });
    return null;
  }
  return row;
}

async function partyOpportunity(req, res) {
  const row = await loadOpportunity(req, res);
  if (!row) return null;
  if (row.recruiterId !== req.user.id && row.candidateId !== req.user.id) {
    res.status(403).json({ error: "You are not part of this conversation." });
    return null;
  }
  return row;
}

async function ownAsCandidate(req, res) {
  const row = await loadOpportunity(req, res);
  if (!row) return null;
  if (row.candidateId !== req.user.id) {
    res.status(403).json({ error: "This is not your application." });
    return null;
  }
  return row;
}

// GET /opportunities/:id
router.get("/:id", async (req, res) => {
  const row = await partyOpportunity(req, res);
  if (!row) return;
  res.json(toOpportunity(row, { unreadCount: await unreadFor(req.user.id, row.id) }));
});

// PUT /opportunities/:id -- recruiter edits status / interview / offer.
router.put("/:id", requireRole("recruiter"), async (req, res) => {
  const before = await ownOpportunity(req, res);
  if (!before) return;
  if (before.status === "withdrawn") {
    return res.status(409).json({ error: "The candidate withdrew, so this entry can't be changed." });
  }
  const data = opportunityData(req.body || {});

  if (SYSTEM_DRIVEN.includes(data.status) && data.status !== before.status) {
    return res.status(400).json({ error: "That status is set by the task and application flow, not by hand." });
  }

  const interviewChanged =
    data.status === "interviewScheduled" &&
    (before.status !== "interviewScheduled" ||
      String(before.interviewDate) !== String(data.interviewDate) ||
      before.interviewMode !== data.interviewMode ||
      before.interviewDetails !== data.interviewDetails);

  // A new or moved interview needs a fresh answer from the candidate and
  // fresh reminders; a new offer needs a fresh answer too.
  if (interviewChanged) {
    data.interviewResponse = null;
    data.interviewResponseNote = "";
    data.interviewRespondedAt = null;
    data.interviewRemindersSent = 0;
  }
  if (data.status === "offered" && before.status !== "offered") {
    data.offerResponse = null;
    data.offerRespondedAt = null;
  }

  const row = await prisma.$transaction(async (tx) => {
    const updated = await tx.opportunity.update({ where: { id: before.id }, data, include: OPPORTUNITY_INCLUDE });
    if (interviewChanged) {
      await postSystemMessage(tx, { opportunityId: updated.id, senderId: req.user.id, text: interviewMessage(updated), kind: "interview" });
    }
    return updated;
  });

  if (row.status !== before.status || interviewChanged) inBackground(notifyCandidateOfStatus(row, before));
  res.json(toOpportunity(row));
});

// ---------------------------------------------------- candidate's answers --

// POST /opportunities/:id/withdraw { reason? }
router.post("/:id/withdraw", requireRole("candidate"), async (req, res) => {
  const row = await ownAsCandidate(req, res);
  if (!row) return;
  if (FINAL_STATUSES.includes(row.status)) {
    return res.status(409).json({ error: row.status === "hired" ? "You are already hired for this role." : "You already withdrew." });
  }
  const reason = str(req.body?.reason, 500);

  const updated = await prisma.$transaction(async (tx) => {
    const next = await tx.opportunity.update({
      where: { id: row.id },
      data: { status: "withdrawn" },
      include: OPPORTUNITY_INCLUDE,
    });
    await postSystemMessage(tx, {
      opportunityId: row.id,
      senderId: req.user.id,
      text: reason ? `${req.user.name} withdrew the application.\nReason: ${reason}` : `${req.user.name} withdrew the application.`,
      kind: "application",
    });
    return next;
  });

  await notify(row.recruiterId, {
    title: `${req.user.name} withdrew`,
    body: `${req.user.name} withdrew their application for ${row.role || "the role"}.${reason ? ` Reason: ${reason}` : ""}`,
    type: "withdrawn",
    opportunityId: row.id,
    email: true,
  });
  res.json(toOpportunity(updated));
});

// POST /opportunities/:id/offer-response { decision: "accepted" | "declined" }
router.post("/:id/offer-response", requireRole("candidate"), async (req, res) => {
  const row = await ownAsCandidate(req, res);
  if (!row) return;
  const decision = req.body?.decision;
  if (!["accepted", "declined"].includes(decision)) {
    return res.status(400).json({ error: "decision must be accepted or declined." });
  }
  if (row.status !== "offered") return res.status(409).json({ error: "There is no open offer to answer." });
  if (row.offerResponse) return res.status(409).json({ error: "You already answered this offer." });

  const accepted = decision === "accepted";
  const updated = await prisma.$transaction(async (tx) => {
    const next = await tx.opportunity.update({
      where: { id: row.id },
      data: { offerResponse: decision, offerRespondedAt: new Date(), ...(accepted ? {} : { status: "withdrawn" }) },
      include: OPPORTUNITY_INCLUDE,
    });
    await postSystemMessage(tx, {
      opportunityId: row.id,
      senderId: req.user.id,
      text: accepted ? `${req.user.name} accepted the offer.` : `${req.user.name} declined the offer.`,
      kind: "offer",
    });
    return next;
  });

  await notify(row.recruiterId, {
    title: accepted ? `${req.user.name} accepted your offer` : `${req.user.name} declined your offer`,
    body: accepted
      ? `${req.user.name} accepted the offer for ${row.role || "the role"}. Mark them as hired when you're ready.`
      : `${req.user.name} declined the offer for ${row.role || "the role"}.`,
    type: accepted ? "offer_accepted" : "offer_declined",
    opportunityId: row.id,
    email: true,
  });
  res.json(toOpportunity(updated));
});

// POST /opportunities/:id/interview-response { decision: "confirm" | "reschedule", note }
router.post("/:id/interview-response", requireRole("candidate"), async (req, res) => {
  const row = await ownAsCandidate(req, res);
  if (!row) return;
  const decision = req.body?.decision;
  if (!["confirm", "reschedule"].includes(decision)) {
    return res.status(400).json({ error: "decision must be confirm or reschedule." });
  }
  if (row.status !== "interviewScheduled" || !row.interviewDate) {
    return res.status(409).json({ error: "There is no scheduled interview to answer." });
  }
  const note = str(req.body?.note, 500);
  if (decision === "reschedule" && note.length < 3) {
    return res.status(400).json({ error: "Tell the recruiter which time would suit you." });
  }

  const confirmed = decision === "confirm";
  const updated = await prisma.$transaction(async (tx) => {
    const next = await tx.opportunity.update({
      where: { id: row.id },
      data: {
        interviewResponse: confirmed ? "confirmed" : "reschedule_requested",
        interviewResponseNote: confirmed ? "" : note,
        interviewRespondedAt: new Date(),
      },
      include: OPPORTUNITY_INCLUDE,
    });
    await postSystemMessage(tx, {
      opportunityId: row.id,
      senderId: req.user.id,
      text: confirmed
        ? `${req.user.name} confirmed the interview on ${formatWhen(row.interviewDate)}.`
        : `${req.user.name} asked to reschedule the interview.\nPreferred time: ${note}`,
      kind: "interview",
    });
    return next;
  });

  await notify(row.recruiterId, {
    title: confirmed ? `${req.user.name} confirmed the interview` : `${req.user.name} asked to reschedule`,
    body: confirmed
      ? `${req.user.name} will attend on ${formatWhen(row.interviewDate)}.`
      : `${req.user.name} can't make ${formatWhen(row.interviewDate)}. Preferred time: ${note}`,
    type: confirmed ? "interview_confirmed" : "interview_reschedule",
    opportunityId: row.id,
    email: !confirmed,
  });
  res.json(toOpportunity(updated));
});

// ---------------------------------------------------------------- tasks --

// GET /opportunities/:id/tasks -- every task for this entry, newest first.
router.get("/:id/tasks", async (req, res) => {
  const row = await partyOpportunity(req, res);
  if (!row) return;
  const tasks = await prisma.task.findMany({ where: { opportunityId: row.id }, orderBy: { createdAt: "desc" } });
  res.json({ tasks: tasks.map(toTask) });
});

// POST /opportunities/:id/tasks { title, description, link, dueDate, saveAsTemplate }
// Recruiter assigns a task: the entry moves to "taskAssigned", the candidate
// gets a chat message, a push, an inbox entry and an email.
router.post("/:id/tasks", requireRole("recruiter"), async (req, res) => {
  const row = await ownOpportunity(req, res);
  if (!row) return;

  const title = str(req.body?.title, 200);
  if (!title) return res.status(400).json({ error: "Give the task a title." });
  if (!CAN_ASSIGN_FROM.includes(row.status)) {
    return res.status(409).json({ error: "A task can only be assigned before the interview stage." });
  }
  const open = row.tasks.filter((t) => t.status === "assigned" || t.status === "submitted").length;
  if (open >= MAX_OPEN_TASKS) {
    return res.status(409).json({ error: `A candidate can have at most ${MAX_OPEN_TASKS} open tasks. Review some first.` });
  }

  const dueDate = date(req.body?.dueDate);
  if (req.body?.dueDate && !dueDate) return res.status(400).json({ error: "That due date is not valid." });
  if (dueDate && dueDate.getTime() < Date.now() - 60 * 1000) {
    return res.status(400).json({ error: "The due date has to be in the future." });
  }

  const description = str(req.body?.description, 4000);
  const link = str(req.body?.link, 1000);

  const result = await prisma.$transaction(async (tx) => {
    const task = await tx.task.create({ data: { opportunityId: row.id, title, description, link, dueDate } });
    const updated = await tx.opportunity.update({
      where: { id: row.id },
      data: { status: "taskAssigned" },
      include: OPPORTUNITY_INCLUDE,
    });
    const lines = [`New task: ${title}`];
    if (description) lines.push(description);
    if (link) lines.push(`Reference: ${link}`);
    if (dueDate) lines.push(`Due: ${formatDay(dueDate)}`);
    await postSystemMessage(tx, { opportunityId: row.id, senderId: req.user.id, text: lines.join("\n"), kind: "task" });
    if (req.body?.saveAsTemplate === true) {
      await tx.taskTemplate.create({ data: { recruiterId: req.user.id, title, description, link } });
    }
    return { task, updated };
  });

  const company = companyOf(row);
  await notify(row.candidateId, {
    title: company,
    body: `${company} assigned you a task: ${title}${dueDate ? ` (due ${formatDay(dueDate)})` : ""}.`,
    type: "task",
    opportunityId: row.id,
    email: { subject: `${company} assigned you a task` },
  });

  res.status(201).json({ task: toTask(result.task), opportunity: toOpportunity(result.updated) });
});

async function taskFor(req, res, row) {
  const task = await prisma.task.findFirst({ where: { id: req.params.taskId, opportunityId: row.id } });
  if (!task) {
    res.status(404).json({ error: "Task not found." });
    return null;
  }
  return task;
}

// POST /opportunities/:id/tasks/:taskId/submit { answer, link, fileUrl, fileName }
// Candidate hands the task in (can be re-sent until the recruiter reviews it).
router.post("/:id/tasks/:taskId/submit", requireRole("candidate"), async (req, res) => {
  const row = await partyOpportunity(req, res);
  if (!row) return;
  if (row.candidateId !== req.user.id) return res.status(403).json({ error: "This task is not yours." });
  const task = await taskFor(req, res, row);
  if (!task) return;
  if (task.status !== "assigned" && task.status !== "submitted") {
    return res.status(409).json({ error: "This task has already been reviewed." });
  }

  const answer = str(req.body?.answer, 8000);
  const link = str(req.body?.link, 1000);
  const fileUrl = str(req.body?.fileUrl, 1000);
  const fileName = fileUrl ? str(req.body?.fileName, 200) || "attachment" : "";
  if (!answer && !link && !fileUrl) {
    return res.status(400).json({ error: "Add your answer, a link, or a file." });
  }
  if (link && !/^https?:\/\/\S+$/i.test(link)) {
    return res.status(400).json({ error: "The link must start with http:// or https://" });
  }
  if (fileUrl && !CLOUDINARY_FILE.test(fileUrl)) {
    return res.status(400).json({ error: "That file was not uploaded through the app." });
  }

  const now = new Date();
  const result = await prisma.$transaction(async (tx) => {
    const updatedTask = await tx.task.update({
      where: { id: task.id },
      data: {
        status: "submitted",
        answer,
        submissionLink: link,
        submissionFileUrl: fileUrl,
        submissionFileName: fileName,
        submittedAt: now,
        reviewReminderSentAt: null,
        feedback: task.status === "assigned" ? task.feedback : "",
      },
    });
    const all = await tx.task.findMany({ where: { opportunityId: row.id } });
    const updated = await tx.opportunity.update({
      where: { id: row.id },
      data: { status: statusFromTasks(all, row.status) },
      include: OPPORTUNITY_INCLUDE,
    });
    const late = task.dueDate && now.getTime() > task.dueDate.getTime() ? " (submitted after the due date)" : "";
    const lines = [`Task submitted: ${task.title}${late}`];
    if (answer) lines.push(answer.length > 300 ? `${answer.slice(0, 300)}...` : answer);
    if (link) lines.push(`Link: ${link}`);
    if (fileUrl) lines.push(`File: ${fileName}`);
    await postSystemMessage(tx, { opportunityId: row.id, senderId: req.user.id, text: lines.join("\n"), kind: "task" });
    return { updatedTask, updated };
  });

  await notify(row.recruiterId, {
    title: `${req.user.name} submitted a task`,
    body: `${req.user.name} submitted "${task.title}". Review it to move forward.`,
    type: "task_submitted",
    opportunityId: row.id,
    email: true,
  });

  res.json({ task: toTask(result.updatedTask), opportunity: toOpportunity(result.updated) });
});

// POST /opportunities/:id/tasks/:taskId/review { decision, feedback }
//   decision "approved" -> task approved, recruiter can now schedule the interview
//   decision "changes"  -> task goes back to the candidate with feedback
//   decision "rejected" -> task rejected and the candidate is marked not selected
router.post("/:id/tasks/:taskId/review", requireRole("recruiter"), async (req, res) => {
  const row = await ownOpportunity(req, res);
  if (!row) return;
  const task = await taskFor(req, res, row);
  if (!task) return;
  if (task.status !== "submitted") {
    return res.status(409).json({ error: "There is no submission to review yet." });
  }

  const decision = req.body?.decision;
  if (!["approved", "changes", "rejected"].includes(decision)) {
    return res.status(400).json({ error: "decision must be approved, changes or rejected." });
  }
  const feedback = str(req.body?.feedback, 2000);
  if (decision === "changes" && !feedback) {
    return res.status(400).json({ error: "Tell the candidate what to change." });
  }

  const taskStatus = decision === "approved" ? "approved" : decision === "rejected" ? "rejected" : "assigned";
  const headline =
    decision === "approved"
      ? `Your task "${task.title}" was approved.`
      : decision === "rejected"
        ? `Your task "${task.title}" was reviewed and you were not selected for this role.`
        : `Changes requested on your task "${task.title}".`;

  const result = await prisma.$transaction(async (tx) => {
    const updatedTask = await tx.task.update({
      where: { id: task.id },
      data: { status: taskStatus, feedback, reviewedAt: new Date() },
    });
    const all = await tx.task.findMany({ where: { opportunityId: row.id } });
    const nextStatus = decision === "rejected" ? "rejected" : statusFromTasks(all, "taskSubmitted");
    const updated = await tx.opportunity.update({
      where: { id: row.id },
      data: { status: nextStatus },
      include: OPPORTUNITY_INCLUDE,
    });
    await postSystemMessage(tx, {
      opportunityId: row.id,
      senderId: req.user.id,
      text: feedback ? `${headline}\nFeedback: ${feedback}` : headline,
      kind: "task",
    });
    return { updatedTask, updated };
  });

  const company = companyOf(row);
  await notify(row.candidateId, {
    title: company,
    body: headline,
    type: decision === "rejected" ? "rejected" : "task_review",
    opportunityId: row.id,
    email: { subject: `${company}: update on your task` },
  });

  res.json({ task: toTask(result.updatedTask), opportunity: toOpportunity(result.updated) });
});

// -------------------------------------------------------------- messages --

// GET /opportunities/:id/messages?after=<ISO> -- the chat thread. Reading it
// marks the other side's messages as read for the person asking.
router.get("/:id/messages", async (req, res) => {
  const row = await partyOpportunity(req, res);
  if (!row) return;
  const after = date(req.query.after);
  const messages = await prisma.message.findMany({
    where: { opportunityId: row.id, ...(after ? { sentAt: { gt: after } } : {}) },
    orderBy: { sentAt: "asc" },
    take: 500,
    include: { sender: { select: { name: true } } },
  });

  const isCandidate = row.candidateId === req.user.id;
  const readAt = isCandidate ? row.candidateReadAt : row.recruiterReadAt;
  const hasNew = messages.some((m) => m.senderId !== req.user.id && (!readAt || m.sentAt > readAt));
  if (hasNew) {
    await prisma.opportunity.updateMany({
      where: { id: row.id },
      data: isCandidate ? { candidateReadAt: new Date() } : { recruiterReadAt: new Date() },
    });
  }
  res.json({ messages: messages.map(toMessage) });
});

// POST /opportunities/:id/messages { text }
router.post("/:id/messages", async (req, res) => {
  const row = await partyOpportunity(req, res);
  if (!row) return;
  const text = str(req.body?.text, 4000);
  if (!text) return res.status(400).json({ error: "Message text is required." });

  const message = await prisma.message.create({
    data: { opportunityId: row.id, senderId: req.user.id, text },
    include: { sender: { select: { name: true } } },
  });

  const recipientId = req.user.id === row.candidateId ? row.recruiterId : row.candidateId;
  // Chat only moves the unread badge and the phone's push; it doesn't fill
  // the bell inbox.
  inBackground(
    notify(recipientId, {
      title: req.user.name,
      body: text.slice(0, 120),
      type: "chat_message",
      opportunityId: row.id,
      inbox: false,
    }),
  );

  res.status(201).json(toMessage(message));
});

module.exports = router;
