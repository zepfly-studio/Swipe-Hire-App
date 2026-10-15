// Who counts as a GlideRecruit admin: an address in ADMIN_EMAILS (comma
// separated, case-insensitive) whose email is verified.
function adminEmails() {
  return String(process.env.ADMIN_EMAILS || "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
}

function isAdminUser(user) {
  if (!user || !user.email || user.emailVerified === false) return false;
  return adminEmails().includes(String(user.email).toLowerCase());
}

module.exports = { isAdminUser, adminEmails };
