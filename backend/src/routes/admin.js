const express = require("express");
const { prisma } = require("../lib/prisma");
const { requireAuth } = require("../middleware/requireAuth");
const { isAdminUser } = require("../lib/admin");
const { notifyTeam, VERIFIED_EVENT, REJECTED_EVENT } = require("../lib/companyVerification");

const router = express.Router();
router.use(requireAuth);
router.use((req, res, next) => {
  if (!isAdminUser(req.user)) return res.status(403).json({ error: "Admins only" });
  next();
});

// GET /admin/verifications -> { companies:[{ id, companyName, website, location,
//   gstin, contact:{name,email}, requestedAt }] } -- pending requests, oldest first.
router.get("/verifications", async (req, res) => {
  const rows = await prisma.company.findMany({
    where: { verificationStatus: "pending" },
    include: { owner: { select: { name: true, email: true } } },
  });
  const companies = rows.map((c) => {
    const requested = c.verificationOtp && typeof c.verificationOtp === "object" ? c.verificationOtp.gstRequestedAt : null;
    return {
      id: c.ownerId,
      companyName: c.name,
      website: c.website,
      location: c.location,
      gstin: c.gstin,
      contact: { name: c.owner?.name ?? "", email: c.owner?.email ?? "" },
      // Requests made before the timestamp was stored fall back to the last edit.
      requestedAt: requested || c.updatedAt.toISOString(),
    };
  });
  companies.sort((a, b) => Date.parse(a.requestedAt) - Date.parse(b.requestedAt));
  res.json({ companies });
});

// POST /admin/verifications/:companyId { approve } -> { ok:true }
// `:companyId` is the owner's user id. Only `approve: true` approves.
router.post("/verifications/:companyId", async (req, res) => {
  const approve = req.body?.approve === true;
  const company = await prisma.company.findFirst({
    where: { ownerId: req.params.companyId, verificationStatus: "pending" },
  });
  if (!company) return res.status(404).json({ error: "No pending request for this company" });

  // Conditional on still being pending, so two admins can't both decide.
  const { count } = await prisma.company.updateMany({
    where: { id: company.id, verificationStatus: "pending" },
    data: approve
      ? { verificationStatus: "verified", verificationMethod: "gst", verificationNote: "manual", verifiedAt: new Date() }
      : { verificationStatus: "rejected", verificationMethod: "gst", verifiedAt: null },
  });
  if (count === 0) return res.status(404).json({ error: "No pending request for this company" });

  await notifyTeam(company.ownerId, approve ? VERIFIED_EVENT(company.name) : REJECTED_EVENT(company.name));
  res.json({ ok: true });
});

// GET /admin/companies?status=all|unverified|pending|verified|rejected&q= ->
//   { companies:[{ id, companyName, website, location, industry, status,
//   verified, method, gstin, contact:{name,email}, createdAt, requestedAt? }] }
// Every company, newest first (max 100), so an admin can verify one by hand
// without it ever having submitted a GSTIN.
router.get("/companies", async (req, res) => {
  const status = String(req.query.status || "all");
  const q = String(req.query.q || "").trim().slice(0, 80);
  const where = {};
  if (["unverified", "pending", "verified", "rejected"].includes(status)) where.verificationStatus = status;
  if (q) {
    where.OR = [
      { name: { contains: q, mode: "insensitive" } },
      { website: { contains: q, mode: "insensitive" } },
      { owner: { is: { email: { contains: q, mode: "insensitive" } } } },
      { owner: { is: { name: { contains: q, mode: "insensitive" } } } },
    ];
  }
  const rows = await prisma.company.findMany({
    where,
    include: { owner: { select: { name: true, email: true } } },
    orderBy: { createdAt: "desc" },
    take: 100,
  });
  const companies = rows.map((c) => {
    const requested = c.verificationOtp && typeof c.verificationOtp === "object" ? c.verificationOtp.gstRequestedAt : null;
    return {
      id: c.ownerId,
      companyName: c.name,
      website: c.website,
      location: c.location,
      industry: c.industry,
      status: c.verificationStatus,
      verified: c.verificationStatus === "verified",
      method: c.verificationMethod,
      gstin: c.gstin,
      contact: { name: c.owner?.name ?? "", email: c.owner?.email ?? "" },
      createdAt: c.createdAt.toISOString(),
      ...(c.verificationStatus === "pending" ? { requestedAt: requested || c.updatedAt.toISOString() } : {}),
    };
  });
  res.json({ companies });
});

// POST /admin/companies/:companyId/verify { verified: boolean } -> { ok, status, verified }
// `:companyId` is the owner's user id. Verifies (method "admin") or removes
// the badge. No GSTIN or work-email proof is needed: it is the admin's call.
router.post("/companies/:companyId/verify", async (req, res) => {
  if (typeof req.body?.verified !== "boolean") {
    return res.status(400).json({ error: "Send { verified: true } or { verified: false }.", field: "verified" });
  }
  const company = await prisma.company.findFirst({ where: { ownerId: req.params.companyId } });
  if (!company) return res.status(404).json({ error: "Company not found" });

  const verify = req.body.verified;
  const wasVerified = company.verificationStatus === "verified";
  await prisma.company.update({
    where: { id: company.id },
    data: verify
      ? { verificationStatus: "verified", verificationMethod: "admin", verificationNote: "admin", verifiedAt: new Date() }
      : { verificationStatus: "unverified", verificationMethod: "", verificationNote: "", verifiedAt: null },
  });
  if (verify && !wasVerified) await notifyTeam(company.ownerId, VERIFIED_EVENT(company.name));
  res.json({ ok: true, status: verify ? "verified" : "unverified", verified: verify });
});

module.exports = router;
