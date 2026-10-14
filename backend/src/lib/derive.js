// Turns the free-text profile fields people type ("3 years", "2 months",
// "Immediate", "Flutter, Dart") into values the database can filter and sort
// on. Used whenever a profile or posting is saved; the matching SQL backfill
// lives in prisma/migrations (phase1_phase2 + fix_experience_backfill).

function normalizeSkills(list) {
  if (!Array.isArray(list)) return [];
  return [...new Set(list.map((s) => String(s).trim().toLowerCase()).filter(Boolean))];
}

function firstNumber(text) {
  const m = String(text ?? "").match(/\d+(?:\.\d+)?/);
  return m ? Number(m[0]) : null;
}

// "Fresher" and anything without a number are 0 years; "6 months" is half a year.
function parseExperienceYears(text) {
  const n = firstNumber(text);
  if (n === null) return 0;
  const lower = String(text).toLowerCase();
  if (/month/.test(lower) && !/year|yr/.test(lower)) return Math.round((n / 12) * 10) / 10;
  return n;
}

// "Immediate" is 0, "2 months" is 60, "3 weeks" is 21, "30 days" is 30.
function parseNoticeDays(text) {
  const lower = String(text ?? "").toLowerCase();
  if (/immediate|none|no notice|serving/.test(lower)) return 0;
  const n = firstNumber(lower);
  if (/month/.test(lower)) return Math.round((n ?? 1) * 30);
  if (/week/.test(lower)) return Math.round((n ?? 1) * 7);
  return Math.round(n ?? 0);
}

module.exports = { normalizeSkills, parseExperienceYears, parseNoticeDays };
