const express = require("express");
const multer = require("multer");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { inBackground } = require("../lib/notify");
const { str, int, requireRole } = require("../lib/validate");
const { toCandidateProfile, toJobPosting } = require("../lib/serializers");
const { FieldError, parseProfileBody, parsePreferencesBody } = require("../lib/candidateProfile");
const { parseResumePdf } = require("../lib/resumeParser");
const { ensureCompany } = require("../lib/credits");
const { companyOwner } = require("../lib/teamNotify");
const { evaluateAlertsForCandidate } = require("../lib/savedSearches");
const deckLib = require("../lib/deck");

const router = express.Router();
router.use(requireAuth);

const MAX_PAGE = 30;
const DEFAULT_PAGE = 10;
// How many candidates are scored and ranked per request. Fetched most
// recently active first, so stale profiles only appear once the fresh ones
// are used up.
const MATCH_WINDOW = 500;
const DAY_MS = 24 * 60 * 60 * 1000;
// A profile whose "I'm still looking" ring ran out (15 days) goes last.
const ACTIVE_DAYS = 15;
// Profiles younger than this get a boost so a new candidate is seen at all.
const NEW_PROFILE_DAYS = 7;
const NEW_PROFILE_BONUS = 10;

const RESUME_MAX_BYTES = 5 * 1024 * 1024;

const PAUSED_MESSAGE = "This job is paused or closed. Reopen it to see candidates.";

// Evaluates saved-search alerts for a candidate whose profile, video or
// preferences just changed. Runs after the response is on its way; failures
// are logged inside and never reach the candidate.
function fireAlerts(candidateId, options) {
  inBackground(evaluateAlertsForCandidate(candidateId, options));
}

// Deck filters, all optional (see lib/deck.js):
//   q            name, desired role, location, qualification or a skill contains
//   skills       comma separated, any of (max 10)
//   location     location OR preferred location contains
//   expMin/expMax   years of experience
//   maxSalary    expected CTC <= this (LPA) or salary negotiable
//   notice       comma list of notice-period days, e.g. 0,15,30
//   ctcMin/ctcMax/noticeMax  older range filters, still honoured
// plus the hard salary-fit rule against the job being swiped for.
async function deckWhere({ query, recruiterId, job, exclude }) {
  const filters = deckLib.filtersFromQuery(query);
  const and = await deckLib.filterConditions(filters);

  const fit = deckLib.salaryFitCondition(job);
  if (fit) and.push({ candidateProfile: { is: fit } });

  const q = str(query.q, 100);
  if (q) {
    and.push({
      OR: [
        { name: { contains: q, mode: "insensitive" } },
        { candidateProfile: { is: { desiredRole: { contains: q, mode: "insensitive" } } } },
        { candidateProfile: { is: { location: { contains: q, mode: "insensitive" } } } },
        { candidateProfile: { is: { qualification: { contains: q, mode: "insensitive" } } } },
        { candidateProfile: { is: { skillsNormalized: { has: q.toLowerCase() } } } },
      ],
    });
  }

  return {
    role: "candidate",
    profileComplete: true,
    // Anyone already swiped (either way) for THIS job is gone; they can still
    // appear for the recruiter's other jobs.
    candidateSwipesAsCandidate: { none: { recruiterId, jobPostingId: job.id } },
    ...(exclude.length ? { id: { notIn: exclude } } : {}),
    AND: and,
  };
}

// Ranking position of a card, as a sortable string:
//   1. not stale before stale (stale = no activity for ACTIVE_DAYS),
//   2. best match first, +NEW_PROFILE_BONUS for sign-ups under a week old,
//   3. newest sign-up, then id so the order is total.
// The cursor is the last card's position, which stays correct as swiped
// candidates drop out of the list between pages.
function rankKey({ stale, score, isNew, createdAt, id }) {
  const rank = (score ?? 0) + (isNew ? NEW_PROFILE_BONUS : 0);
  return `${stale ? 0 : 1}|${String(rank).padStart(4, "0")}|${String(createdAt.getTime()).padStart(15, "0")}|${id}`;
}

