// What a recruiter's deck, saved searches and alert matching share: the filter
// vocabulary, how it becomes a database condition, how the same filters are
// checked in memory against one candidate, and the card shape.

const { prisma } = require("./prisma");
const { normalizeSkills } = require("./derive");
const { matchScore } = require("./matching");
const { toCandidate } = require("./serializers");

const MAX_SKILL_FILTERS = 10;
const MAX_NOTICE_BUCKETS = 10;

// Candidate preference values the work mode / job type filters accept.
const WORK_MODES = ["onsite", "hybrid", "remote"];
const JOB_TYPES = ["full-time", "part-time", "internship", "contract"];
// What a candidate picks as their qualification (the app's dropdown).
const QUALIFICATIONS = ["10th", "12th", "Diploma", "Graduate", "Post Graduate", "PhD"];

// A recruiter who never posts a job still swipes: their swipes hang off one
// private "general hiring" job, asked for with jobId=GENERAL_JOB_ID. It is not
// open (isOpen=false), so no candidate-facing list ever shows it, and has no
// budget so no salary rule applies to it.
const GENERAL_STATUS = "general";
const GENERAL_JOB_ID = "general";

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

function cleanString(value, max) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function noticeList(value) {
  const raw = Array.isArray(value) ? value : csv(value);
  const out = [];
  for (const item of raw) {
    const n = Number(String(item).trim().split(/\s+/)[0]);
    if (Number.isInteger(n) && n >= 0 && n <= 365 && !out.includes(n)) out.push(n);
  }
  return out.slice(0, MAX_NOTICE_BUCKETS);
}

function choiceList(value, allowed) {
  const raw = Array.isArray(value) ? value : csv(value);
  const out = [];
  for (const item of raw) {
    const v = String(item ?? "").trim().toLowerCase().replace(/[\s_]+/g, "-").replace(/^on-site$/, "onsite");
    if (allowed.includes(v) && !out.includes(v)) out.push(v);
  }
  return out;
}

function qualificationList(value) {
  const raw = Array.isArray(value) ? value : csv(value);
  const out = [];
  for (const item of raw) {
    const q = QUALIFICATIONS.find((o) => o.toLowerCase() === String(item ?? "").trim().toLowerCase());
    if (q && !out.includes(q)) out.push(q);
  }
  return out;
}

function skillList(value) {
  const raw = Array.isArray(value) ? value : csv(value);
  const seen = new Set();
  const out = [];
  for (const item of raw) {
    const s = cleanString(String(item ?? ""), 40);
    if (s && !seen.has(s.toLowerCase())) {
      seen.add(s.toLowerCase());
      out.push(s);
    }
  }
  return out.slice(0, MAX_SKILL_FILTERS);
}

/**
 * The deck query string, as the canonical filter object also stored by saved
 * searches: { role, location, minExp, maxExp, minSalary, maxSalary, notice[],
 * skills[], workModes[], jobTypes[], qualifications[], education }.
 * The older ctcMin/ctcMax/noticeMax query keys still work (`extra`).
 */
function filtersFromQuery(query) {
  return {
    role: cleanString(query.role, 100),
    location: cleanString(query.location, 100),
    minExp: optionalNumber(query.expMin),
    maxExp: optionalNumber(query.expMax),
    minSalary: optionalNumber(query.minSalary),
    maxSalary: optionalNumber(query.maxSalary),
    notice: noticeList(query.notice),
    skills: skillList(query.skills),
    workModes: choiceList(query.workMode, WORK_MODES),
    jobTypes: choiceList(query.jobType, JOB_TYPES),
    qualifications: qualificationList(query.qualification),
    education: cleanString(query.education, 60),
    extra: {
      ctcMin: optionalNumber(query.ctcMin),
      ctcMax: optionalNumber(query.ctcMax),
      noticeMax: optionalNumber(query.noticeMax),
    },
  };
}

/** A saved search's stored filters, cleaned. */
function cleanFilters(input) {
  const f = input && typeof input === "object" ? input : {};
  const bounded = (v) => {
    const n = optionalNumber(v);
    return n !== null && n >= 0 ? n : null;
  };
  return {
    role: cleanString(f.role, 100),
    location: cleanString(f.location, 60),
    minExp: bounded(f.minExp),
    maxExp: bounded(f.maxExp),
    minSalary: bounded(f.minSalary),
    maxSalary: bounded(f.maxSalary),
    notice: noticeList(f.notice),
    skills: skillList(f.skills),
    workModes: choiceList(f.workModes, WORK_MODES),
    jobTypes: choiceList(f.jobTypes, JOB_TYPES),
    qualifications: qualificationList(f.qualifications),
    education: cleanString(f.education, 60),
  };
}

