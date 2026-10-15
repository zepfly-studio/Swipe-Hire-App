const jwt = require("jsonwebtoken");
const { prisma } = require("../lib/prisma");

// Besides the signed-in user this sets, on `req.user`:
//   companyId  the hiring account every recruiter-side record hangs off: the
//              owner's user id for a team member, the user's own id otherwise
//              (candidates get their own id, which they never use).
//   isOwner    true for a recruiter who is not a team member.
// Tokens carry the user's `tokenVersion` (`v`); "log out of all devices" and a
// password change bump it, which makes every older token invalid.
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({ error: "Missing bearer token." });
  }

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    const user = await prisma.user.findUnique({ where: { id: payload.sub } });
    if (!user) {
      return res.status(401).json({ error: "User no longer exists." });
    }
    if ((payload.v ?? 0) !== (user.tokenVersion ?? 0)) {
      return res.status(401).json({ error: "Your session has expired, please log in again." });
    }
    user.companyId = user.companyOwnerId || user.id;
    user.isOwner = user.role === "recruiter" && !user.companyOwnerId;
    req.user = user;
    next();
  } catch (err) {
    return res.status(401).json({ error: "Invalid or expired token." });
  }
}

module.exports = { requireAuth };