function isStale(profile, now) {
  const last = profile?.activeAt ?? profile?.updatedAt;
  return !last || now - last.getTime() > ACTIVE_DAYS * DAY_MS;
}

async function jobStats(jobId) {
  const groups = await prisma.candidateSwipe.groupBy({
    by: ["action", "stage"],
    where: { jobPostingId: jobId },
    _count: { _all: true },
  });
  const stats = { swiped: 0, shortlisted: 0, interviewing: 0, hired: 0 };
  for (const g of groups) {
    const n = g._count._all;
    stats.swiped += n;
    if (g.action === "right") {
      stats.shortlisted += n;
      if (g.stage === "interview") stats.interviewing += n;
      if (g.stage === "hired") stats.hired += n;
    }
  }
  return stats;
}

// GET /candidates?jobId=&exclude=&limit=10&cursor=&...filters&sort=match|newest
// The recruiter's swipe deck for ONE job: finished, open-to-work profiles,
// minus anyone already swiped for this job, anyone in `exclude` (already in
// the app's stack) and anyone whose salary expectation is above the job's
// budget without being negotiable. Never more cards than swipes left (less
// the excluded ones the app is already holding).
//
// Order: profiles active within the last 15 days first; then best match first
// (new sign-ups under 7 days get +10) and, among equals, the newest sign-up.
// `sort=newest` skips all ranking.
router.get("/", requireRole("recruiter"), async (req, res) => {
  const company = await ensureCompany(req.user);
  const owner = await companyOwner(req.user);

  const jobId = str(req.query.jobId, 100);
  let job;
  if (jobId) {
    job = await prisma.jobPosting.findFirst({ where: { id: jobId, recruiterId: req.user.companyId } });
    if (!job) return res.status(404).json({ error: "Job not found." });
  } else {
    job = await deckLib.defaultJob(req.user.companyId);
    if (!job) return res.status(403).json({ code: "NO_JOB", error: "Please add a job you are hiring for first" });
  }
  if (!job.isOpen) return res.status(409).json({ error: PAUSED_MESSAGE });

  const exclude = deckLib.csv(req.query.exclude).slice(0, 200);
  const requested = Math.min(Math.max(int(req.query.limit, DEFAULT_PAGE), 1), MAX_PAGE);
  const limit = Math.min(requested, company.swipesLeft - exclude.length);
  const companyProfile = await prisma.company.findUnique({
    where: { ownerId: req.user.companyId },
    select: { id: true, name: true, logoUrl: true, verificationStatus: true },
  });
  const jobJson = toJobPosting(
    { ...job, recruiter: { name: owner.name, company: owner.company, companyProfile } },
    { stats: await jobStats(job.id) },
  );
  const respond = (cards, nextCursor, hasMore) =>
    res.json({ candidates: cards, nextCursor, hasMore, swipesLeft: company.swipesLeft, job: jobJson });

  if (limit <= 0) return respond([], null, false);

  const where = await deckWhere({ query: req.query, recruiterId: req.user.companyId, job, exclude });
  const cursor = str(req.query.cursor, 200);

  // Cards carry the "wishlisted" flag and `contact` for people already shortlisted.
  const toCards = async (users) => {
    const rel = await deckLib.relationsFor(req.user.companyId, users.map((u) => u.id));
    return users.map((u) =>
      deckLib.buildCard(u, job, { wishlisted: rel.wishlisted.has(u.id), contact: rel.shortlisted.has(u.id) }),
    );
  };

  if (req.query.sort !== "newest") {
    // Ranking needs scores for the whole filtered set, so score a window of
    // it (the MATCH_WINDOW most recently active) and page through that.
    const users = await prisma.user.findMany({
      where,
      orderBy: [{ candidateProfile: { activeAt: "desc" } }, { id: "desc" }],
      take: MATCH_WINDOW,
      include: { candidateProfile: true },
    });
    const now = Date.now();
    const ranked = users
      .map((u) => {
        const card = deckLib.buildCard(u, job);
        const key = rankKey({
          stale: isStale(u.candidateProfile, now),
          score: card.matchScore,
          isNew: now - u.createdAt.getTime() < NEW_PROFILE_DAYS * DAY_MS,
          createdAt: u.createdAt,
          id: u.id,
        });
        return { user: u, key };
      })
      .sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
    const remaining = cursor ? ranked.filter((r) => r.key < cursor) : ranked;
    const page = remaining.slice(0, limit);
    const cards = await toCards(page.map((r) => r.user));
    return respond(cards, page.length ? page[page.length - 1].key : null, remaining.length > page.length);
  }

  const users = await prisma.user.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: { candidateProfile: true },
  });
  const page = users.slice(0, limit);
  respond(await toCards(page), page.length ? page[page.length - 1].id : null, users.length > limit);
});

