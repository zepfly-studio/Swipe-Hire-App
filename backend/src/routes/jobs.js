const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notifyCompany } = require("../lib/teamNotify");
const { normalizeSkills } = require("../lib/derive");
const { matchScore } = require("../lib/matching");
const { str, num, int, bool, strList, requireRole } = require("../lib/validate");
const { FieldError } = require("../lib/candidateProfile");
const {
  toJobPosting,
  toOpportunity,
  toCandidate,
  jobStatus,
  OPPORTUNITY_INCLUDE,
  POSTING_INCLUDE,
} = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

const MAX_ACTIVE_JOBS = 25;
const ACTIVE_JOBS_ERROR = "You can have up to 25 active jobs. Close an old one first.";
const STATUSES = ["open", "paused", "closed"];
const WORK_MODES = ["onsite", "hybrid", "remote"];
const JOB_TYPES = ["full-time", "part-time", "internship", "contract"];

function fieldError(res, err) {
  return res.status(400).json({ error: err.message, field: err.field });
}

function optionalYears(value, field, label) {
  if (value === undefined || value === null || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > 50) throw new FieldError(field, `Enter years between 0 and 50 for ${label}`);
  return n;
}

function lpa(value, field, { required = false } = {}) {
  if (value === undefined || value === null || value === "") {
    if (required) throw new FieldError(field, "Enter the maximum salary you can offer");
    return 0;
  }
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > 1000) throw new FieldError(field, "Enter a valid salary");
  if (required && n <= 0) throw new FieldError(field, "Enter the maximum salary you can offer");
  return Math.round(n * 100) / 100;
}

/**
 * Validates a job form body (create and full edit). Returns the Prisma data
 * object; `status`/`isOpen` are included only when the body carries one.
 * @throws {FieldError}
 */
function parseJobBody(b, prefix = "") {
  const body = b && typeof b === "object" ? b : {};
  const f = (name) => `${prefix}${name}`;

  const title = str(body.title, 200);
  if (!title) throw new FieldError(f("title"), "A job title is required.");
  const skills = strList(body.skills, 30);
  if (skills.length === 0) throw new FieldError(f("skills"), "Add at least one skill");

  const salaryMaxLpa = lpa(body.salaryMaxLpa, f("salaryMaxLpa"), { required: true });
  const salaryMinLpa = lpa(body.salaryMinLpa, f("salaryMinLpa"));
  if (salaryMinLpa > salaryMaxLpa) throw new FieldError(f("salaryMinLpa"), "Minimum salary cannot be more than maximum salary");

  const minExperienceYears = optionalYears(body.minExperienceYears, f("minExperienceYears"), "minimum experience") ?? 0;
  const maxExperienceYears = optionalYears(body.maxExperienceYears, f("maxExperienceYears"), "maximum experience");
  if (maxExperienceYears !== null && maxExperienceYears < minExperienceYears) {
    throw new FieldError(f("minExperienceYears"), "Minimum experience cannot be more than maximum experience");
  }

  let openings = 1;
  if (body.openings !== undefined && body.openings !== null && body.openings !== "") {
    openings = Number(body.openings);
    if (!Number.isInteger(openings) || openings < 1 || openings > 1000) {
      throw new FieldError(f("openings"), "Openings must be between 1 and 1000");
    }
  }

  let workMode = "onsite";
  if (body.workMode !== undefined && body.workMode !== null && body.workMode !== "") {
    workMode = str(body.workMode, 20).toLowerCase().replace(/[\s_-]+/g, "");
    if (!WORK_MODES.includes(workMode)) throw new FieldError(f("workMode"), "Choose on-site, hybrid or remote");
  }

  let employmentType = "full-time";
  const rawType = body.employmentType ?? body.jobType;
  if (rawType !== undefined && rawType !== null && rawType !== "") {
    employmentType = str(rawType, 30).toLowerCase().replace(/[\s_]+/g, "-");
    if (!JOB_TYPES.includes(employmentType)) {
      throw new FieldError(f("employmentType"), "Choose full-time, part-time, internship or contract");
    }
  }

  const data = {
    title,
    description: str(body.description, 8000),
    skills,
    skillsNormalized: normalizeSkills(skills),
    location: str(body.location, 200),
    employmentType,
    workMode,
    openings,
    salaryMinLpa,
    salaryMaxLpa,
    minExperienceYears,
    maxExperienceYears,
  };

  if (body.status !== undefined) {
    const status = str(body.status, 20).toLowerCase();
    if (!STATUSES.includes(status)) throw new FieldError(f("status"), "Status must be open, paused or closed");
    data.status = status;
    data.isOpen = status === "open";
  } else if (typeof body.isOpen === "boolean") {
    data.isOpen = body.isOpen;
    // Closing via the old flag pauses; reopening a closed job reopens it.
    data.status = body.isOpen ? "open" : "paused";
  }
  return data;
}

// Non-closed postings (open + paused, and legacy isOpen=false rows).
async function activeJobCount(recruiterId, excludeId) {
  return prisma.jobPosting.count({
    where: { recruiterId, status: { not: "closed" }, ...(excludeId ? { id: { not: excludeId } } : {}) },
  });
}

