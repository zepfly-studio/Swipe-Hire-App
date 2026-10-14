// Time-based nudges, run from the API process on a timer:
//
//   task due soon     candidate  once, when an unsubmitted task is due within 24h
//   review waiting    recruiter  once, when a submission has sat unreviewed for 24h
//   interview coming  both       a day before, and again an hour before
//
// Each nudge is claimed with a conditional update (marker IS NULL -> now)
// before it is sent, so a second server instance, or a retry after a crash,
// can never send the same one twice.

const { prisma } = require("../lib/prisma");
const { notify } = require("../lib/notify");

const HOUR = 60 * 60 * 1000;
const INTERVAL_MS = 10 * 60 * 1000;

// A task assigned moments ago with a short deadline doesn't need a reminder
// before the candidate has even seen it.
const MIN_AGE_MINUTES = 30;

function dueText(dueDate, now) {
  const hours = Math.max(1, Math.round((dueDate.getTime() - now.getTime()) / HOUR));
  if (hours <= 1) return "in about an hour";
  if (hours < 24) return `in about ${hours} hours`;
  return "tomorrow";
}

function whenText(date) {
  return `${date.toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })} IST`;
}

// ------------------------------------------------------------ due soon --

// Returns the ids of the tasks it reminded. `now` is injectable so the
// behaviour can be checked without waiting for real time to pass.
async function runTaskReminders(now = new Date()) {
  const soon = new Date(now.getTime() + 24 * HOUR);
  const oldEnough = new Date(now.getTime() - MIN_AGE_MINUTES * 60 * 1000);

  const tasks = await prisma.task.findMany({
    where: {
      status: "assigned",
      reminderSentAt: null,
      dueDate: { gt: now, lte: soon },
      createdAt: { lte: oldEnough },
    },
    include: {
      opportunity: {
        select: { id: true, candidateId: true, recruiter: { select: { company: true, companyProfile: { select: { name: true } } } } },
      },
    },
  });

  const reminded = [];
  for (const task of tasks) {
    const claimed = await prisma.task.updateMany({
      where: { id: task.id, reminderSentAt: null, status: "assigned" },
      data: { reminderSentAt: now },
    });
    if (claimed.count !== 1) continue;

    const company = task.opportunity.recruiter?.companyProfile?.name || task.opportunity.recruiter?.company || "A recruiter";
    await notify(task.opportunity.candidateId, {
      title: "Task due soon",
      body: `"${task.title}" for ${company} is due ${dueText(task.dueDate, now)}. Submit it before the deadline.`,
      type: "task_reminder",
      opportunityId: task.opportunity.id,
    });
    reminded.push(task.id);
  }
  return reminded;
}

// ------------------------------------------------------- review waiting --

async function runReviewReminders(now = new Date()) {
  const cutoff = new Date(now.getTime() - 24 * HOUR);
  const tasks = await prisma.task.findMany({
    where: {
      status: "submitted",
      reviewReminderSentAt: null,
      submittedAt: { lte: cutoff },
      opportunity: { status: { notIn: ["rejected", "withdrawn", "hired"] } },
    },
    include: { opportunity: { select: { id: true, recruiterId: true, candidate: { select: { name: true } } } } },
  });

  const reminded = [];
  for (const task of tasks) {
    const claimed = await prisma.task.updateMany({
      where: { id: task.id, reviewReminderSentAt: null, status: "submitted" },
      data: { reviewReminderSentAt: now },
    });
    if (claimed.count !== 1) continue;

    const name = task.opportunity.candidate?.name || "A candidate";
    await notify(task.opportunity.recruiterId, {
      title: "Submission waiting for review",
      body: `${name} submitted "${task.title}" over a day ago. Review it to keep them moving.`,
      type: "review_reminder",
      opportunityId: task.opportunity.id,
    });
    reminded.push(task.id);
  }
  return reminded;
}

// ------------------------------------------------------ interview soon --

// Stage 1 goes out between 24h and 1h before; stage 2 within the last hour.
// An interview booked less than an hour out skips straight to stage 2.
async function runInterviewReminders(now = new Date()) {
  const horizon = new Date(now.getTime() + 24 * HOUR);
  const rows = await prisma.opportunity.findMany({
    where: {
      status: "interviewScheduled",
      interviewDate: { gt: now, lte: horizon },
      interviewRemindersSent: { lt: 2 },
    },
    include: { candidate: { select: { name: true } } },
  });

  const reminded = [];
  for (const o of rows) {
    const msUntil = o.interviewDate.getTime() - now.getTime();
    const stage = msUntil <= HOUR ? 2 : 1;
    if (stage <= o.interviewRemindersSent) continue;

    const claimed = await prisma.opportunity.updateMany({
      where: { id: o.id, interviewRemindersSent: { lt: stage }, status: "interviewScheduled" },
      data: { interviewRemindersSent: stage },
    });
    if (claimed.count !== 1) continue;

    const when = whenText(o.interviewDate);
    const lead = stage === 2 ? "starts within the hour" : "is tomorrow";
    const role = o.role || "the role";
    await notify(o.candidateId, {
      title: "Interview reminder",
      body: `Your interview for ${role} ${lead}: ${when}.`,
      type: "interview_reminder",
      opportunityId: o.id,
    });
    await notify(o.recruiterId, {
      title: "Interview reminder",
      body: `Your interview with ${o.candidate?.name || "the candidate"} for ${role} ${lead}: ${when}.`,
      type: "interview_reminder",
      opportunityId: o.id,
    });
    reminded.push(o.id);
  }
  return reminded;
}

function startTaskReminders() {
  if (process.env.DISABLE_TASK_REMINDERS === "true") {
    console.log("[reminders] disabled by DISABLE_TASK_REMINDERS");
    return;
  }
  const tick = async () => {
    for (const [name, run] of [
      ["task", runTaskReminders],
      ["review", runReviewReminders],
      ["interview", runInterviewReminders],
    ]) {
      try {
        const ids = await run();
        if (ids.length) console.log(`[reminders] sent ${ids.length} ${name} reminder(s)`);
      } catch (err) {
        console.error(`[reminders] ${name} run failed:`, err.message);
      }
    }
  };

  setTimeout(tick, 20 * 1000).unref();
  setInterval(tick, INTERVAL_MS).unref();
}

module.exports = { runTaskReminders, runReviewReminders, runInterviewReminders, startTaskReminders };
