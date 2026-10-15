const express = require("express");
const multer = require("multer");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { normalizeSkills } = require("../lib/derive");
const { bestMatch } = require("../lib/matching");
const { str, int, requireRole } = require("../lib/validate");
const { toCandidate, toCandidateProfile } = require("../lib/serializers");
const { FieldError, parseProfileBody, parsePreferencesBody } = require("../lib/candidateProfile");
const { parseResumePdf } = require("../lib/resumeParser");

const router = express.Router();
router.use(requireAuth);

const MAX_PAGE = 50;
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

function csv(value) {
  return String(value || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

function optionalNumber(value) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

// Deck filters, all optional:
//   q           name, desired role, location or a skill contains
//   skills      comma separated; a candidate needs any one of them
//   location    location contains
//   expMin/expMax   years of experience
//   ctcMin/ctcMax   expected CTC in LPA
//   noticeMax   longest acceptable notice period, in days
function profileFilter(query) {
  const is = {};
  const skills = normalizeSkills(csv(query.skills));
  if (skills.length) is.skillsNormalized = { hasSome: skills };

  const location = str(query.location, 100);
  if (location) is.location = { contains: location, mode: "insensitive" };

  const expMin = optionalNumber(query.expMin);
  const expMax = optionalNumber(query.expMax);
  if (expMin !== null || expMax !== null) {
    is.experienceYears = { ...(expMin !== null ? { gte: expMin } : {}), ...(expMax !== null ? { lte: expMax } : {}) };
  }
  const ctcMin = optionalNumber(query.ctcMin);
  const ctcMax = optionalNumber(query.ctcMax);
  if (ctcMin !== null || ctcMax !== null) {
    is.expectedSalaryLpa = { ...(ctcMin !== null ? { gte: ctcMin } : {}), ...(ctcMax !== null ? { lte: ctcMax } : {}) };
  }
  const noticeMax = optionalNumber(query.noticeMax);
  if (noticeMax !== null) is.noticeDays = { lte: noticeMax };

  // Candidates who switched "open to work" off are not on any deck.
  is.openToWork = true;
  return { is };
}

function deckWhere(query, recruiterId) {
  const where = {
    role: "candidate",
    profileComplete: true,
    candidateProfile: profileFilter(query),
    swipedBy: { none: { recruiterId } },
  };
  const q = str(query.q, 100);
  if (q) {
    where.OR = [
      { name: { contains: q, mode: "insensitive" } },
      { candidateProfile: { is: { desiredRole: { contains: q, mode: "insensitive" } } } },
      { candidateProfile: { is: { location: { contains: q, mode: "insensitive" } } } },
      { candidateProfile: { is: { qualification: { contains: q, mode: "insensitive" } } } },
      { candidateProfile: { is: { skillsNormalized: { has: q.toLowerCase() } } } },
    ];
  }
  return where;
}

// The postings a candidate is scored against: one if the recruiter picked
// it, otherwise all of their open ones (the best fit wins).
async function postingsToMatch(recruiterId, jobId) {
  const where = { recruiterId, isOpen: true, ...(jobId ? { id: jobId } : {}) };
  return prisma.jobPosting.findMany({
    where,
    select: { id: true, title: true, skillsNormalized: true, minExperienceYears: true, location: true, salaryMinLpa: true, salaryMaxLpa: true },
  });
}

function cardWithMatch(user, postings) {
  const profile = user.candidateProfile;
  const match = profile && postings.length ? bestMatch(postings, profile) : null;
  return toCandidate(user, profile, match);
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

// GET /candidates?cursor=&limit=20&...filters&jobId=&sort=match|newest
// The recruiter's swipe deck: finished profiles only, excluding anyone this
// recruiter has already swiped on (so the deck is the same on every device).
// Each card carries its best match against the recruiter's open postings.
//
// Order: profiles active within the last 15 days first; then best match first
// (new sign-ups under 7 days get +10) and, among equals, the newest sign-up.
// With no open posting there is nothing to match against, so that is newest
// first. `sort=newest` skips all ranking. Candidates with openToWork off are
// never listed.
router.get("/", requireRole("recruiter"), async (req, res) => {
  const limit = Math.min(Math.max(int(req.query.limit, 20), 1), MAX_PAGE);
  const jobId = str(req.query.jobId, 100);
  const where = deckWhere(req.query, req.user.id);
  const postings = await postingsToMatch(req.user.id, jobId);
  const cursor = str(req.query.cursor, 200);
  const newestFirst = [{ createdAt: "desc" }, { id: "desc" }];

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
        const card = cardWithMatch(u, postings);
        const key = rankKey({
          stale: isStale(u.candidateProfile, now),
          score: card.matchScore,
          isNew: now - u.createdAt.getTime() < NEW_PROFILE_DAYS * DAY_MS,
          createdAt: u.createdAt,
          id: u.id,
        });
        return { card, key };
      })
      .sort((a, b) => (a.key < b.key ? 1 : a.key > b.key ? -1 : 0));
    const remaining = cursor ? ranked.filter((r) => r.key < cursor) : ranked;
    const page = remaining.slice(0, limit);
    return res.json({
      candidates: page.map((r) => r.card),
      nextCursor: page.length ? page[page.length - 1].key : null,
      hasMore: remaining.length > limit,
    });
  }

  const users = await prisma.user.findMany({
    where,
    orderBy: newestFirst,
    take: limit,
    ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    include: { candidateProfile: true },
  });

  res.json({
    candidates: users.map((u) => cardWithMatch(u, postings)),
    nextCursor: users.length ? users[users.length - 1].id : null,
    hasMore: users.length === limit,
  });
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
});

