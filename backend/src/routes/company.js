const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify } = require("../lib/notify");
const { automaticVerification, normalizeWebsite } = require("../lib/company");
const { str, requireRole } = require("../lib/validate");
const { toCompany, toJobPosting, POSTING_INCLUDE } = require("../lib/serializers");

const router = express.Router();
router.use(requireAuth);

// GET /company/me (recruiter) -> { company | null, suggestedName }
router.get("/me", requireRole("recruiter"), async (req, res) => {
  const company = await prisma.company.findUnique({ where: { ownerId: req.user.id } });
  res.json({ company: company ? toCompany(company) : null, suggestedName: req.user.company });
});

// PUT /company/me { name, website, about, industry, size, location, logoUrl }
// A website on the same domain as the recruiter's own email (not a free mail
// provider) verifies the company automatically.
router.put("/me", requireRole("recruiter"), async (req, res) => {
  const b = req.body || {};
  const name = str(b.name, 150);
  if (name.length < 2) return res.status(400).json({ error: "Enter the company name." });

  const website = normalizeWebsite(b.website);
  if (str(b.website, 300) && !website) {
    return res.status(400).json({ error: "That website address doesn't look right." });
  }
  const logoUrl = str(b.logoUrl, 1000);
  if (logoUrl && !/^https:\/\//i.test(logoUrl)) {
    return res.status(400).json({ error: "The logo must be an https link." });
  }

  const existing = await prisma.company.findUnique({ where: { ownerId: req.user.id } });
  const automatic = automaticVerification({ website, ownerEmail: req.user.email });

  // A manual approval sticks; otherwise the status follows the website.
  let status = automatic;
  let note = existing?.verificationNote ?? "";
  if (existing?.verificationStatus === "verified" && note === "manual") status = "verified";
  else if (automatic !== "verified" && existing?.verificationStatus === "pending") status = "pending";
  if (status === "verified" && note !== "manual") note = "domain";

  const data = {
    name,
    website,
    about: str(b.about, 2000),
    industry: str(b.industry, 100),
    size: str(b.size, 50),
    location: str(b.location, 150),
    logoUrl,
    verificationStatus: status,
    verificationNote: status === "verified" ? note : existing?.verificationNote === "manual" ? "" : note,
    verifiedAt: status === "verified" ? existing?.verifiedAt ?? new Date() : null,
  };
  const company = await prisma.company.upsert({
    where: { ownerId: req.user.id },
    create: { ownerId: req.user.id, ...data },
    update: data,
  });
  // The company name shown across the app comes from the account too.
  if (req.user.company !== name) {
    await prisma.user.update({ where: { id: req.user.id }, data: { company: name } });
  }
  res.json({ company: toCompany(company) });
});

// POST /company/me/verification-request { note } -- asks for a manual review
// when the website domain can't be matched to the recruiter's email.
router.post("/me/verification-request", requireRole("recruiter"), async (req, res) => {
  const company = await prisma.company.findUnique({ where: { ownerId: req.user.id } });
  if (!company) return res.status(409).json({ error: "Save your company details first." });
  if (company.verificationStatus === "verified") return res.json({ company: toCompany(company) });

  const updated = await prisma.company.update({
    where: { id: company.id },
    data: { verificationStatus: "pending", verificationNote: str(req.body?.note, 500) },
  });
  console.log(`[company] verification requested for "${company.name}" (${company.id}) by ${req.user.email}`);
  await notify(req.user.id, {
    title: "Verification requested",
    body: `We received your request to verify ${company.name}. We'll update the badge once it's reviewed.`,
    type: "company",
  });
  res.json({ company: toCompany(updated) });
});

// GET /company/:id -- the public company page (any signed-in account).
router.get("/:id", async (req, res) => {
  const company = await prisma.company.findUnique({ where: { id: req.params.id } });
  if (!company) return res.status(404).json({ error: "Company not found." });
  const openJobs = await prisma.jobPosting.findMany({
    where: { recruiterId: company.ownerId, isOpen: true },
    orderBy: { createdAt: "desc" },
    take: 20,
    include: POSTING_INCLUDE,
  });
  res.json({ company: toCompany(company), jobs: openJobs.map((j) => toJobPosting(j)) });
});

module.exports = router;