// { swiped, shortlisted, interviewing, hired } per job, from CandidateSwipe.
async function statsFor(jobIds) {
  const stats = new Map(jobIds.map((id) => [id, { swiped: 0, shortlisted: 0, interviewing: 0, hired: 0 }]));
  if (!jobIds.length) return stats;
  const groups = await prisma.candidateSwipe.groupBy({
    by: ["jobPostingId", "action", "stage"],
    where: { jobPostingId: { in: jobIds } },
    _count: { _all: true },
  });
  for (const g of groups) {
    const s = stats.get(g.jobPostingId);
    if (!s) continue;
    const n = g._count._all;
    s.swiped += n;
    if (g.action === "right") {
      s.shortlisted += n;
      if (g.stage === "interview") s.interviewing += n;
      if (g.stage === "hired") s.hired += n;
    }
  }
  return stats;
}

const STATUS_ORDER = { open: 0, paused: 1, closed: 2 };

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
    where: { recruiterId: req.user.companyId },
    orderBy: { createdAt: "desc" },
    include: POSTING_INCLUDE,
  });
  const counts = await prisma.opportunity.groupBy({
    by: ["jobPostingId"],
    where: { jobPostingId: { in: postings.map((p) => p.id) }, status: { not: "withdrawn" } },
    _count: { _all: true },
  });
  const countOf = new Map(counts.map((c) => [c.jobPostingId, c._count._all]));
  const stats = await statsFor(postings.map((p) => p.id));
  // Open first, then paused, then closed; newest first inside each group.
  const sorted = [...postings].sort(
    (a, b) => STATUS_ORDER[jobStatus(a)] - STATUS_ORDER[jobStatus(b)] || b.createdAt - a.createdAt,
  );
  res.json({
    jobs: sorted.map((p) => toJobPosting(p, { applicantsCount: countOf.get(p.id) ?? 0, stats: stats.get(p.id) })),
  });
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
  let data;
  try {
    data = parseJobBody(req.body);
  } catch (err) {
    if (err instanceof FieldError) return fieldError(res, err);
    throw err;
  }
  if (data.status === undefined) {
    data.status = "open";
    data.isOpen = true;
  }
  if (data.status !== "closed" && (await activeJobCount(req.user.companyId)) >= MAX_ACTIVE_JOBS) {
    return res.status(400).json({ error: ACTIVE_JOBS_ERROR });
  }
  const posting = await prisma.jobPosting.create({
    data: { recruiterId: req.user.companyId, ...data },
    include: POSTING_INCLUDE,
  });
  res.status(201).json(toJobPosting(posting, { stats: { swiped: 0, shortlisted: 0, interviewing: 0, hired: 0 } }));
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
  if (posting.recruiterId !== req.user.companyId) {
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

// Moving a closed job back to open/paused counts against the 25-job limit.
async function reopenBlocked(posting, nextStatus) {
  if (nextStatus === undefined || nextStatus === "closed") return false;
  if (jobStatus(posting) !== "closed") return false;
  return (await activeJobCount(posting.recruiterId, posting.id)) >= MAX_ACTIVE_JOBS;
}

// PUT /jobs/:id -- full edit (keeps createdAt). The status only changes when
// the body carries `status` or `isOpen`.
router.put("/:id", requireRole("recruiter"), async (req, res) => {
  const existing = await ownPosting(req, res);
  if (!existing) return;
  let data;
  try {
    data = parseJobBody(req.body);
  } catch (err) {
    if (err instanceof FieldError) return fieldError(res, err);
    throw err;
  }
  if (await reopenBlocked(existing, data.status)) return res.status(400).json({ error: ACTIVE_JOBS_ERROR });
  const posting = await prisma.jobPosting.update({ where: { id: req.params.id }, data, include: POSTING_INCLUDE });
  const stats = await statsFor([posting.id]);
  res.json(toJobPosting(posting, { stats: stats.get(posting.id) }));
});

// PATCH /jobs/:id/status { status: open | paused | closed } -> { job }
router.patch("/:id/status", requireRole("recruiter"), async (req, res) => {
  const status = str(req.body?.status, 20).toLowerCase();
  if (!STATUSES.includes(status)) {
    return res.status(400).json({ error: "Status must be open, paused or closed.", field: "status" });
  }
  const existing = await ownPosting(req, res);
  if (!existing) return;
  if (await reopenBlocked(existing, status)) return res.status(400).json({ error: ACTIVE_JOBS_ERROR });
  const posting = await prisma.jobPosting.update({
    where: { id: req.params.id },
    data: { status, isOpen: status === "open" },
    include: POSTING_INCLUDE,
  });
  const stats = await statsFor([posting.id]);
  res.json({ job: toJobPosting(posting, { stats: stats.get(posting.id) }) });
});

// PATCH /jobs/:id { isOpen } -- the older toggle; keeps `status` in sync
// (false pauses, true reopens). A closed job stays closed when told isOpen=false.
router.patch("/:id", requireRole("recruiter"), async (req, res) => {
  const existing = await ownPosting(req, res);
  if (!existing) return;
  const isOpen = bool(req.body?.isOpen, true);
  const status = isOpen ? "open" : jobStatus(existing) === "closed" ? "closed" : "paused";
  if (await reopenBlocked(existing, status)) return res.status(400).json({ error: ACTIVE_JOBS_ERROR });
  const posting = await prisma.jobPosting.update({
    where: { id: req.params.id },
    data: { isOpen, status },
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

  await notifyCompany(posting.recruiterId, {
    title: "New applicant",
    body: `${req.user.name} applied for ${posting.title}.`,
    type: "applied",
    opportunityId: opportunity.id,
    email: true,
  });

  res.status(201).json(toOpportunity(opportunity));
});

module.exports = router;