// GET /candidates/me/stats -- the candidate's "who looked at me" numbers.
//
// A shortlist on its own is anonymous: it only counts towards hiddenCount.
// The recruiter's company is named in shortlistedBy once they have contacted
// the candidate, i.e. there is an Opportunity between them.
router.get("/me/stats", requireRole("candidate"), async (req, res) => {
  const swipes = await prisma.swipe.findMany({
    where: { candidateId: req.user.id },
    include: { recruiter: { select: { id: true, name: true, company: true, companyProfile: true } } },
    orderBy: { updatedAt: "desc" },
  });
  const shortlists = swipes.filter((s) => s.state === "shortlist");

  const opportunities = shortlists.length
    ? await prisma.opportunity.findMany({
        where: { candidateId: req.user.id, recruiterId: { in: shortlists.map((s) => s.recruiterId) } },
        include: { jobPosting: { select: { location: true } } },
        orderBy: { updatedAt: "desc" },
      })
    : [];
  // Most recently touched opportunity per recruiter.
  const latestByRecruiter = new Map();
  for (const o of opportunities) if (!latestByRecruiter.has(o.recruiterId)) latestByRecruiter.set(o.recruiterId, o);

  const shortlistedBy = [];
  let hiddenCount = 0;
  for (const swipe of shortlists) {
    const opportunity = latestByRecruiter.get(swipe.recruiterId);
    if (!opportunity) {
      hiddenCount += 1;
      continue;
    }
    const company = swipe.recruiter.companyProfile;
    shortlistedBy.push({
      id: opportunity.id,
      recruiterId: swipe.recruiterId,
      ...(company ? { companyId: company.id } : {}),
      companyName: company?.name || swipe.recruiter.company || "Hiring company",
      industry: company?.industry ?? "",
      hiringFor: opportunity.role || "",
      location: opportunity.jobPosting?.location || company?.location || "",
      verified: company?.verificationStatus === "verified",
      logoUrl: company?.logoUrl ?? "",
      stage: opportunity.status,
      date: swipe.updatedAt.toISOString(),
    });
  }

  res.json({
    viewedCount: swipes.length,
    wishlistedCount: swipes.filter((s) => s.state === "wishlist").length,
    shortlistedCount: shortlists.length,
    hiddenCount,
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
  const postings = await postingsToMatch(req.user.id, str(req.query.jobId, 100));
  res.json(cardWithMatch(user, postings));
});

module.exports = router;
