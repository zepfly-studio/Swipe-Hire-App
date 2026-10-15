// The company's hiring side, mounted under /company: swiping (and its swipe
// credits), undo, wishlist, the shortlisted pipeline and saved searches.
// Plans/payments live in payment.js; the deck itself is GET /candidates.

const express = require("express");
const { Prisma } = require("@prisma/client");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify, inBackground } = require("../lib/notify");
const { str, bool, requireRole } = require("../lib/validate");
const { ensureCompany, spendSwipe, refundSwipe, balanceOf } = require("../lib/credits");
const { buildCard, relationsFor, isLive, defaultJob, salaryFits, contactOf, cleanFilters, hasAnyFilter } = require("../lib/deck");
const { MAX_SEARCHES, toSearch, liveCandidateIdsMatching } = require("../lib/savedSearches");

const router = express.Router();
router.use(requireAuth, requireRole("recruiter"));

const UNDO_WINDOW_MS = 10 * 60 * 1000;
const STAGES = ["shortlisted", "contacted", "task", "interview", "hired", "rejected"];
const CANDIDATE_INCLUDE = { candidateProfile: true };

class NoSwipes extends Error {}

function firstName(name) {
  return String(name || "").trim().split(/\s+/)[0] || "This candidate";
}

function lpaText(value) {
  return String(Math.round(Number(value) * 100) / 100);
}

// The in-app row is written before the response (so an undo can find it);
// the push and email go out in the background.
async function tell(userId, event) {
  const { title, body = "", type, link = "", email = false } = event;
  const row = await prisma.notification.create({ data: { userId, type, title, body, link } });
  inBackground(notify(userId, { title, body, type, link, email, inbox: false }));
  return row;
}

async function companyNameFor(user) {
  const company = await prisma.company.findUnique({ where: { ownerId: user.id }, select: { name: true } });
  return company?.name || user.company || "A company";
}

// --- swipe -----------------------------------------------------------------

// POST /company/swipe { candidateId, action: left|right, jobId? }
// -> { swipesLeft, contact? }. Costs one swipe, left or right.
router.post("/swipe", async (req, res) => {
  const candidateId = str(req.body?.candidateId, 100);
  const action = req.body?.action;
  const jobId = str(req.body?.jobId, 100);
  if (!candidateId) return res.status(400).json({ error: "Invalid candidate" });
  if (action !== "left" && action !== "right") return res.status(400).json({ error: "Invalid swipe" });

  const company = await ensureCompany(req.user);
  const job = jobId
    ? await prisma.jobPosting.findFirst({ where: { id: jobId, recruiterId: req.user.id } })
    : await defaultJob(req.user.id);
  if (!job) {
    return jobId
      ? res.status(404).json({ error: "Job not found." })
      : res.status(403).json({ code: "NO_JOB", error: "Please add a job you are hiring for first" });
  }
  if (company.swipesLeft <= 0) {
    return res.status(402).json({ code: "NO_SWIPES", error: "You have used all your swipes. Buy a plan to keep swiping." });
  }

  const candidate = await prisma.user.findFirst({
    where: { id: candidateId, role: "candidate" },
    include: CANDIDATE_INCLUDE,
  });
  if (!isLive(candidate)) return res.status(404).json({ error: "Candidate not found" });

  const profile = candidate.candidateProfile;
  if (action === "right" && !salaryFits(job, profile)) {
    return res.status(409).json({
      code: "SALARY_MISMATCH",
      error: `${firstName(candidate.name)} expects at least ₹${lpaText(profile.expectedSalaryLpa)} LPA, above this job's budget of ₹${lpaText(job.salaryMaxLpa)} LPA, and is not open to negotiate.`,
    });
  }

  const duplicate = () => res.status(409).json({ error: "You have already swiped this candidate for this job" });
  const key = { recruiterId_candidateId_jobPostingId: { recruiterId: req.user.id, candidateId, jobPostingId: job.id } };
  if (await prisma.candidateSwipe.findUnique({ where: key, select: { id: true } })) return duplicate();

  // Credit and swipe row commit together or not at all, so a duplicate (lost
  // race) or any failure leaves the balance untouched.
  let swipesLeft;
  try {
    swipesLeft = await prisma.$transaction(async (tx) => {
      const left = await spendSwipe(tx, req.user.id);
      if (left === null) throw new NoSwipes();
      await tx.candidateSwipe.create({
        data: { recruiterId: req.user.id, candidateId, jobPostingId: job.id, action },
      });
      return left;
    });
  } catch (err) {
    if (err instanceof NoSwipes) {
      return res.status(402).json({ code: "NO_SWIPES", error: "You have used all your swipes. Buy a plan to keep swiping." });
    }
    if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") return duplicate();
    throw err;
  }

  if (action === "left") return res.json({ swipesLeft });

  await tell(candidateId, {
    type: "shortlisted",
    title: "A company shortlisted you!",
    body: "A company is interested in your profile. Keep your profile active to hear from them.",
    link: "/candidate",
    email: true,
  });
  res.json({ swipesLeft, contact: contactOf(candidate, profile) });
});

