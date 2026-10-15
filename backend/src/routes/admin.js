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

module.exports = router;