function hasAnyFilter(f) {
  return (
    Boolean(f.role) ||
    Boolean(f.location) ||
    f.minExp !== null ||
    f.maxExp !== null ||
    (f.minSalary ?? null) !== null ||
    f.maxSalary !== null ||
    f.notice.length > 0 ||
    f.skills.length > 0 ||
    (f.workModes || []).length > 0 ||
    (f.jobTypes || []).length > 0 ||
    (f.qualifications || []).length > 0 ||
    Boolean(f.education)
  );
}

// Candidates whose preferredLocations contain `location` (case-insensitive
// substring). Prisma can't substring-match inside a scalar list, so this is
// resolved in SQL and joined back as an id list.
async function userIdsPreferringLocation(location) {
  const rows = await prisma.$queryRaw`
    SELECT "userId" FROM "candidate_profiles"
    WHERE EXISTS (
      SELECT 1 FROM unnest("preferredLocations") AS l
      WHERE position(lower(${location}::text) in lower(l)) > 0
    )`;
  return rows.map((r) => r.userId);
}

/**
 * Prisma conditions (an AND list) on the User row for these filters. Always
 * restricts to live, open-to-work candidates. Salary fit against a job is NOT
 * here; the deck adds it.
 */
async function filterConditions(filters) {
  const profile = [{ openToWork: true }];
  const and = [];

  if (filters.skills.length) {
    const skills = normalizeSkills(filters.skills);
    if (skills.length) profile.push({ skillsNormalized: { hasSome: skills } });
  }
  if (filters.minExp !== null) profile.push({ experienceYears: { gte: filters.minExp } });
  if (filters.maxExp !== null) profile.push({ experienceYears: { lte: filters.maxExp } });
  // Expected salary inside [minSalary, maxSalary]; people open to negotiate are always included.
  if (filters.maxSalary !== null) {
    profile.push({ OR: [{ expectedSalaryLpa: { lte: filters.maxSalary } }, { salaryNegotiable: true }] });
  }
  if (filters.minSalary != null) {
    profile.push({ OR: [{ expectedSalaryLpa: { gte: filters.minSalary } }, { salaryNegotiable: true }] });
  }
  if (filters.role) {
    profile.push({
      OR: [
        { desiredRole: { contains: filters.role, mode: "insensitive" } },
        { currentPost: { contains: filters.role, mode: "insensitive" } },
      ],
    });
  }
  if (filters.notice.length) profile.push({ noticeDays: { in: filters.notice } });
  if (filters.workModes?.length) profile.push({ workModes: { hasSome: filters.workModes } });
  if (filters.jobTypes?.length) profile.push({ jobTypes: { hasSome: filters.jobTypes } });
  if (filters.qualifications?.length) {
    profile.push({ OR: filters.qualifications.map((q) => ({ qualification: { equals: q, mode: "insensitive" } })) });
  }
  // "B.Tech", "MBA", "Jaipur University": the degree or the college contains it.
  if (filters.education) {
    profile.push({
      OR: [
        { degree: { contains: filters.education, mode: "insensitive" } },
        { college: { contains: filters.education, mode: "insensitive" } },
      ],
    });
  }

  const extra = filters.extra || {};
  if (extra.ctcMin != null) profile.push({ expectedSalaryLpa: { gte: extra.ctcMin } });
  if (extra.ctcMax != null) profile.push({ expectedSalaryLpa: { lte: extra.ctcMax } });
  if (extra.noticeMax != null) profile.push({ noticeDays: { lte: extra.noticeMax } });

  if (filters.location) {
    const ids = await userIdsPreferringLocation(filters.location);
    profile.push({
      OR: [{ location: { contains: filters.location, mode: "insensitive" } }, ...(ids.length ? [{ userId: { in: ids } }] : [])],
    });
  }

  and.push({ candidateProfile: { is: { AND: profile } } });
  return and;
}

/** The same filters, checked in memory (alert matching). */
function filtersMatch(filters, profile) {
  if (!profile || profile.openToWork === false) return false;
  const f = cleanFilters(filters);
  if (f.skills.length) {
    const want = normalizeSkills(f.skills);
    const have = new Set(profile.skillsNormalized || []);
    if (!want.some((s) => have.has(s))) return false;
  }
  const years = Number(profile.experienceYears) || 0;
  if (f.minExp !== null && years < f.minExp) return false;
  if (f.maxExp !== null && years > f.maxExp) return false;
  if (f.maxSalary !== null && !profile.salaryNegotiable && !(Number(profile.expectedSalaryLpa) <= f.maxSalary)) return false;
  if (f.minSalary !== null && !profile.salaryNegotiable && !(Number(profile.expectedSalaryLpa) >= f.minSalary)) return false;
  if (f.role) {
    const needle = f.role.toLowerCase();
    if (![profile.desiredRole, profile.currentPost].some((r) => String(r || "").toLowerCase().includes(needle))) return false;
  }
  if (f.notice.length && !f.notice.includes(profile.noticeDays)) return false;
  if (f.workModes.length && !f.workModes.some((m) => (profile.workModes || []).includes(m))) return false;
  if (f.jobTypes.length && !f.jobTypes.some((t) => (profile.jobTypes || []).includes(t))) return false;
  if (f.qualifications.length && !f.qualifications.some((q) => q.toLowerCase() === String(profile.qualification || "").toLowerCase())) return false;
  if (f.education) {
    const needle = f.education.toLowerCase();
    if (![profile.degree, profile.college].some((v) => String(v || "").toLowerCase().includes(needle))) return false;
  }
  if (f.location) {
    const needle = f.location.toLowerCase();
    const places = [profile.location, ...(profile.preferredLocations || [])];
    if (!places.some((p) => String(p || "").toLowerCase().includes(needle))) return false;
  }
  return true;
}

