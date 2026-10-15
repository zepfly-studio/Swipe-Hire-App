// Builders for the pair-feature tests (chat / interviews / tasks). They write
// straight through Prisma so these tests don't depend on the signup flow or
// on the company / swipe routes. Every account uses h.emailFor(), so
// h.stop() removes them (and their cascaded rows) afterwards.

const jwt = require("jsonwebtoken");
const h = require("./helpers");

const { prisma } = h;

function tokenFor(user) {
  return jwt.sign({ sub: user.id, role: user.role }, process.env.JWT_SECRET, { expiresIn: "1d" });
}

/** A recruiter with a Company row. Returns { id, token, name, company, user }. */
async function createRecruiter(name = "Rhea Recruiter", { company = "PairCorp", verified = false, industry = "Software", logoUrl = "" } = {}) {
  const user = await prisma.user.create({
    data: {
      name,
      email: h.emailFor("recruiter"),
      passwordHash: "x",
      role: "recruiter",
      company,
      profileComplete: true,
      emailVerified: true,
    },
  });
  await prisma.company.create({
    data: {
      ownerId: user.id,
      name: company,
      industry,
      logoUrl,
      verificationStatus: verified ? "verified" : "unverified",
    },
  });
  return { id: user.id, token: tokenFor(user), name, company, user };
}

/** A candidate with a profile card. Returns { id, token, name, user }. */
async function createCandidate(name = "Cara Candidate", { desiredRole = "Flutter Developer", photoUrl = "" } = {}) {
  const user = await prisma.user.create({
    data: {
      name,
      email: h.emailFor("candidate"),
      passwordHash: "x",
      role: "candidate",
      profileComplete: true,
      emailVerified: true,
      candidateProfile: { create: { desiredRole, photoUrl, location: "Pune", skills: ["Flutter"], skillsNormalized: ["flutter"] } },
    },
  });
  return { id: user.id, token: tokenFor(user), name, user };
}

async function createJob(recruiter, title = "Flutter Developer") {
  return prisma.jobPosting.create({
    data: { recruiterId: recruiter.id, title, description: "Build apps", skills: ["Flutter"], salaryMaxLpa: 15, status: "open", isOpen: true },
  });
}

/** One CandidateSwipe row (right by default), the way the company swipe route would leave it. */
async function createSwipe(recruiter, candidate, job, { action = "right", stage = "shortlisted" } = {}) {
  return prisma.candidateSwipe.create({
    data: { recruiterId: recruiter.id, candidateId: candidate.id, jobPostingId: job.id, action, stage },
  });
}

/** Recruiter + candidate + job + right swipe, in one go. */
async function shortlistedPair({ recruiterName, candidateName, jobTitle, stage } = {}) {
  const recruiter = await createRecruiter(recruiterName);
  const candidate = await createCandidate(candidateName);
  const job = await createJob(recruiter, jobTitle);
  const swipe = await createSwipe(recruiter, candidate, job, { stage });
  return { recruiter, candidate, job, swipe };
}

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;
const inFuture = (ms) => new Date(Date.now() + ms).toISOString();

module.exports = {
  ...h,
  tokenFor,
  createRecruiter,
  createCandidate,
  createJob,
  createSwipe,
  shortlistedPair,
  MINUTE,
  HOUR,
  DAY,
  inFuture,
};