// GET /candidates/me/profile -- the signed-in candidate's own hiring profile.
router.get("/me/profile", requireRole("candidate"), async (req, res) => {
  const profile = await prisma.candidateProfile.findUnique({ where: { userId: req.user.id } });
  if (!profile) return res.status(404).json({ error: "No candidate profile yet." });
  res.json(toCandidateProfile(profile));
});

function sendFieldError(res, err) {
  return res.status(400).json({ error: err.message, field: err.field });
}

// PUT /candidates/me/profile { ...CandidateProfile.toMap() }
// All required fields must be sent on every call; a 400 carries
// { error, field } so the app can highlight the input.
router.put("/me/profile", requireRole("candidate"), async (req, res) => {
  let data;
  try {
    data = parseProfileBody(req.body);
  } catch (err) {
    if (err instanceof FieldError) return sendFieldError(res, err);
    throw err;
  }
  const profile = await prisma.candidateProfile.upsert({
    where: { userId: req.user.id },
    create: { userId: req.user.id, ...data },
    update: data,
  });
  res.json(toCandidateProfile(profile));
  // Saving the form finishes onboarding (the app marks the account complete
  // right after), so the candidate counts as live for saved-search alerts.
  fireAlerts(req.user.id, { assumeComplete: true });
});

// POST /candidates/me/active -- "I'm still looking": restarts the 15-day ring.
router.post("/me/active", requireRole("candidate"), async (req, res) => {
  const existing = await prisma.candidateProfile.findUnique({ where: { userId: req.user.id } });
  if (!existing) return res.status(404).json({ error: "No candidate profile yet." });
  const profile = await prisma.candidateProfile.update({
    where: { userId: req.user.id },
    data: { activeAt: new Date() },
  });
  res.json(toCandidateProfile(profile));
});

// PUT /candidates/me/preferences { openToWork?, workModes?, jobTypes?, preferredLocations? }
// Only the keys sent are changed.
router.put("/me/preferences", requireRole("candidate"), async (req, res) => {
  let data;
  try {
    data = parsePreferencesBody(req.body);
  } catch (err) {
    if (err instanceof FieldError) return sendFieldError(res, err);
    throw err;
  }
  const existing = await prisma.candidateProfile.findUnique({ where: { userId: req.user.id } });
  if (!existing) return res.status(404).json({ error: "No candidate profile yet." });
  const profile = await prisma.candidateProfile.update({ where: { userId: req.user.id }, data });
  res.json(toCandidateProfile(profile));
  fireAlerts(req.user.id);
});