// POST /company/swipe/undo -> { swipesLeft, action, jobId, card }
router.post("/swipe/undo", async (req, res) => {
  await ensureCompany(req.user);
  const swipe = await prisma.candidateSwipe.findFirst({
    where: { recruiterId: req.user.id, createdAt: { gte: new Date(Date.now() - UNDO_WINDOW_MS) } },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    include: { candidate: { include: CANDIDATE_INCLUDE }, jobPosting: true },
  });
  if (!swipe) return res.status(404).json({ error: "There is no recent swipe to undo" });

  const contacted = () => res.status(409).json({ error: "You have already contacted this candidate, so this swipe cannot be undone" });

  if (swipe.action === "right") {
    if (swipe.stage !== "shortlisted") return contacted();
    const pair = { companyId: req.user.id, candidateId: swipe.candidateId, createdAt: { gte: swipe.createdAt } };
    const [messages, interviews, tasks] = await Promise.all([
      prisma.chatMessage.count({ where: { ...pair, senderId: req.user.id } }),
      prisma.interview.count({ where: pair }),
      prisma.hiringTask.count({ where: pair }),
    ]);
    if (messages + interviews + tasks > 0) return contacted();
  }

  let swipesLeft;
  try {
    swipesLeft = await prisma.$transaction(async (tx) => {
      // Guarded delete: if the stage moved (or it is already gone) in the
      // meantime, nothing is removed and nothing is refunded.
      const removed = await tx.candidateSwipe.deleteMany({
        where: { id: swipe.id, ...(swipe.action === "right" ? { stage: "shortlisted" } : {}) },
      });
      if (removed.count !== 1) throw new NoSwipes();
      return swipe.action === "left" ? refundSwipe(tx, req.user.id) : balanceOf(tx, req.user.id);
    });
  } catch (err) {
    if (err instanceof NoSwipes) return contacted();
    throw err;
  }

  if (swipe.action === "right") {
    const notification = await prisma.notification.findFirst({
      where: { userId: swipe.candidateId, type: "shortlisted", createdAt: { gte: new Date(swipe.createdAt.getTime() - 2000) } },
      orderBy: { createdAt: "asc" },
      select: { id: true },
    });
    if (notification) await prisma.notification.deleteMany({ where: { id: notification.id } });
  }

  const rel = await relationsFor(req.user.id, [swipe.candidateId]);
  const card = buildCard(swipe.candidate, swipe.jobPosting, {
    wishlisted: rel.wishlisted.has(swipe.candidateId),
    contact: rel.shortlisted.has(swipe.candidateId),
  });
  res.json({ swipesLeft, action: swipe.action, jobId: swipe.jobPostingId, card });
});

// --- wishlist --------------------------------------------------------------

// PUT /company/wishlist/:candidateId { wishlisted } -> { wishlisted }
router.put("/wishlist/:candidateId", async (req, res) => {
  const wishlisted = req.body?.wishlisted;
  if (typeof wishlisted !== "boolean") return res.status(400).json({ error: "Invalid request" });
  const candidateId = req.params.candidateId;

  if (!wishlisted) {
    await prisma.wishlistEntry.deleteMany({ where: { recruiterId: req.user.id, candidateId } });
    return res.json({ wishlisted: false });
  }
  const candidate = await prisma.user.findFirst({ where: { id: candidateId, role: "candidate" }, include: CANDIDATE_INCLUDE });
  if (!isLive(candidate)) return res.status(404).json({ error: "Candidate not found" });
  await prisma.wishlistEntry.upsert({
    where: { recruiterId_candidateId: { recruiterId: req.user.id, candidateId } },
    create: { recruiterId: req.user.id, candidateId },
    update: {},
  });
  res.json({ wishlisted: true });
});

// GET /company/wishlist -> { candidates: [Card] }, newest first, scored
// against the oldest open job.
router.get("/wishlist", async (req, res) => {
  const entries = await prisma.wishlistEntry.findMany({
    where: { recruiterId: req.user.id },
    orderBy: [{ createdAt: "desc" }, { candidateId: "asc" }],
    include: { candidate: { include: CANDIDATE_INCLUDE } },
  });
  const job = await prisma.jobPosting.findFirst({
    where: { recruiterId: req.user.id, isOpen: true },
    orderBy: [{ createdAt: "asc" }, { id: "asc" }],
  });
  const live = entries.filter((e) => isLive(e.candidate));
  const rel = await relationsFor(req.user.id, live.map((e) => e.candidateId));
  res.json({
    candidates: live.map((e) => buildCard(e.candidate, job, { wishlisted: true, contact: rel.shortlisted.has(e.candidateId) })),
  });
});

// --- shortlisted pipeline --------------------------------------------------