/** Hard salary rule: expected <= the job's maximum, or negotiable, or unknown. */
function salaryFits(job, profile) {
  const max = Number(job.salaryMaxLpa) || 0;
  const expected = Number(profile.expectedSalaryLpa) || 0;
  return Boolean(profile.salaryNegotiable) || max <= 0 || expected <= 0 || expected <= max;
}

/** Prisma condition for the same rule, on the CandidateProfile row. */
function salaryFitCondition(job) {
  const max = Number(job.salaryMaxLpa) || 0;
  if (max <= 0) return null;
  return { OR: [{ expectedSalaryLpa: { lte: max } }, { salaryNegotiable: true }, { expectedSalaryLpa: { lte: 0 } }] };
}

function matchedSkillsOf(job, profile) {
  const have = new Set(profile?.skillsNormalized || []);
  return (job?.skills || []).filter((s) => have.has(String(s).trim().toLowerCase()));
}

function contactOf(user, profile) {
  return { email: user.email, phone: profile?.phone || user.phone || "" };
}

/**
 * A candidate card as the company sees it. `job` (may be null) is what the
 * score is computed against. `contact` is only passed for candidates this
 * company already right-swiped.
 */
function buildCard(user, rawJob, { wishlisted = false, contact = false } = {}) {
  const profile = user.candidateProfile;
  // The private general job has no skills to score against.
  const job = rawJob && rawJob.status !== GENERAL_STATUS ? rawJob : null;
  let match = null;
  if (profile && job) {
    const { score, reasons } = matchScore(job, profile);
    match = { score, reasons, jobTitle: job.title };
  }
  const card = {
    ...toCandidate(user, profile, match),
    matchedSkills: profile && job ? matchedSkillsOf(job, profile) : [],
    wishlisted,
  };
  if (contact) card.contact = contactOf(user, profile);
  return card;
}

/** Candidate ids this company already right-swiped (any job), and wishlisted ones. */
async function relationsFor(recruiterId, candidateIds) {
  if (!candidateIds.length) return { shortlisted: new Set(), wishlisted: new Set() };
  const [swipes, wishes] = await Promise.all([
    prisma.candidateSwipe.findMany({
      where: { recruiterId, candidateId: { in: candidateIds }, action: "right" },
      select: { candidateId: true },
    }),
    prisma.wishlistEntry.findMany({ where: { recruiterId, candidateId: { in: candidateIds } }, select: { candidateId: true } }),
  ]);
  return {
    shortlisted: new Set(swipes.map((s) => s.candidateId)),
    wishlisted: new Set(wishes.map((w) => w.candidateId)),
  };
}

/** A live candidate: finished profile and open to work. */
function isLive(user) {
  return Boolean(user && user.role === "candidate" && user.profileComplete && user.candidateProfile && user.candidateProfile.openToWork !== false);
}

/** The job a request without a jobId means: the oldest open one, else the oldest of any status. */
async function defaultJob(recruiterId) {
  const open = await prisma.jobPosting.findFirst({ where: { recruiterId, isOpen: true }, orderBy: [{ createdAt: "asc" }, { id: "asc" }] });
  if (open) return open;
  return prisma.jobPosting.findFirst({ where: { recruiterId }, orderBy: [{ createdAt: "asc" }, { id: "asc" }] });
}

/**
 * What a card's match % is scored against when the recruiter has no job: the
 * filters themselves (skills asked for, minimum experience, city, salary range).
 * Null when none of those is set, so there is nothing to score.
 */
function scoringJobFromFilters(filters) {
  const skills = filters.skills || [];
  if (!skills.length && filters.minExp == null && !filters.location && filters.maxSalary == null) return null;
  return {
    title: filters.role || "Your filters",
    skills,
    skillsNormalized: normalizeSkills(skills),
    minExperienceYears: filters.minExp ?? 0,
    location: filters.location || "",
    salaryMinLpa: filters.minSalary ?? 0,
    salaryMaxLpa: filters.maxSalary ?? 0,
  };
}

