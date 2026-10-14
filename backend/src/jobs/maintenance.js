// Housekeeping that keeps the database from growing without bound.

const { prisma } = require("../lib/prisma");

const INTERVAL_MS = 60 * 60 * 1000;

// One-time codes are useless a day after they expire, but each signup or
// password reset leaves a row behind.
async function cleanupExpiredOtps(now = new Date()) {
  const cutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  const { count } = await prisma.otpCode.deleteMany({ where: { expiresAt: { lt: cutoff } } });
  return count;
}

function startMaintenance() {
  const tick = () =>
    cleanupExpiredOtps()
      .then((count) => {
        if (count) console.log(`[maintenance] removed ${count} expired OTP code(s)`);
      })
      .catch((err) => console.error("[maintenance] cleanup failed:", err.message));

  setTimeout(tick, 60 * 1000).unref();
  setInterval(tick, INTERVAL_MS).unref();
}

module.exports = { cleanupExpiredOtps, startMaintenance };