// GET /company/shortlisted?jobId= -> { candidates: [ShortlistRow] }
router.get("/shortlisted", async (req, res) => {
  const jobId = str(req.query.jobId, 100);
  const swipes = await prisma.candidateSwipe.findMany({
    where: { recruiterId: req.user.id, action: "right", ...(jobId ? { jobPostingId: jobId } : {}) },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    include: { candidate: { include: CANDIDATE_INCLUDE }, jobPosting: true },
  });
  const rel = await relationsFor(req.user.id, [...new Set(swipes.map((s) => s.candidateId))]);
  res.json({
    candidates: swipes.map((s) => ({
      ...buildCard(s.candidate, s.jobPosting, { wishlisted: rel.wishlisted.has(s.candidateId), contact: true }),
      swipeId: s.id,
      jobId: s.jobPostingId,
      job: { id: s.jobPostingId, title: s.jobPosting.title },
      stage: s.stage,
      notes: s.notes,
      shortlistedAt: s.createdAt.toISOString(),
    })),
  });
});

// PATCH /company/pipeline/:swipeId { stage?, notes? } -> { ok, stage?, notes? }
router.patch("/pipeline/:swipeId", async (req, res) => {
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const hasStage = body.stage !== undefined;
  const hasNotes = body.notes !== undefined;
  if (!hasStage && !hasNotes) return res.status(400).json({ error: "Invalid request" });
  if (hasStage && !STAGES.includes(body.stage)) return res.status(400).json({ error: "Invalid stage", field: "stage" });
  if (hasNotes && (typeof body.notes !== "string" || body.notes.length > 2000)) {
    return res.status(400).json({ error: "Notes can be up to 2000 characters.", field: "notes" });
  }

  const swipe = await prisma.candidateSwipe.findFirst({
    where: { id: req.params.swipeId, recruiterId: req.user.id, action: "right" },
    include: { jobPosting: { select: { title: true } } },
  });
  if (!swipe) return res.status(404).json({ error: "This candidate is not in your pipeline" });

  let moved = false;
  if (hasStage) {
    const result = await prisma.candidateSwipe.updateMany({
      where: { id: swipe.id, stage: { not: body.stage } },
      data: { stage: body.stage, ...(hasNotes ? { notes: body.notes.trim() } : {}) },
    });
    moved = result.count === 1;
    if (!moved && hasNotes) {
      await prisma.candidateSwipe.updateMany({ where: { id: swipe.id }, data: { notes: body.notes.trim() } });
    }
  } else {
    await prisma.candidateSwipe.updateMany({ where: { id: swipe.id }, data: { notes: body.notes.trim() } });
  }

  if (moved && body.stage === "hired") {
    const name = await companyNameFor(req.user);
    await tell(swipe.candidateId, {
      type: "hired",
      title: `Congratulations! ${name} selected you 🎉`,
      body: `${name} has selected you for ${swipe.jobPosting.title}.`,
      link: `/messages?with=${req.user.id}`,
      email: true,
    });
  }

  res.json({ ok: true, ...(hasStage ? { stage: body.stage } : {}), ...(hasNotes ? { notes: body.notes.trim() } : {}) });
});

// --- saved searches --------------------------------------------------------

router.get("/searches", async (req, res) => {
  const rows = await prisma.savedSearch.findMany({ where: { recruiterId: req.user.id }, orderBy: { createdAt: "desc" } });
  res.json({ searches: rows.map(toSearch) });
});

// POST /company/searches { name, filters, alerts? } -> 201 { search }
router.post("/searches", async (req, res) => {
  const name = str(req.body?.name, 60);
  if (!name) return res.status(400).json({ error: "Give this search a name", field: "name" });
  const filters = cleanFilters(req.body?.filters);
  if (!hasAnyFilter(filters)) {
    return res.status(400).json({ error: "Set at least one filter before saving the search", field: "filters" });
  }
  const count = await prisma.savedSearch.count({ where: { recruiterId: req.user.id } });
  if (count >= MAX_SEARCHES) {
    return res.status(400).json({ error: `You can save up to ${MAX_SEARCHES} searches. Delete one first.` });
  }
  // Candidates who already match are pre-marked so they never trigger an alert.
  const already = await liveCandidateIdsMatching(filters);
  const row = await prisma.savedSearch.create({
    data: {
      recruiterId: req.user.id,
      name,
      filters,
      alerts: bool(req.body?.alerts, true),
      notifiedCandidates: already,
    },
  });
  res.status(201).json({ search: toSearch(row) });
});

// PATCH /company/searches/:id { alerts?, name? } -> { search }. Filters are fixed.
router.patch("/searches/:id", async (req, res) => {
  const data = {};
  if (typeof req.body?.alerts === "boolean") data.alerts = req.body.alerts;
  if (req.body?.name !== undefined) {
    const name = str(req.body.name, 60);
    if (!name) return res.status(400).json({ error: "Give this search a name", field: "name" });
    data.name = name;
  }
  const result = await prisma.savedSearch.updateMany({ where: { id: req.params.id, recruiterId: req.user.id }, data });
  if (result.count === 0) return res.status(404).json({ error: "Saved search not found" });
  const row = await prisma.savedSearch.findUnique({ where: { id: req.params.id } });
  res.json({ search: toSearch(row) });
});

router.delete("/searches/:id", async (req, res) => {
  await prisma.savedSearch.deleteMany({ where: { id: req.params.id, recruiterId: req.user.id } });
  res.json({ ok: true });
});

module.exports = router;
