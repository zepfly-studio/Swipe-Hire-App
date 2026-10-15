const crypto = require("crypto");
const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
const { notifyCompany } = require("../lib/teamNotify");
const { buildInterviewIcs } = require("../lib/ics");
const {
  loadParties,
  companyName,
  hasRightSwipe,
  moveStage,
  latestSwipedJob,
  toInterview,
  formatWhen,
} = require("../lib/pairSerializers");

// Slot-based interviews: the company proposes 1-3 times, the candidate picks
// one (which confirms it). There is no reschedule: cancel and invite again.

const router = express.Router();
router.use(requireAuth);

const MIN_LEAD_MS = 15 * 60 * 1000;
const DURATIONS = [15, 30, 45, 60];
const MODES = ["video", "phone", "in-person"];
const MODE_LABEL = { video: "video", phone: "phone", "in-person": "in-person" };

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

async function companyDisplayName(user) {
  const profile = await prisma.company.findUnique({ where: { ownerId: user.companyId || user.id }, select: { name: true } });
  return companyName({ ...user, companyProfile: profile });
}

// GET /interviews -> { interviews }  latest 100
router.get("/", async (req, res) => {
  const viewerIsCompany = isCompany(req.user);
  const rows = await prisma.interview.findMany({
    where: viewerIsCompany ? { companyId: req.user.companyId } : { candidateId: req.user.id },
    include: INCLUDE,
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  const parties = await loadParties(rows.map((r) => (viewerIsCompany ? r.candidateId : r.companyId)));
  res.json({
    interviews: rows.map((r) => toInterview(r, parties.get(viewerIsCompany ? r.candidateId : r.companyId), viewerIsCompany)),
  });
});

// POST /interviews -> 201 { id }
router.post("/", onlyCompany, async (req, res) => {
  const body = req.body || {};
  const now = Date.now();

  const candidateId = typeof body.candidateId === "string" ? body.candidateId.trim() : "";
  if (!candidateId) return fail(res, 400, "Choose a candidate", "candidateId");

  const rawSlots = Array.isArray(body.slots) ? body.slots : [];
  const times = [];
  for (const raw of rawSlots) {
    const d = typeof raw === "string" || typeof raw === "number" ? new Date(raw) : null;
    if (!d || Number.isNaN(d.getTime())) return fail(res, 400, "One of the proposed times is not a valid date", "slots");
    times.push(d.getTime());
  }
  const unique = [...new Set(times)].sort((a, b) => a - b);
  if (unique.length < 1 || unique.length > 3) return fail(res, 400, "Please offer between 1 and 3 times", "slots");
  if (unique.some((t) => t < now + MIN_LEAD_MS)) {
    return fail(res, 400, "Every proposed time must be at least 15 minutes from now", "slots");
  }

  let durationMins = 30;
  if (body.durationMins !== undefined && body.durationMins !== null && body.durationMins !== "") {
    durationMins = Number(body.durationMins);
    if (!DURATIONS.includes(durationMins)) {
      return fail(res, 400, "Duration must be 15, 30, 45 or 60 minutes", "durationMins");
    }
  }

  const mode = body.mode === undefined || body.mode === null || body.mode === "" ? "video" : body.mode;
  if (!MODES.includes(mode)) return fail(res, 400, "Choose video, phone or in-person", "mode");

  const location = typeof body.location === "string" ? body.location.trim() : "";
  if (location.length > 200) return fail(res, 400, "Location is too long (max 200 characters)", "location");
  if (mode === "in-person" && !location) return fail(res, 400, "Please add the location for an in-person interview", "location");

  let meetingLink = typeof body.meetingLink === "string" ? body.meetingLink.trim() : "";
  if (meetingLink) {
    if (meetingLink.length > 300) return fail(res, 400, "Meeting link is too long (max 300 characters)", "meetingLink");
    if (!/^https:\/\/\S+$/i.test(meetingLink)) return fail(res, 400, "Meeting link must start with https://", "meetingLink");
  } else if (mode === "video") {
    meetingLink = `https://meet.jit.si/GlideRecruit-${crypto.randomBytes(6).toString("hex")}`;
  }

  const note = typeof body.note === "string" ? body.note.trim() : "";
  if (note.length > 500) return fail(res, 400, "Note is too long (max 500 characters)", "note");

  const candidate = await prisma.user.findUnique({ where: { id: candidateId }, select: { id: true, role: true } });
  if (!candidate || candidate.role !== "candidate") return fail(res, 404, "Candidate not found");

  const jobId = typeof body.jobId === "string" && body.jobId.trim() ? body.jobId.trim() : "";
  if (jobId) {
    if (!(await hasRightSwipe(req.user.companyId, candidateId, jobId))) {
      return fail(res, 403, "This candidate is not shortlisted for that job");
    }
  } else if (!(await hasRightSwipe(req.user.companyId, candidateId))) {
    return fail(res, 403, "Shortlist this candidate before scheduling an interview");
  }

  // A proposed interview, or a confirmed one that has not happened yet,
  // already covers this pair.
  const existing = await prisma.interview.findFirst({
    where: {
      companyId: req.user.companyId,
      candidateId,
      OR: [{ status: "proposed" }, { status: "confirmed", chosenSlot: { gt: new Date() } }],
    },
    select: { id: true },
  });
  if (existing) return fail(res, 409, "An interview with this candidate is already scheduled");

  const job = jobId ? { id: jobId, title: "" } : await latestSwipedJob(req.user.companyId, candidateId);
  const created = await prisma.interview.create({
    data: {
      companyId: req.user.companyId,
      candidateId,
      jobPostingId: job?.id || null,
      slots: unique.map((t) => new Date(t)),
      durationMins,
      mode,
      meetingLink,
      location: mode === "in-person" || location ? location : "",
      note,
    },
    include: INCLUDE,
  });

  await moveStage({ companyId: req.user.companyId, candidateId, jobId: jobId || null, to: "interview", from: null });

  const company = await companyDisplayName(req.user);
  const jobTitle = created.jobPosting?.title || "";
  const lines = [
    `${company} invited you to a ${durationMins}-minute ${MODE_LABEL[mode]} interview${jobTitle ? ` for ${jobTitle}` : ""}.`,
    "Pick a time that suits you:",
    ...created.slots.map((s) => `- ${formatWhen(s, { withYear: true })}`),
  ];
  if (mode === "in-person" && location) lines.push(`Location: ${location}`);
  if (note) lines.push(`Note: ${note}`);
  lines.push("Open GlideRecruit to choose a time.");
  inBackground(
    notify(candidateId, {
      title: `${company} invited you to an interview`,
      body: lines.join("\n"),
      type: "interview",
      link: "/interviews",
      email: { subject: `Interview invitation from ${company}` },
    }),
  );

  res.status(201).json({ id: created.id });
});

// POST /interviews/:id/accept { slot } -> { ok }
router.post("/:id/accept", onlyCandidate, async (req, res) => {
  const interview = await prisma.interview.findFirst({
    where: { id: req.params.id, candidateId: req.user.id },
    include: INCLUDE,
  });
  if (!interview) return fail(res, 404, "Interview not found");
  if (interview.status !== "proposed") return fail(res, 409, "This interview is no longer open");

  const raw = req.body?.slot;
  const chosen = typeof raw === "string" || typeof raw === "number" ? new Date(raw) : null;
  const chosenMs = chosen && !Number.isNaN(chosen.getTime()) ? chosen.getTime() : NaN;
  const slot = interview.slots.find((s) => s.getTime() === chosenMs);
  if (!slot) return fail(res, 400, "Please choose one of the offered times", "slot");
  if (slot.getTime() <= Date.now()) {
    return fail(res, 400, "That time has already passed, please ask for a new time in chat", "slot");
  }

  const claimed = await prisma.interview.updateMany({
    where: { id: interview.id, status: "proposed" },
    data: { status: "confirmed", chosenSlot: slot },
  });
  if (claimed.count !== 1) return fail(res, 409, "This interview is no longer open");

  const [company, candidate] = await Promise.all([
    prisma.user.findUnique({ where: { id: interview.companyId }, select: { id: true, name: true, company: true } }),
    prisma.user.findUnique({ where: { id: interview.candidateId }, select: { name: true } }),
  ]);
  const companyLabel = company ? await companyDisplayName(company) : "your company";
  const candidateName = candidate?.name || "The candidate";
  const jobTitle = interview.jobPosting?.title || "";
  const when = formatWhen(slot, { withYear: true });

  const ics = buildInterviewIcs({
    uid: interview.id,
    start: slot,
    durationMinutes: interview.durationMins,
    summary: `Interview: ${candidateName}${jobTitle ? ` for ${jobTitle}` : ""}`,
    description: [interview.note && `Note: ${interview.note}`, interview.meetingLink && `Join: ${interview.meetingLink}`]
      .filter(Boolean)
      .join("\n"),
    location: interview.meetingLink || interview.location || "",
    organizer: companyLabel,
    url: interview.meetingLink || "",
  });

  const lines = [`${candidateName} confirmed the interview${jobTitle ? ` for ${jobTitle}` : ""}.`, `When: ${when}`];
  if (interview.meetingLink) lines.push(`Join: ${interview.meetingLink}`);
  else if (interview.location) lines.push(`Location: ${interview.location}`);
  inBackground(
    notifyCompany(interview.companyId, {
      title: `${candidateName} confirmed the interview`,
      body: lines.join("\n"),
      type: "interview",
      link: "/interviews",
      email: {
        subject: `Interview confirmed with ${candidateName}`,
        attachments: [{ filename: "interview.ics", content: Buffer.from(ics, "utf8") }],
      },
    }),
  );

  res.json({ ok: true });
});

// POST /interviews/:id/cancel { reason? } -> { ok }   (either side, idempotent)
router.post("/:id/cancel", async (req, res) => {
  const viewerIsCompany = isCompany(req.user);
  const interview = await prisma.interview.findFirst({
    where: { id: req.params.id, ...(viewerIsCompany ? { companyId: req.user.companyId } : { candidateId: req.user.id }) },
    include: INCLUDE,
  });
  if (!interview) return fail(res, 404, "Interview not found");
  if (interview.status === "cancelled") return res.json({ ok: true });

  const reason = typeof req.body?.reason === "string" ? req.body.reason.trim() : "";
  if (reason.length > 300) return fail(res, 400, "Reason is too long (max 300 characters)", "reason");

  const claimed = await prisma.interview.updateMany({
    where: { id: interview.id, status: { not: "cancelled" } },
    data: { status: "cancelled", cancelledById: req.user.id, cancelReason: reason },
  });
  if (claimed.count !== 1) return res.json({ ok: true });

  const otherId = viewerIsCompany ? interview.candidateId : interview.companyId;
  const actor = viewerIsCompany ? await companyDisplayName(req.user) : req.user.name;
  const cancelEvent = {
    title: `${actor} cancelled the interview`,
    body: reason || "You can agree on a new time in chat.",
    type: "interview",
    link: "/interviews",
    email: { subject: `Interview cancelled by ${actor}` },
  };
  // A candidate cancelling tells the whole company team.
  inBackground(viewerIsCompany ? notify(otherId, cancelEvent) : notifyCompany(otherId, cancelEvent));

  res.json({ ok: true });
});

module.exports = router;
