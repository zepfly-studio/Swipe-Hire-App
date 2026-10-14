// Small coercion helpers so routes never trust raw JSON types.

function str(value, max = 2000) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function num(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function int(value, fallback = 0) {
  return Math.trunc(num(value, fallback));
}

function bool(value, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

function strList(value, maxItems = 50) {
  if (!Array.isArray(value)) return [];
  return value
    .map((v) => str(v, 60))
    .filter(Boolean)
    .slice(0, maxItems);
}

function date(value) {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function requireRole(role) {
  return (req, res, next) => {
    if (req.user.role !== role) {
      return res.status(403).json({ error: `Only ${role} accounts can do this.` });
    }
    next();
  };
}

module.exports = { str, num, int, bool, strList, date, requireRole };
