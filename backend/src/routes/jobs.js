const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify } = require("../lib/notify");
const { normalizeSkills } = require("../lib/derive");
const { matchScore } = require("../lib/matching");
const { str, num, int, bool, strList, requireRole } = require("../lib/validate");
const {
  toJobPosting,
  toOpportunity,
  toCandidate,
  OPPORTUNITY_INCLUDE,
  POSTING_INCLUDE,
} = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

function postingData(b) {
  const skills = strList(b.skills);
  return {
    title: str(b.title, 200),
    description: str(b.description, 8000),
    skills,
    skillsNormalized: normalizeSkills(skills),
    location: str(b.location, 200),
    employmentType: str(b.employmentType, 100),
    salaryMinLpa: num(b.salaryMinLpa),
    salaryMaxLpa: num(b.salaryMaxLpa),
    minExperienceYears: Math.max(0, num(b.minExperienceYears)),
    isOpen: bool(b.isOpen, true),
  };
}

function csv(value) {
  return String(value || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

// GET /jobs filters, all optional:
//   q            title, description, skill, or company name contains
//   location     location contains
//   type         employment type (Full-time, Contract...)
//   salaryMin    postings that pay at least this many LPA at the top end
//   skills       comma separated; a posting needs any one of them
//   remote=1     remote roles only
//   experience   my years of experience; hides roles that ask for more
function jobWhere(query) {
  const and = [{ isOpen: true }];
  const q = str(query.q, 100);
  if (q) {
    and.push({
      OR: [
        { title: { contains: q, mode: "insensitive" } },
        { description: { contains: q, mode: "insensitive" } },
        { skillsNormalized: { has: q.toLowerCase() } },
        { recruiter: { company: { contains: q, mode: "insensitive" } } },
        { recruiter: { companyProfile: { is: { name: { contains: q, mode: "insensitive" } } } } },
      ],
    });
  }
  const location = str(query.location, 100);
  if (location) and.push({ location: { contains: location, mode: "insensitive" } });
  // "Full-time" and "Full Time" are the same thing; match on the first word.
  const typeWord = str(query.type, 50).toLowerCase().split(/[\s-]+/)[0];
  if (typeWord) and.push({ employmentType: { contains: typeWord, mode: "insensitive" } });
  if (String(query.remote) === "1") and.push({ location: { contains: "remote", mode: "insensitive" } });
  const salaryMin = num(query.salaryMin, 0);
  if (salaryMin > 0) and.push({ salaryMaxLpa: { gte: salaryMin } });
  const skills = normalizeSkills(csv(query.skills));
  if (skills.length) and.push({ skillsNormalized: { hasSome: skills } });
  if (query.experience !== undefined && query.experience !== "") {
    and.push({ minExperienceYears: { lte: Math.max(0, num(query.experience, 0)) } });
  }
  return { AND: and };
}

async function profileOf(userId) {
  return prisma.candidateProfile.findUnique({ where: { userId } });
}

function withMatch(posting, profile) {
  if (!profile) return toJobPosting(posting);
  const { score, reasons } = matchScore(posting, profile);
  return toJobPosting(posting, { matchScore: score, matchReasons: reasons });
}

// GET /jobs?...filters&sort=match|newest&limit=100 -- open postings. For a
// candidate each one carries a match score against their profile.
router.get("/", async (req, res) => {
  const limit = Math.min(Math.max(int(req.query.limit, 100), 1), 200);
  const postings = await prisma.jobPosting.findMany({
    where: jobWhere(req.query),
    orderBy: { createdAt: "desc" },
    take: limit,
    include: POSTING_INCLUDE,
  });
  const profile = req.user.role === "candidate" ? await profileOf(req.user.id) : null;
  let jobs = postings.map((p) => withMatch(p, profile));
  if (req.query.sort === "match" && profile) jobs = jobs.sort((a, b) => b.matchScore - a.matchScore);
  res.json({ jobs });
});

// GET /jobs/recommended -- the open roles that fit this candidate best,
// excluding ones they already applied to.
router.get("/recommended", requireRole("candidate"), async (req, res) => {
  const profile = await profileOf(req.user.id);
  if (!profile) return res.json({ jobs: [] });

  const applied = await prisma.opportunity.findMany({
    where: { candidateId: req.user.id, jobPostingId: { not: null } },
    select: { jobPostingId: true },
  });
  const appliedIds = new Set(applied.map((a) => a.jobPostingId));

  const postings = await prisma.jobPosting.findMany({
    where: { isOpen: true },
    orderBy: { createdAt: "desc" },
    take: 200,
    include: POSTING_INCLUDE,
  });
  const jobs = postings
    .filter((p) => !appliedIds.has(p.id))
    .map((p) => withMatch(p, profile))
    .filter((j) => j.matchScore >= 40)
    .sort((a, b) => b.matchScore - a.matchScore)
    .slice(0, 10);
  res.json({ jobs });
});

// GET /jobs/mine -- the recruiter's own postings, open or closed, each with
// how many people applied.
router.get("/mine", requireRole("recruiter"), async (req, res) => {
  const postings = await prisma.jobPosting.findMany({
    where: { recruiterId: req.user.id },
    orderBy: { createdAt: "desc" },
    include: POSTING_INCLUDE,
  });
  const counts = await prisma.opportunity.groupBy({
    by: ["jobPostingId"],
    where: { jobPostingId: { in: postings.map((p) => p.id) }, status: { not: "withdrawn" } },
    _count: { _all: true },
  });
  const countOf = new Map(counts.map((c) => [c.jobPostingId, c._count._all]));
  res.json({ jobs: postings.map((p) => toJobPosting(p, { applicantsCount: countOf.get(p.id) ?? 0 })) });
});

// GET /jobs/saved -- what this candidate bookmarked: the ids (for the save
// toggles) and the full postings (for the Saved tab), newest save first, in
// one query so the app never has to fetch them one by one.
router.get("/saved", requireRole("candidate"), async (req, res) => {
  const saved = await prisma.savedJob.findMany({
    where: { candidateId: req.user.id },
    orderBy: { savedAt: "desc" },
    include: { jobPosting: { include: POSTING_INCLUDE } },
  });
  res.json({
    ids: saved.map((s) => s.jobPostingId),
    jobs: saved.map((s) => toJobPosting(s.jobPosting)),
  });
});

// PUT /jobs/saved/:id | DELETE /jobs/saved/:id
router.put("/saved/:id", requireRole("candidate"), async (req, res) => {
  const posting = await prisma.jobPosting.findUnique({ where: { id: req.params.id } });
  if (!posting) return res.status(404).json({ error: "Job posting not found." });
  await prisma.savedJob.upsert({
    where: { candidateId_jobPostingId: { candidateId: req.user.id, jobPostingId: posting.id } },
    create: { candidateId: req.user.id, jobPostingId: posting.id },
    update: {},
  });
  res.json({ saved: true });
});

router.delete("/saved/:id", requireRole("candidate"), async (req, res) => {
  await prisma.savedJob.deleteMany({ where: { candidateId: req.user.id, jobPostingId: req.params.id } });
  res.json({ saved: false });
});

// POST /jobs -- publish a new posting.
router.post("/", requireRole("recruiter"), async (req, res) => {
  const data = postingData(req.body || {});
  if (!data.title) return res.status(400).json({ error: "A job title is required." });
  const posting = await prisma.jobPosting.create({
    data: { recruiterId: req.user.id, ...data },
    include: POSTING_INCLUDE,
  });
  res.status(201).json(toJobPosting(posting));
});

// GET /jobs/:id
router.get("/:id", async (req, res) => {
  const posting = await prisma.jobPosting.findUnique({ where: { id: req.params.id }, include: POSTING_INCLUDE });
  if (!posting) return res.status(404).json({ error: "Job posting not found." });
  const profile = req.user.role === "candidate" ? await profileOf(req.user.id) : null;
  res.json(withMatch(posting, profile));
});

async function ownPosting(req, res) {
  const posting = await prisma.jobPosting.findUnique({ where: { id: req.params.id } });
  if (!posting) {
    res.status(404).json({ error: "Job posting not found." });
    return null;
  }
  if (posting.recruiterId !== req.user.id) {
    res.status(403).json({ error: "You can only edit your own postings." });
    return null;
  }
  return posting;
}

// GET /jobs/:id/applicants -- everyone who applied, best match first, with
// where each stands in the pipeline.
router.get("/:id/applicants", requireRole("recruiter"), async (req, res) => {
  const posting = await ownPosting(req, res);
  if (!posting) return;

  const opportunities = await prisma.opportunity.findMany({
    where: { jobPostingId: posting.id },
    include: OPPORTUNITY_INCLUDE,
    orderBy: { updatedAt: "desc" },
  });
  const users = await prisma.user.findMany({
    where: { id: { in: opportunities.map((o) => o.candidateId) } },
    include: { candidateProfile: true },
  });
  const byId = new Map(users.map((u) => [u.id, u]));

  const applicants = opportunities.map((o) => {
    const user = byId.get(o.candidateId);
    const profile = user?.candidateProfile;
    const match = profile ? matchScore(posting, profile) : { score: null, reasons: [] };
    return {
      opportunity: toOpportunity(o),
      candidate: user ? toCandidate(user, profile, { ...match, jobTitle: posting.title }) : null,
    };
  });
  applicants.sort((a, b) => (b.candidate?.matchScore ?? -1) - (a.candidate?.matchScore ?? -1));

  const full = await prisma.jobPosting.findUnique({ where: { id: posting.id }, include: POSTING_INCLUDE });
  res.json({ job: toJobPosting(full, { applicantsCount: applicants.length }), applicants });
});

// PUT /jobs/:id -- full edit (keeps createdAt).
router.put("/:id", requireRole("recruiter"), async (req, res) => {
  if (!(await ownPosting(req, res))) return;
  const data = postingData(req.body || {});
  if (!data.title) return res.status(400).json({ error: "A job title is required." });
  const posting = await prisma.jobPosting.update({ where: { id: req.params.id }, data, include: POSTING_INCLUDE });
  res.json(toJobPosting(posting));
});

// PATCH /jobs/:id { isOpen }
router.patch("/:id", requireRole("recruiter"), async (req, res) => {
  if (!(await ownPosting(req, res))) return;
  const posting = await prisma.jobPosting.update({
    where: { id: req.params.id },
    data: { isOpen: bool(req.body?.isOpen, true) },
    include: POSTING_INCLUDE,
  });
  res.json(toJobPosting(posting));
});

// GET /jobs/:id/application -- has this candidate already applied?
router.get("/:id/application", requireRole("candidate"), async (req, res) => {
  const existing = await prisma.opportunity.findFirst({
    where: { candidateId: req.user.id, jobPostingId: req.params.id },
  });
  res.json({ applied: Boolean(existing) });
});

// POST /jobs/:id/apply -- creates the "applied" opportunity the recruiter
// then manages on their Pipeline tab, and tells them.
router.post("/:id/apply", requireRole("candidate"), async (req, res) => {
  const posting = await prisma.jobPosting.findUnique({ where: { id: req.params.id }, include: POSTING_INCLUDE });
  if (!posting) return res.status(404).json({ error: "Job posting not found." });
  if (!posting.isOpen) return res.status(409).json({ error: "This role is no longer accepting applications." });

  const existing = await prisma.opportunity.findFirst({
    where: { candidateId: req.user.id, jobPostingId: posting.id },
  });
  if (existing) return res.status(409).json({ error: "You have already applied to this role." });

  const opportunity = await prisma.opportunity.create({
    data: {
      candidateId: req.user.id,
      recruiterId: posting.recruiterId,
      jobPostingId: posting.id,
      role: posting.title,
      status: "applied",
    },
    include: OPPORTUNITY_INCLUDE,
  });

  await notify(posting.recruiterId, {
    title: "New applicant",
    body: `${req.user.name} applied for ${posting.title}.`,
    type: "applied",
    opportunityId: opportunity.id,
    email: true,
  });

  res.status(201).json(toOpportunity(opportunity));
});

module.exports = router;
