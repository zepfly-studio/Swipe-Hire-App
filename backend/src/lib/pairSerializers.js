// Shared pieces for the company <-> candidate "pair" features: chat,
// interviews and tasks. Contains
//   * who-may-talk-to-whom lookups (read-only against CandidateSwipe),
//   * the `with` block every payload carries (name / subtitle / badge / avatar),
//   * JSON shapes pinned in docs/PHASE23_CONTRACT.md section B.
//
// "Company" is the recruiter user id; a company's display name comes from
// the Company row, then User.company, then the user's own name.

const { prisma } = require("./prisma");

function iso(date) {
  return date ? date.toISOString() : null;
}

// "Thu, 16 Oct, 3:00 pm IST" -- the app's users are in India.
function formatWhen(date, { withYear = false } = {}) {
  return `${date.toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    weekday: "short",
    day: "numeric",
    month: "short",
    ...(withYear ? { year: "numeric" } : {}),
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  })} IST`;
}

function firstName(name) {
  return String(name || "").trim().split(/\s+/)[0] || "";
}

// ------------------------------------------------------------ people --

const PARTY_SELECT = {
  id: true,
  name: true,
  role: true,
  company: true,
  candidateProfile: { select: { desiredRole: true, photoUrl: true } },
  companyProfile: { select: { name: true, industry: true, logoUrl: true, verificationStatus: true } },
};

/** Map of userId -> user (with the profile bits the `with` block needs). */
async function loadParties(ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  if (!unique.length) return new Map();
  const users = await prisma.user.findMany({ where: { id: { in: unique } }, select: PARTY_SELECT });
  return new Map(users.map((u) => [u.id, u]));
}

function companyName(user) {
  return user?.companyProfile?.name || user?.company || user?.name || "A company";
}

/**
 * Right swipes between this viewer and each of `otherIds`, folded into
 * Map(otherId -> { stage, jobTitle, swipedAt }):
 *   stage    the stage of the most recently updated right swipe,
 *   jobTitle the job of the most recent right swipe.
 * `viewerIsCompany` says which side of CandidateSwipe the viewer is.
 */
async function swipeInfo(viewerId, viewerIsCompany, otherIds) {
  const ids = [...new Set(otherIds.filter(Boolean))];
  const result = new Map();
  if (!ids.length) return result;
  const rows = await prisma.candidateSwipe.findMany({
    where: viewerIsCompany
      ? { recruiterId: viewerId, candidateId: { in: ids }, action: "right" }
      : { candidateId: viewerId, recruiterId: { in: ids }, action: "right" },
    orderBy: { createdAt: "desc" },
    select: {
      recruiterId: true,
      candidateId: true,
      stage: true,
      createdAt: true,
      updatedAt: true,
      jobPosting: { select: { title: true } },
    },
  });
  for (const row of rows) {
    const key = viewerIsCompany ? row.candidateId : row.recruiterId;
    const info = result.get(key);
    if (!info) {
      result.set(key, { stage: row.stage, stageAt: row.updatedAt, jobTitle: row.jobPosting?.title || "", swipedAt: row.createdAt, updatedAt: row.updatedAt });
    } else if (row.updatedAt > info.stageAt) {
      info.stage = row.stage;
      info.stageAt = row.updatedAt;
      info.updatedAt = row.updatedAt;
    }
  }
  return result;
}

/**
 * The `with` block describing `other` to a viewer.
 * @param viewerIsCompany  true when the viewer is the company (so `other` is a candidate)
 * @param jobTitle         job the pair is about (right swipe / interview / task), if known
 */
function toWith(other, viewerIsCompany, { jobTitle = "" } = {}) {
  if (!other) return { id: "", name: "Unknown", subtitle: "", avatarUrl: "" };
  if (viewerIsCompany) {
    const p = other.candidateProfile;
    return { id: other.id, name: other.name, subtitle: p?.desiredRole || "", avatarUrl: p?.photoUrl || "" };
  }
  const c = other.companyProfile;
  return {
    id: other.id,
    name: companyName(other),
    subtitle: jobTitle || c?.industry || "",
    verified: c?.verificationStatus === "verified",
    avatarUrl: c?.logoUrl || "",
  };
}

// --------------------------------------------------- pair relationship --

