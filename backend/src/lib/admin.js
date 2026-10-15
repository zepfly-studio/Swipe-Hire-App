// Who counts as a GlideRecruit admin: an address in ADMIN_EMAILS (comma
// separated, case-insensitive) whose email is verified.
// The product owner is an admin out of the box, so the admin panel works
// without any server setting. Setting ADMIN_EMAILS replaces this list.
const DEFAULT_ADMIN_EMAILS = ["content.zepfly@gmail.com"];

function adminEmails() {
  const configured = String(process.env.ADMIN_EMAILS || "")
    .split(",")
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean);
  return configured.length ? configured : DEFAULT_ADMIN_EMAILS;
}

function isAdminUser(user) {
  if (!user || !user.email || user.emailVerified === false) return false;
  return adminEmails().includes(String(user.email).toLowerCase());
}

module.exports = { isAdminUser, adminEmails, DEFAULT_ADMIN_EMAILS };
