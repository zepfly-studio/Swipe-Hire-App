const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { requireRole } = require("../lib/validate");
const { toCandidate } = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth, requireRole("recruiter"));

const STATES = ["wishlist", "shortlist", "rejected"];

// GET /swipes -- the recruiter's whole funnel, so it's identical on every
// device: wishlist + shortlist as full candidate cards, rejected as ids.
router.get("/", async (req, res) => {
  const swipes = await prisma.swipe.findMany({
    where: { recruiterId: req.user.id },
    orderBy: { updatedAt: "desc" },
    include: { candidate: { include: { candidateProfile: true } } },
  });
  const cards = (state) =>
    swipes.filter((s) => s.state === state).map((s) => toCandidate(s.candidate, s.candidate.candidateProfile));
  res.json({
    wishlist: cards("wishlist"),
    shortlist: cards("shortlist"),
    rejectedIds: swipes.filter((s) => s.state === "rejected").map((s) => s.candidateId),
  });
});

// PUT /swipes/:candidateId { state }
router.put("/:candidateId", async (req, res) => {
  const state = req.body?.state;
  if (!STATES.includes(state)) return res.status(400).json({ error: "state must be wishlist, shortlist or rejected." });
  const candidate = await prisma.user.findFirst({ where: { id: req.params.candidateId, role: "candidate" } });
  if (!candidate) return res.status(404).json({ error: "Candidate not found." });

  await prisma.swipe.upsert({
    where: { recruiterId_candidateId: { recruiterId: req.user.id, candidateId: candidate.id } },
    create: { recruiterId: req.user.id, candidateId: candidate.id, state },
    update: { state },
  });
  res.json({ state });
});

// DELETE /swipes/:candidateId -- undo: the candidate becomes unseen again.
router.delete("/:candidateId", async (req, res) => {
  await prisma.swipe.deleteMany({ where: { recruiterId: req.user.id, candidateId: req.params.candidateId } });
  res.json({ removed: true });
});

module.exports = router;