/** True when the company has right-swiped the candidate (any job, or `jobId`). */
async function hasRightSwipe(companyId, candidateId, jobId) {
  const row = await prisma.candidateSwipe.findFirst({
    where: { recruiterId: companyId, candidateId, action: "right", ...(jobId ? { jobPostingId: jobId } : {}) },
    select: { id: true },
  });
  return Boolean(row);
}

/**
 * True once the company has reached out to the candidate: a chat message
 * from the company, an interview invite or a task. That is what unlocks the
 * candidate's side of the conversation.
 */
async function companyContacted(companyId, candidateId) {
  const [message, interview, task] = await Promise.all([
    prisma.chatMessage.findFirst({ where: { companyId, candidateId, senderId: companyId }, select: { id: true } }),
    prisma.interview.findFirst({ where: { companyId, candidateId }, select: { id: true } }),
    prisma.hiringTask.findFirst({ where: { companyId, candidateId }, select: { id: true } }),
  ]);
  return Boolean(message || interview || task);
}

/**
 * A pair does something (interview / task) that moves the pipeline:
 * sets `stage` on the pair's right swipes (for `jobId` when given) whose
 * stage is in `from`. `from: null` means "any stage except hired/rejected".
 */
async function moveStage({ companyId, candidateId, jobId, to, from }) {
  const stageFilter = from ? { in: from } : { notIn: ["hired", "rejected"] };
  await prisma.candidateSwipe.updateMany({
    where: {
      recruiterId: companyId,
      candidateId,
      action: "right",
      stage: stageFilter,
      ...(jobId ? { jobPostingId: jobId } : {}),
    },
    data: { stage: to },
  });
}

/** The job of this company's most recent right swipe on the candidate. */
async function latestSwipedJob(companyId, candidateId) {
  const row = await prisma.candidateSwipe.findFirst({
    where: { recruiterId: companyId, candidateId, action: "right" },
    orderBy: { createdAt: "desc" },
    select: { jobPostingId: true, jobPosting: { select: { title: true } } },
  });
  return row ? { id: row.jobPostingId, title: row.jobPosting?.title || "" } : null;
}

// ------------------------------------------------------------ shapes --

function toChatMessage(row, viewerId) {
  return {
    id: row.id,
    text: row.text,
    mine: row.senderId === viewerId,
    at: iso(row.createdAt),
    read: row.readAt != null,
  };
}

/**
 * @param row     Interview with `jobPosting: { title }` included
 * @param other   the other side's user (see PARTY_SELECT)
 */
function toInterview(row, other, viewerIsCompany) {
  const confirmed = row.status === "confirmed";
  return {
    id: row.id,
    with: toWith(other, viewerIsCompany, { jobTitle: row.jobPosting?.title || "" }),
    jobTitle: row.jobPosting?.title || "",
    slots: row.slots.map(iso),
    chosenSlot: iso(row.chosenSlot),
    durationMins: row.durationMins,
    mode: row.mode,
    meetingLink: confirmed ? row.meetingLink : "",
    location: row.location,
    note: row.note,
    status: row.status,
    createdAt: iso(row.createdAt),
  };
}

/** "overdue" is not stored: an assigned task whose deadline has passed. */
function taskStatus(row, now = new Date()) {
  if (row.status === "cancelled") return "cancelled";
  if (row.status === "submitted") return "submitted";
  return row.dueAt.getTime() < now.getTime() ? "overdue" : "assigned";
}

function toTask(row, other, viewerIsCompany, now = new Date()) {
  const item = {
    id: row.id,
    with: toWith(other, viewerIsCompany, { jobTitle: row.jobPosting?.title || "" }),
    jobTitle: row.jobPosting?.title || "",
    title: row.title,
    description: row.description,
    briefUrl: row.briefUrl,
    dueAt: iso(row.dueAt),
    status: taskStatus(row, now),
    createdAt: iso(row.createdAt),
  };
  if (row.submittedAt) {
    item.submission = { liveUrl: row.liveUrl, repoUrl: row.repoUrl, note: row.submissionNote, at: iso(row.submittedAt) };
  }
  return item;
}

module.exports = {
  iso,
  formatWhen,
  firstName,
  PARTY_SELECT,
  loadParties,
  companyName,
  swipeInfo,
  toWith,
  hasRightSwipe,
  companyContacted,
  moveStage,
  latestSwipedJob,
  toChatMessage,
  toInterview,
  taskStatus,
  toTask,
};
