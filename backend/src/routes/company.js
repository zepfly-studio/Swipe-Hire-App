const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { notify } = require("../lib/notify");
const { automaticVerification, normalizeWebsite } = require("../lib/company");
const { str, strList, requireRole } = require("../lib/validate");
const { normalizeSkills } = require("../lib/derive");
const { FieldError } = require("../lib/candidateProfile");
const { toCompany, toJobPosting, POSTING_INCLUDE } = require("../lib/serializers");
const verification = require("../lib/companyVerification");
const { Prisma } = require("@prisma/client");

const router = express.Router();
router.use(requireAuth);

const PHONE_RE = /^\+?[\d\s-]{8,16}$/;
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const WORK_MODES = ["onsite", "hybrid", "remote"];
const JOB_TYPES = ["full-time", "part-time", "internship", "contract"];

function has(body, key) {
  return body[key] !== undefined && body[key] !== null;
}

// Validates the company fields that are present in `b`. `prefix` is added to
// field names in errors (`company.` inside the onboarding body).
// Returns a partial Prisma data object (absent fields are left alone).
function parseCompanyFields(b, prefix = "") {
  const body = b && typeof b === "object" ? b : {};
  const field = (name) => `${prefix}${name}`;
  const data = {};

  if (has(body, "name")) {
    const name = str(body.name, 150);
    if (name.length < 2) throw new FieldError(field("name"), "Enter the company name.");
    data.name = name;
  }
  if (has(body, "website")) {
    const raw = str(body.website, 300);
    const website = normalizeWebsite(raw);
    if (raw && !website) throw new FieldError(field("website"), "That website address doesn't look right.");
    data.website = website;
  }
  if (has(body, "about")) data.about = str(body.about, 2000);
  if (has(body, "industry")) data.industry = str(body.industry, 100);
  if (has(body, "size")) data.size = str(body.size, 50);
  if (has(body, "location")) data.location = str(body.location, 150);
  if (has(body, "logoUrl")) {
    const logoUrl = str(body.logoUrl, 1000);
    if (logoUrl && !/^https:\/\//i.test(logoUrl)) throw new FieldError(field("logoUrl"), "The logo must be an https link.");
    data.logoUrl = logoUrl;
  }
  if (has(body, "address")) data.address = str(body.address, 200);
  if (has(body, "phone")) {
    const phone = str(body.phone, 20);
    if (phone && !PHONE_RE.test(phone)) throw new FieldError(field("phone"), "Please enter a valid phone number");
    data.phone = phone;
  }
  if (has(body, "contactEmail")) {
    const email = str(body.contactEmail, 120).toLowerCase();
    if (email && !EMAIL_RE.test(email)) throw new FieldError(field("contactEmail"), "Please enter a valid email address");
    data.contactEmail = email;
  }
  if (has(body, "linkedin")) {
    const raw = str(body.linkedin, 300);
    const linkedin = normalizeWebsite(raw);
    if (raw && !linkedin) throw new FieldError(field("linkedin"), "That LinkedIn address doesn't look right.");
    data.linkedin = linkedin;
  }
  if (has(body, "foundedYear")) {
    if (body.foundedYear === "") {
      data.foundedYear = null;
    } else {
      const year = Number(body.foundedYear);
      if (!Number.isInteger(year) || year < 1800 || year > new Date().getFullYear()) {
        throw new FieldError(field("foundedYear"), "Please enter a valid founding year");
      }
      data.foundedYear = year;
    }
  } else if (body.foundedYear === null) {
    data.foundedYear = null;
  }
  return data;
}

// Verification status after a save by the OWNER. Renaming the company or
// changing its website resets verified/pending/rejected to unverified; after
// that (or on a new company) the domain check can verify it straight away.
// Otherwise the status is left alone: a manual/GST approval sticks, a pending
// request stays pending, a rejection stays rejected.
// `next` is the name and website the company has after this save.
function verificationData(existing, next, ownerEmail) {
  const automatic = automaticVerification({ website: next.website, ownerEmail });
  const changed = Boolean(existing) && (existing.name !== next.name || (existing.website || "") !== (next.website || ""));
  const base = existing && !changed ? existing : null;

  let status = base?.verificationStatus || "unverified";
  let method = base?.verificationMethod ?? "";
  let note = base?.verificationNote ?? "";
  if (status !== "verified" && automatic === "verified") {
    status = "verified";
    method = "email";
    note = "domain";
  }
  const data = {
    verificationStatus: status,
    verificationMethod: status === "unverified" ? "" : method,
    verificationNote: status === "unverified" ? "" : note,
    verifiedAt: status === "verified" ? base?.verifiedAt ?? new Date() : null,
  };
  // A code emailed for the old name/website is no longer valid.
  if (changed) data.verificationOtp = Prisma.DbNull;
  return data;
}

const OWNER_ONLY = "Only the account owner can change the company name or website";

function sendFieldError(res, err) {
  return res.status(400).json({ error: err.message, field: err.field });
}

// GET /company/me (recruiter) -> { company | null, suggestedName }
router.get("/me", requireRole("recruiter"), async (req, res) => {
  const company = await prisma.company.findUnique({ where: { ownerId: req.user.companyId } });
  res.json({ company: company ? toCompany(company, { own: true }) : null, suggestedName: req.user.company });
});

// PUT /company/me { name, website, about, industry, size, location, logoUrl,
//                   address, phone, contactEmail, linkedin, foundedYear }
// Only the fields sent are changed; `name` (>= 2 chars) is required when the
// company does not exist yet. A website on the same domain as the recruiter's
// own email (not a free mail provider) verifies the company automatically.
router.put("/me", requireRole("recruiter"), async (req, res) => {
  let fields;
  try {
    fields = parseCompanyFields(req.body);
  } catch (err) {
    if (err instanceof FieldError) return sendFieldError(res, err);
    throw err;
  }

  const companyId = req.user.companyId;
  const existing = await prisma.company.findUnique({ where: { ownerId: companyId } });

  // Team members edit the shared profile, except the identity of the company.
  if (!req.user.isOwner) {
    if (!existing) return res.status(409).json({ error: "The account owner has not set up the company yet." });
    const renamed = fields.name !== undefined && fields.name !== existing.name;
    const rewebbed = fields.website !== undefined && fields.website !== (existing.website || "");
    if (renamed || rewebbed) return res.status(403).json({ error: OWNER_ONLY });
    const company = await prisma.company.update({ where: { id: existing.id }, data: fields });
    return res.json({ company: toCompany(company, { own: true }) });
  }

  if (!existing && !fields.name) return res.status(400).json({ error: "Enter the company name.", field: "name" });

  const name = fields.name ?? existing?.name ?? req.user.company ?? req.user.name;
  const website = fields.website !== undefined ? fields.website : existing?.website ?? "";
  const data = { ...fields, ...verificationData(existing, { name, website }, req.user.email) };
  const company = await prisma.company.upsert({
    where: { ownerId: companyId },
    create: { ownerId: companyId, ...data, name },
    update: data,
  });
  // The company name shown across the app comes from the account too (the
  // owner's and every teammate's).
  if (fields.name && req.user.company !== fields.name) {
    await prisma.user.updateMany({
      where: { OR: [{ id: companyId }, { companyOwnerId: companyId }] },
      data: { company: fields.name },
    });
  }
  res.json({ company: toCompany(company, { own: true }) });
});

// POST /company/onboarding { company: {...}, job: {...} } -> { company, job }
// The two-step onboarding in one call: saves the company (new ones start with
// the free swipes), creates the first job when the recruiter has none, and
// marks the account complete.
router.post("/onboarding", requireRole("recruiter"), async (req, res) => {
  if (!req.user.isOwner) return res.status(403).json({ error: OWNER_ONLY });
  const companyId = req.user.companyId;
  const body = req.body && typeof req.body === "object" ? req.body : {};
  const c = body.company && typeof body.company === "object" ? body.company : {};
  const j = body.job && typeof body.job === "object" ? body.job : {};

  let fields;
  let jobData;
  try {
    if (str(c.name, 150).length < 2) throw new FieldError("company.name", "Enter your company name");
    if (!str(c.location, 150)) throw new FieldError("company.location", "Enter your company location");
    fields = parseCompanyFields(c, "company.");

    const title = str(j.title, 200);
    if (!title) throw new FieldError("job.title", "Enter the role you are hiring for");
    const skills = strList(j.skills, 30);
    if (skills.length === 0) throw new FieldError("job.skills", "Add at least one skill");

    const number = (value, name, { min = 0, max, label }) => {
      if (value === undefined || value === null || value === "") return null;
      const n = Number(value);
      if (!Number.isFinite(n) || n < min || n > max) throw new FieldError(name, label);
      return n;
    };
    const minExp = number(j.minExperienceYears, "job.minExperienceYears", { max: 50, label: "Enter years between 0 and 50" });
    const maxExp = number(j.maxExperienceYears, "job.maxExperienceYears", { max: 50, label: "Enter years between 0 and 50" });
    if (minExp !== null && maxExp !== null && minExp > maxExp) {
      throw new FieldError("job.minExperienceYears", "Minimum experience cannot be more than maximum experience");
    }
    const salaryMax = number(j.salaryMaxLpa, "job.salaryMaxLpa", { max: 1000, label: "Enter a valid salary" });
    if (salaryMax === null || salaryMax <= 0) {
      throw new FieldError("job.salaryMaxLpa", "Enter the maximum salary you can offer");
    }
    const salaryMin = number(j.salaryMinLpa, "job.salaryMinLpa", { max: 1000, label: "Enter a valid salary" });
    if (salaryMin !== null && salaryMin > salaryMax) throw new FieldError("job.salaryMinLpa", "Minimum salary cannot be more than maximum salary");

    let workMode = "onsite";
    if (j.workMode !== undefined && j.workMode !== null && j.workMode !== "") {
      workMode = str(j.workMode, 20).toLowerCase().replace(/[\s_-]+/g, "");
      if (!WORK_MODES.includes(workMode)) throw new FieldError("job.workMode", "Choose on-site, hybrid or remote");
    }
    let employmentType = "full-time";
    if (j.employmentType !== undefined && j.employmentType !== null && j.employmentType !== "") {
      employmentType = str(j.employmentType, 30).toLowerCase().replace(/[\s_]+/g, "-");
      if (!JOB_TYPES.includes(employmentType)) throw new FieldError("job.employmentType", "Choose a valid job type");
    }

    jobData = {
      title,
      skills,
      skillsNormalized: normalizeSkills(skills),
      description: str(j.description, 8000),
      // The job location defaults to the company's.
      location: str(j.location, 200) || fields.location,
      employmentType,
      workMode,
      openings: 1,
      salaryMinLpa: salaryMin ?? 0,
      salaryMaxLpa: salaryMax,
      minExperienceYears: minExp ?? 0,
      maxExperienceYears: maxExp,
    };
  } catch (err) {
    if (err instanceof FieldError) return sendFieldError(res, err);
    throw err;
  }

  const result = await prisma.$transaction(async (tx) => {
    const existing = await tx.company.findUnique({ where: { ownerId: companyId } });
    const website = fields.website !== undefined ? fields.website : existing?.website ?? "";
    const data = { ...fields, ...verificationData(existing, { name: fields.name, website }, req.user.email) };
    const company = await tx.company.upsert({
      where: { ownerId: companyId },
      create: { ownerId: companyId, ...data },
      update: data,
    });

    let job = await tx.jobPosting.findFirst({
      where: { recruiterId: companyId },
      orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      include: POSTING_INCLUDE,
    });
    if (!job) {
      job = await tx.jobPosting.create({
        data: { recruiterId: companyId, ...jobData, status: "open", isOpen: true },
        include: POSTING_INCLUDE,
      });
    }
    await tx.user.update({ where: { id: req.user.id }, data: { company: company.name, profileComplete: true } });
    return { company, job };
  });

  // Reload the job with the company name just saved.
  const job = await prisma.jobPosting.findUnique({ where: { id: result.job.id }, include: POSTING_INCLUDE });
  res.json({
    company: toCompany(result.company, { own: true }),
    job: toJobPosting(job, { stats: { swiped: 0, shortlisted: 0, interviewing: 0, hired: 0 } }),
  });
});

// POST /company/me/verification-request { note } -- asks for a manual review
// when the website domain can't be matched to the recruiter's email.
router.post("/me/verification-request", requireRole("recruiter"), async (req, res) => {
  const company = await prisma.company.findUnique({ where: { ownerId: req.user.companyId } });
  if (!company) return res.status(409).json({ error: "Save your company details first." });
  if (company.verificationStatus === "verified") return res.json({ company: toCompany(company, { own: true }) });

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
  res.json({ company: toCompany(updated, { own: true }) });
});

// ---------------------------------------------------------------------------
// Company verification (phase 4). Any recruiter on the team may start it; the
// work-email code goes to the caller's own login email.
// ---------------------------------------------------------------------------

async function ownCompany(req) {
  return prisma.company.findUnique({ where: { ownerId: req.user.companyId } });
}

function sendError(res, error) {
  const body = { error: error.message };
  if (error.field) body.field = error.field;
  return res.status(error.status).json(body);
}

// GET /company/verification -> { verification:{status,method,verifiedAt}, gstin, website, email }
router.get("/verification", requireRole("recruiter"), async (req, res) => {
  const company = await ownCompany(req);
  res.json({
    verification: company
      ? verification.verificationView(company)
      : { status: "none", method: "", verifiedAt: null },
    gstin: company?.gstin ?? "",
    website: company?.website ?? "",
    email: req.user.email,
  });
});

// POST /company/verification/gst { gstin } -> { verification:{status:'pending', method:'gst'} }
router.post("/verification/gst", requireRole("recruiter"), async (req, res) => {
  const gstin = verification.normalizeGstin(req.body?.gstin);
  if (!verification.isValidGstin(gstin)) {
    return res.status(400).json({ error: "Please enter a valid 15-character GSTIN", field: "gstin" });
  }
  const company = await ownCompany(req);
  if (!company) return res.status(409).json({ error: "Save your company details first." });
  if (company.verificationStatus === "verified") {
    return res.status(409).json({ error: verification.MESSAGES.alreadyVerified });
  }
  await verification.requestGst(company, gstin);
  console.log(`[company] GST verification requested for "${company.name}" (${company.id}) by ${req.user.email}`);
  res.json({ verification: { status: "pending", method: "gst" } });
});

// POST /company/verification/email/send -> { sentTo, devCode? }
router.post("/verification/email/send", requireRole("recruiter"), async (req, res) => {
  const company = await ownCompany(req);
  if (!company) return res.status(400).json({ error: verification.MESSAGES.noWebsite });
  const result = await verification.sendEmailCode(company, req.user.email);
  if (result.error) return sendError(res, result.error);
  res.json(result);
});

// POST /company/verification/email/confirm { code } -> { verification:{status:'verified', method:'email', verifiedAt} }
router.post("/verification/email/confirm", requireRole("recruiter"), async (req, res) => {
  const before = await ownCompany(req);
  if (!before) return res.status(400).json({ error: verification.MESSAGES.expired });
  if (before.verificationStatus === "verified") return res.json({ verification: verification.verificationView(before) });

  const result = await verification.confirmEmailCode(before.id, req.body?.code);
  if (result.error) return sendError(res, result.error);
  await verification.notifyTeam(before.ownerId, verification.VERIFIED_EVENT(result.company.name));
  res.json({ verification: verification.verificationView(result.company) });
});

// GET /company/:id -- the public company page (any signed-in account); open
// postings only.
// Ids are UUIDs; anything else (wishlist, shortlisted, searches, ...) belongs
// to the hiring router mounted after this one.
router.get("/:id", async (req, res, next) => {
  if (!UUID_RE.test(req.params.id)) return next();
  // Either the Company id or its owner's user id (chat and notification links
  // carry the recruiter's user id).
  const company = await prisma.company.findFirst({
    where: { OR: [{ id: req.params.id }, { ownerId: req.params.id }] },
  });
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
