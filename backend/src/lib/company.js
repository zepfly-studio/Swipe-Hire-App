// Company verification: a company counts as verified automatically when its
// website's domain is the domain of the recruiter's own email -- an address
// they already proved they control with the signup OTP -- and that domain
// isn't a free mail provider (anyone can have a gmail.com address).

const FREE_MAIL_DOMAINS = new Set([
  "gmail.com", "googlemail.com", "yahoo.com", "yahoo.in", "yahoo.co.in", "outlook.com", "hotmail.com",
  "live.com", "msn.com", "icloud.com", "me.com", "aol.com", "proton.me", "protonmail.com", "zoho.com",
  "rediffmail.com", "gmx.com", "mail.com", "yandex.com", "example.com", "example.net", "example.org",
]);

function stripWww(host) {
  return host.replace(/^www\./, "");
}

function domainFromUrl(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  try {
    const url = new URL(/^[a-z]+:\/\//i.test(raw) ? raw : `https://${raw}`);
    return stripWww(url.hostname.toLowerCase());
  } catch {
    return "";
  }
}

function domainFromEmail(email) {
  const at = String(email || "").lastIndexOf("@");
  return at === -1 ? "" : String(email).slice(at + 1).toLowerCase().trim();
}

// Provider names that are free mail on any country domain (yahoo.com,
// yahoo.co.in, hotmail.co.uk ...).
const FREE_MAIL_NAMES = new Set([
  "gmail", "googlemail", "yahoo", "ymail", "hotmail", "outlook", "live", "msn", "rediffmail", "icloud",
  "me", "aol", "proton", "protonmail", "zoho", "gmx", "yandex",
]);
const SECOND_LEVEL = new Set(["co", "com", "org", "net", "ac", "gov", "edu"]);

// The name part of a registrable domain: "acme" for mail.acme.co.in.
function registrableName(domain) {
  const parts = String(domain || "").toLowerCase().split(".").filter(Boolean);
  if (parts.length <= 1) return parts[0] || "";
  const tld = parts[parts.length - 1];
  if (parts.length >= 3 && tld.length === 2 && SECOND_LEVEL.has(parts[parts.length - 2])) return parts[parts.length - 3];
  return parts[parts.length - 2];
}

function isFreeMail(domain) {
  const d = String(domain || "").toLowerCase();
  return FREE_MAIL_DOMAINS.has(d) || FREE_MAIL_NAMES.has(registrableName(d));
}

// A website on the same domain, or a subdomain of the email's domain
// (careers.acme.com for someone@acme.com).
function domainsMatch(websiteDomain, emailDomain) {
  if (!websiteDomain || !emailDomain) return false;
  return websiteDomain === emailDomain || websiteDomain.endsWith(`.${emailDomain}`) || emailDomain.endsWith(`.${websiteDomain}`);
}

/** @returns {"verified" | "unverified"} what can be established automatically */
function automaticVerification({ website, ownerEmail }) {
  const emailDomain = domainFromEmail(ownerEmail);
  if (isFreeMail(emailDomain)) return "unverified";
  return domainsMatch(domainFromUrl(website), emailDomain) ? "verified" : "unverified";
}

function normalizeWebsite(value) {
  const raw = String(value || "").trim();
  if (!raw) return "";
  const withScheme = /^[a-z]+:\/\//i.test(raw) ? raw : `https://${raw}`;
  try {
    const url = new URL(withScheme);
    if (!["http:", "https:"].includes(url.protocol)) return "";
    return url.origin + (url.pathname === "/" ? "" : url.pathname);
  } catch {
    return "";
  }
}

module.exports = { domainFromUrl, domainFromEmail, isFreeMail, domainsMatch, automaticVerification, normalizeWebsite };
