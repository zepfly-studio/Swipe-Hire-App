const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { normalizeSkills, parseExperienceYears, parseNoticeDays } = require("../lib/derive");
const { bestMatch } = require("../lib/matching");
const { str, num, int, strList, requireRole } = require("../lib/validate");
const { toCandidate, toCandidateProfile } = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

const MAX_PAGE = 50;
const MATCH_WINDOW = 200;

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

  return Object.keys(is).length ? { is } : { isNot: null };
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

// Ranking position of a card: best match first, then the newest sign-up, then
// id so the order is total. The cursor is the last card's position, which
// stays correct as swiped candidates drop out of the list between pages.
function rankKey(score, createdAt, id) {
  return `${String(score ?? -1).padStart(4, "0")}|${String(createdAt.getTime()).padStart(15, "0")}|${id}`;
}

// GET /candidates?cursor=&limit=20&...filters&jobId=&sort=match|newest
// The recruiter's swipe deck: finished profiles only, excluding anyone this
// recruiter has already swiped on (so the deck is the same on every device).
// Each card carries its best match against the recruiter's open postings.
//
// Order: with at least one open posting the best match comes first and, among
// equal matches, the newest sign-up (`sort=newest` skips the match ranking).
// With no posting there is nothing to match against, so newest comes first.
router.get("/", requireRole("recruiter"), async (req, res) => {
  const limit = Math.min(Math.max(int(req.query.limit, 20), 1), MAX_PAGE);
  const jobId = str(req.query.jobId, 100);
  const where = deckWhere(req.query, req.user.id);
  const postings = await postingsToMatch(req.user.id, jobId);
  const cursor = str(req.query.cursor, 200);
  const newestFirst = [{ createdAt: "desc" }, { id: "desc" }];

  if (req.query.sort !== "newest" && postings.length) {
    // Ranking needs scores for the whole filtered set, so score a window of
    // it (the newest MATCH_WINDOW candidates) and page through that.
    const users = await prisma.user.findMany({
      where,
      orderBy: newestFirst,
      take: MATCH_WINDOW,
      include: { candidateProfile: true },
    });
    const ranked = users
      .map((u) => {
        const card = cardWithMatch(u, postings);
        return { card, key: rankKey(card.matchScore, u.createdAt, u.id) };
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

// PUT /candidates/me/profile { ...CandidateProfile.toMap() }
router.put("/me/profile", requireRole("candidate"), async (req, res) => {
  const b = req.body || {};
  const skills = strList(b.skills);
  const experience = str(b.experience, 200);
  const noticePeriod = str(b.noticePeriod, 100);
  const data = {
    age: int(b.age),
    qualification: str(b.qualification, 200),
    experience,
    desiredRole: str(b.desiredRole, 200),
    location: str(b.location, 200),
    skills,
    skillsNormalized: normalizeSkills(skills),
    experienceYears: parseExperienceYears(experience),
    noticeDays: parseNoticeDays(noticePeriod),
    expectedSalaryLpa: num(b.expectedSalaryLpa),
    noticePeriod,
    about: str(b.about, 4000),
    currentCompany: str(b.currentCompany, 200),
    currentSalaryLpa: num(b.currentSalaryLpa),
    photoUrl: str(b.photoUrl, 1000),
    resumeUrl: str(b.resumeUrl, 1000),
    introVideoUrl: str(b.introVideoUrl, 1000),
  };
  const profile = await prisma.candidateProfile.upsert({
    where: { userId: req.user.id },
    create: { userId: req.user.id, ...data },
    update: data,
  });
  res.json(toCandidateProfile(profile));
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