/**
 * How well a candidate fits ALL the filters, 0-100, with the reasons. Every
 * candidate the deck returns already passes the filters, so what separates
 * them is how fully they fit: every asked-for skill, the exact title, living
 * in the city (not just willing to move), an expectation inside the salary
 * range (not just "negotiable"), every chosen work mode / job type...
 * Only the filters that are set count.
 */
function filterMatch(filters, profile) {
  const f = cleanFilters(filters);
  const parts = []; // { weight, fit 0-1, reason }
  const add = (weight, fit, reason) => parts.push({ weight, fit, reason });
  const lower = (v) => String(v || "").toLowerCase();

  if (f.skills.length) {
    const want = normalizeSkills(f.skills);
    const have = new Set(profile.skillsNormalized || []);
    const matched = want.filter((s) => have.has(s)).length;
    add(3, want.length ? matched / want.length : 1, `${matched} of ${want.length} skills match`);
  }
  if (f.role) {
    const needle = lower(f.role);
    const titles = [profile.desiredRole, profile.currentPost].map(lower);
    const exact = titles.some((t) => t === needle);
    add(2, exact ? 1 : titles.some((t) => t.includes(needle)) ? 0.8 : 0, exact ? "job title matches" : "similar job title");
  }
  if (f.location) {
    const needle = lower(f.location);
    const lives = lower(profile.location).includes(needle);
    add(2, lives ? 1 : 0.6, lives ? "lives in the city" : "open to the city");
  }
  const years = Number(profile.experienceYears) || 0;
  if (f.minExp !== null || f.maxExp !== null) {
    const lo = f.minExp ?? 0;
    const hi = f.maxExp ?? Infinity;
    const inside = years >= lo && years <= hi;
    // Only a minimum was asked for: far above it fits a little less.
    const over = f.maxExp === null && years > lo + 3 ? Math.min(0.3, (years - lo - 3) / 20) : 0;
    add(1.5, inside ? 1 - over : 0, "experience fits");
  }
  if (f.minSalary !== null || f.maxSalary !== null) {
    const expected = Number(profile.expectedSalaryLpa) || 0;
    const inside = expected >= (f.minSalary ?? 0) && expected <= (f.maxSalary ?? Infinity);
    add(1.5, inside ? 1 : profile.salaryNegotiable ? 0.8 : 0, inside ? "expectation within range" : "salary negotiable");
  }
  if (f.workModes.length) {
    const offered = f.workModes.filter((m) => (profile.workModes || []).includes(m)).length;
    add(1, offered / f.workModes.length, "work mode fits");
  }
  if (f.jobTypes.length) {
    const offered = f.jobTypes.filter((t) => (profile.jobTypes || []).includes(t)).length;
    add(1, offered / f.jobTypes.length, "job type fits");
  }
  if (f.notice.length) add(1, f.notice.includes(profile.noticeDays) ? 1 : 0, "notice period fits");
  if (f.qualifications.length) {
    add(1, f.qualifications.some((q) => lower(q) === lower(profile.qualification)) ? 1 : 0, "education level fits");
  }
  if (f.education) {
    const needle = lower(f.education);
    add(1, lower(profile.degree).includes(needle) ? 1 : lower(profile.college).includes(needle) ? 0.9 : 0, "degree / college fits");
  }

  const total = parts.reduce((sum, p) => sum + p.weight, 0);
  if (!total) return null;
  const score = Math.round((parts.reduce((sum, p) => sum + p.weight * p.fit, 0) / total) * 100);
  return { score: Math.max(0, Math.min(100, score)), reasons: parts.filter((p) => p.fit >= 0.8).map((p) => p.reason) };
}

/** The recruiter's private general job, created the first time it is needed. */
async function generalJob(recruiterId) {
  const existing = await prisma.jobPosting.findFirst({
    where: { recruiterId, status: GENERAL_STATUS },
    orderBy: [{ createdAt: "asc" }, { id: "asc" }],
  });
  if (existing) return existing;
  return prisma.jobPosting.create({
    data: { recruiterId, title: "General hiring", status: GENERAL_STATUS, isOpen: false, openings: 1 },
  });
}

module.exports = {
  csv,
  optionalNumber,
  filtersFromQuery,
  cleanFilters,
  hasAnyFilter,
  filterConditions,
  filtersMatch,
  salaryFits,
  salaryFitCondition,
  matchedSkillsOf,
  contactOf,
  buildCard,
  relationsFor,
  isLive,
  defaultJob,
  generalJob,
  scoringJobFromFilters,
  filterMatch,
  GENERAL_STATUS,
  GENERAL_JOB_ID,
  WORK_MODES,
  JOB_TYPES,
  QUALIFICATIONS,
  MAX_SKILL_FILTERS,
};