// GET /candidates/me/stats -- the candidate's "who looked at me" numbers.
//
// A shortlist on its own is anonymous: it only counts towards hiddenCount.
// A company is named in shortlistedBy once it has contacted the candidate
// (a message from the company, an interview or a task).
router.get("/me/stats", requireRole("candidate"), async (req, res) => {
  const candidateId = req.user.id;
  const [viewedCount, wishlistedCount, shortlists, fromCompany, interviews, tasks] = await Promise.all([
    prisma.candidateSwipe.count({ where: { candidateId } }),
    prisma.wishlistEntry.count({ where: { candidateId } }),
    prisma.candidateSwipe.findMany({
      where: { candidateId, action: "right" },
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      include: {
        recruiter: { select: { id: true, name: true, company: true, companyProfile: true } },
        jobPosting: { select: { title: true, location: true } },
      },
    }),
    // Messages the company itself sent (a candidate can only write after being
    // contacted, and their own messages are not "contact").
    prisma.chatMessage.findMany({
      where: { candidateId, NOT: { senderId: candidateId } },
      distinct: ["companyId"],
      select: { companyId: true },
    }),
    prisma.interview.findMany({ where: { candidateId }, distinct: ["companyId"], select: { companyId: true } }),
    prisma.hiringTask.findMany({ where: { candidateId }, distinct: ["companyId"], select: { companyId: true } }),
  ]);

  const contacted = new Set([...fromCompany, ...interviews, ...tasks].map((r) => r.companyId));

  const shortlistedBy = [];
  const hidden = new Set();
  for (const swipe of shortlists) {
    if (!contacted.has(swipe.recruiterId)) {
      hidden.add(swipe.recruiterId);
      continue;
    }
    const company = swipe.recruiter.companyProfile;
    shortlistedBy.push({
      id: swipe.id,
      recruiterId: swipe.recruiterId,
      companyId: swipe.recruiterId,
      companyName: company?.name || swipe.recruiter.company || "Hiring company",
      industry: company?.industry ?? "",
      hiringFor: swipe.jobPosting?.title || "",
      location: swipe.jobPosting?.location || company?.location || "",
      verified: company?.verificationStatus === "verified",
      logoUrl: company?.logoUrl ?? "",
      stage: swipe.stage,
      date: swipe.createdAt.toISOString(),
    });
  }

  res.json({
    viewedCount,
    wishlistedCount,
    shortlistedCount: shortlists.length,
    hiddenCount: hidden.size,
    shortlistedBy,
  });
});

// POST /candidates/me/resume/autofill (multipart field "resume", PDF <= 5 MB)
// -> { fields }. Reads the PDF to pre-fill the profile form; nothing is
// stored here (the app uploads the file to Cloudinary itself). A scanned PDF
// with no text layer gives { fields: {} }.
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: RESUME_MAX_BYTES, files: 1 },
});

function acceptResume(req, res, next) {
  upload.single("resume")(req, res, (err) => {
    if (!err) return next();
    if (err.code === "LIMIT_FILE_SIZE") {
      return res.status(400).json({ error: "That file is too large. The limit is 5 MB.", field: "resume" });
    }
    if (err instanceof multer.MulterError) {
      return res.status(400).json({ error: "Please choose your resume (PDF)", field: "resume" });
    }
    next(err);
  });
}

router.post("/me/resume/autofill", requireRole("candidate"), acceptResume, async (req, res) => {
  const file = req.file;
  if (!file || !file.buffer || file.buffer.length === 0) {
    return res.status(400).json({ error: "Please choose your resume (PDF)", field: "resume" });
  }
  if (file.buffer.subarray(0, 5).toString("latin1") !== "%PDF-") {
    return res.status(400).json({ error: "This file is not a valid PDF", field: "resume" });
  }
  let fields;
  try {
    fields = await parseResumePdf(file.buffer);
  } catch (err) {
    // A broken, encrypted or truncated PDF: nothing the user can fix but the file.
    return res.status(400).json({ error: "This file is not a valid PDF", field: "resume" });
  }
  res.json({ fields });
});

// GET /candidates/:id -- one candidate card (recruiter only).
router.get("/:id", requireRole("recruiter"), async (req, res) => {
  const user = await prisma.user.findFirst({
    where: { id: req.params.id, role: "candidate" },
    include: { candidateProfile: true },
  });
  if (!user) return res.status(404).json({ error: "Candidate not found." });
  const jobId = str(req.query.jobId, 100);
  const job = jobId
    ? await prisma.jobPosting.findFirst({ where: { id: jobId, recruiterId: req.user.companyId } })
    : await prisma.jobPosting.findFirst({
        where: { recruiterId: req.user.companyId, isOpen: true },
        orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      });
  const rel = await deckLib.relationsFor(req.user.companyId, [user.id]);
  res.json(deckLib.buildCard(user, job, { wishlisted: rel.wishlisted.has(user.id), contact: rel.shortlisted.has(user.id) }));
});

module.exports = router;
