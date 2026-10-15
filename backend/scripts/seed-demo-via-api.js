// Fills a DEPLOYED backend with realistic demo data through its public API,
// exactly the way the app does (no database access needed):
//   - 50 candidates with complete profiles (photo, skills, salary, notice...)
//   - 9 companies for the admin panel: 3 verified (work-email domain), 3 with a
//     GSTIN waiting for review, 3 not verified; each with 1-2 open jobs
//
//   node scripts/seed-demo-via-api.js                  everything
//   node scripts/seed-demo-via-api.js --only=companies
//   node scripts/seed-demo-via-api.js --only=candidates
//
// Environment:
//   API_BASE_URL     default https://swipe-hire-app.onrender.com
//   SEED_STATE_FILE  where created accounts (email + generated password) are
//                    remembered; default scripts/.demo-accounts.json (gitignored)
//
// Notes:
//   - The auth routes allow 30 requests per 15 minutes per IP, so a full run
//     takes about an hour; it waits for the window to reset on its own.
//   - Safe to re-run: an email that already exists is skipped.
//   - OTP codes come back in the API response because the server has
//     OTP_DEV_FALLBACK=true; nothing is emailed to the demo addresses.
//   - Passwords are random and only kept in the state file, so the accounts
//     can be removed later (DELETE /users/me) but nobody can guess them.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { CANDIDATES, photoFor } = require("./seed-demo-candidates");

const BASE = (process.env.API_BASE_URL || "https://swipe-hire-app.onrender.com").replace(/\/$/, "");
const STATE_FILE = process.env.SEED_STATE_FILE || path.join(__dirname, ".demo-accounts.json");
const ONLY = (process.argv.find((a) => a.startsWith("--only=")) || "").slice(7);
const DOMAIN = "glide-demo-mail.in";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// ---- state ------------------------------------------------------------
let state = { accounts: [] };
try {
  state = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
} catch {
  /* first run */
}
function remember(account) {
  state.accounts.push(account);
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}
const known = (email) => state.accounts.find((a) => a.email === email);

// ---- http -------------------------------------------------------------
async function api(method, route, { token, body } = {}) {
  for (let attempt = 0; ; attempt++) {
    let res;
    try {
      res = await fetch(BASE + route, {
        method,
        headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(90000),
      });
    } catch (e) {
      if (attempt >= 4) throw e;
      log(`network error (${e.message}); retrying`);
      await sleep(5000 * (attempt + 1));
      continue;
    }
    if (res.status === 429) {
      // "ratelimit: "30-in-15min"; r=0; t=612" -> seconds until the window resets
      const header = res.headers.get("ratelimit") || "";
      const t = Number((header.match(/t=(\d+)/) || [])[1]) || 900;
      log(`rate limited; waiting ${t + 3}s for the window to reset`);
      await sleep((t + 3) * 1000);
      continue;
    }
    let json = {};
    try {
      json = await res.json();
    } catch {
      /* empty */
    }
    return { status: res.status, json };
  }
}

function must(res, what) {
  if (res.status < 200 || res.status >= 300) {
    throw new Error(`${what} failed: ${res.status} ${JSON.stringify(res.json).slice(0, 200)}`);
  }
  return res.json;
}

/** otp -> verify -> signup. Returns null when the account already exists. */
async function createAccount({ email, name, role, company }) {
  if (known(email)) return null;
  const send = await api("POST", "/auth/otp/send", { body: { email } });
  if (send.status === 409) return null;
  must(send, `otp/send ${email}`);
  if (!send.json.otp) throw new Error(`no otp returned for ${email} (is OTP_DEV_FALLBACK on?)`);
  must(await api("POST", "/auth/otp/verify", { body: { email, otp: send.json.otp } }), `otp/verify ${email}`);
  const password = "Demo-" + crypto.randomBytes(9).toString("hex");
  const out = must(
    await api("POST", "/auth/signup", { body: { name, email, password, role, ...(company ? { company } : {}) } }),
    `signup ${email}`,
  );
  const user = out.user || {};
  remember({ email, password, role, id: user.uid || user.id, name });
  return { token: out.token, id: user.uid || user.id };
}

// ---- companies (admin panel data) --------------------------------------
const COMPANIES = [
  // Verified automatically: the recruiter's work email is on the company site's domain.
  {
    name: "BrightPath Technologies", city: "Bengaluru", industry: "IT / Software", size: "51-200",
    site: "brightpath-demo.in", hr: "Neha Kapoor", mailbox: "hr", state: "verified",
    about: "Product engineering studio building mobile and cloud apps for fintech and retail brands.",
    jobs: [
      { title: "Flutter Developer", skills: ["Flutter", "Dart", "Firebase"], min: 2, max: 5, lo: 10, hi: 20, mode: "hybrid" },
      { title: "Backend Developer (Node.js)", skills: ["Node.js", "PostgreSQL", "Docker"], min: 3, max: 6, lo: 14, hi: 24, mode: "onsite" },
    ],
  },
  {
    name: "Zenith Infosystems", city: "Hyderabad", industry: "IT / Software", size: "201-1000",
    site: "zenithinfosys-demo.in", hr: "Arvind Reddy", mailbox: "careers", state: "verified",
    about: "Enterprise software services with delivery centres across India. We hire for long-term product teams.",
    jobs: [
      { title: "Java Backend Engineer", skills: ["Java", "Spring Boot", "Microservices"], min: 4, max: 8, lo: 16, hi: 28, mode: "onsite" },
      { title: "QA Automation Engineer", skills: ["Selenium", "API Testing", "Cypress"], min: 2, max: 5, lo: 8, hi: 14, mode: "hybrid" },
    ],
  },
  {
    name: "Orbit Digital", city: "Pune", industry: "Marketing / Media", size: "11-50",
    site: "orbitdigital-demo.in", hr: "Sakshi Joshi", mailbox: "talent", state: "verified",
    about: "Growth marketing and design agency working with D2C brands. Small team, big ownership.",
    jobs: [
      { title: "Digital Marketing Executive", skills: ["SEO", "Google Ads", "Social Media"], min: 1, max: 4, lo: 4, hi: 8, mode: "onsite" },
      { title: "UI/UX Designer", skills: ["Figma", "Prototyping", "Design Systems"], min: 2, max: 5, lo: 8, hi: 15, mode: "hybrid" },
    ],
  },
  // GSTIN submitted, waiting for an admin (login email is NOT on the company domain).
  {
    name: "NovaByte Solutions", city: "Noida", industry: "IT / Software", size: "11-50",
    site: "novabyte-demo.in", hr: "Rohit Malhotra", mailbox: "talent.novabyte", state: "pending", gstin: "09AAACN4321K1Z8",
    about: "Cloud consulting and DevOps services for growing startups.",
    jobs: [
      { title: "DevOps Engineer", skills: ["AWS", "Docker", "Kubernetes", "Terraform"], min: 3, max: 7, lo: 14, hi: 26, mode: "remote" },
    ],
  },
  {
    name: "Kesari Retail Pvt Ltd", city: "Jaipur", industry: "Retail", size: "201-1000",
    site: "kesariretail-demo.in", hr: "Pooja Sharma", mailbox: "hr.kesari", state: "pending", gstin: "08AABCK7788M1ZP",
    about: "Regional retail chain with 40 stores, moving its operations and analytics to modern tools.",
    jobs: [
      { title: "Data Analyst", skills: ["SQL", "Power BI", "Excel"], min: 1, max: 4, lo: 5, hi: 10, mode: "onsite" },
      { title: "Operations Executive", skills: ["Operations", "Excel", "Logistics"], min: 1, max: 3, lo: 3, hi: 6, mode: "onsite" },
    ],
  },
  {
    name: "Sapphire Healthcare Services", city: "Mumbai", industry: "Healthcare", size: "51-200",
    site: "sapphirehealth-demo.in", hr: "Dr. Meenal Iyer", mailbox: "recruit.sapphire", state: "pending", gstin: "27AAECS5566R1ZQ",
    about: "Diagnostics and telehealth provider building its first in-house product team.",
    jobs: [
      { title: "Full Stack Developer", skills: ["React", "Node.js", "PostgreSQL"], min: 2, max: 5, lo: 10, hi: 18, mode: "hybrid" },
    ],
  },
  // Nothing submitted yet: the admin can verify these by hand.
  {
    name: "GreenLeaf Agritech", city: "Indore", industry: "Other", size: "11-50",
    site: "greenleafagri-demo.in", hr: "Amit Choudhary", mailbox: "founder.greenleaf", state: "none",
    about: "Agri-tech startup helping farmers sell directly to retailers.",
    jobs: [
      { title: "Python Developer", skills: ["Python", "Django", "PostgreSQL"], min: 1, max: 4, lo: 6, hi: 12, mode: "hybrid" },
    ],
  },
  {
    name: "Pixel Orchard Studio", city: "Kochi", industry: "Marketing / Media", size: "1-10",
    site: "pixelorchard-demo.in", hr: "Anjali Menon", mailbox: "studio.pixel", state: "none",
    about: "Boutique design studio for brand identities, apps and websites.",
    jobs: [
      { title: "UI Designer", skills: ["Figma", "Illustrator", "Responsive Design"], min: 1, max: 3, lo: 4, hi: 9, mode: "remote" },
      { title: "Content Writer", skills: ["Content Writing", "SEO", "Copywriting"], min: 1, max: 3, lo: 3, hi: 6, mode: "remote" },
    ],
  },
  {
    name: "Swift Logistics", city: "Delhi", industry: "Other", size: "51-200",
    site: "swiftlogistics-demo.in", hr: "Karan Bedi", mailbox: "hiring.swift", state: "none",
    about: "Last-mile logistics for e-commerce sellers across NCR.",
    jobs: [
      { title: "Customer Support Executive", skills: ["Customer Support", "Communication", "CRM"], min: 0, max: 3, lo: 2.5, hi: 5, mode: "onsite" },
    ],
  },
];

async function seedCompany(c) {
  const email = `${c.mailbox}@${c.state === "verified" ? c.site : DOMAIN}`;
  const account = await createAccount({ email, name: c.hr, role: "recruiter", company: c.name });
  if (!account) return log(`skip company (exists): ${c.name}`);
  const [first, ...more] = c.jobs;
  const body = {
    company: { name: c.name, industry: c.industry, size: c.size, location: c.city, website: `https://${c.site}`, about: c.about },
    job: {
      title: first.title, skills: first.skills, minExperienceYears: first.min, maxExperienceYears: first.max,
      salaryMinLpa: first.lo, salaryMaxLpa: first.hi, location: c.city, workMode: first.mode,
    },
  };
  must(await api("POST", "/company/onboarding", { token: account.token, body }), `onboarding ${c.name}`);
  for (const j of more) {
    must(
      await api("POST", "/jobs", {
        token: account.token,
        body: {
          title: j.title, skills: j.skills, minExperienceYears: j.min, maxExperienceYears: j.max,
          salaryMinLpa: j.lo, salaryMaxLpa: j.hi, location: c.city, workMode: j.mode,
          employmentType: "full-time", openings: 2,
          description: `${c.name} is hiring a ${j.title} in ${c.city}. You will work with a small, friendly team.`,
        },
      }),
      `job ${j.title}`,
    );
  }
  let status = "not verified";
  if (c.state === "pending") {
    must(await api("POST", "/company/verification/gst", { token: account.token, body: { gstin: c.gstin } }), `gstin ${c.name}`);
    status = "GSTIN pending";
  } else if (c.state === "verified") {
    status = "verified (domain)";
  }
  log(`company ready: ${c.name} -> ${status}, ${c.jobs.length} job(s)`);
}

// ---- candidates --------------------------------------------------------
const FEMALE = new Set([
  "riya", "sneha", "priya", "sana", "pooja", "isha", "tanvi", "meera", "neha", "kavya", "shreya", "ananya",
  "divya", "bhavna", "lakshmi", "ritika", "aditi", "simran", "ishita", "payal", "nandini", "ayesha", "pallavi", "zoya",
]);

function qualificationOf(degreeText) {
  const d = degreeText.toLowerCase();
  if (/diploma/.test(d)) return "Diploma";
  if (/(^|\b)(m\.?tech|mca|mba|m\.?sc|m\.?des|m\.?com|ma\b|pgdm|m\.e)/.test(d)) return "Post Graduate";
  return "Graduate";
}

async function seedCandidate(row, index) {
  const [name, age, role, experience, qualificationText, location, skills, expected, company, currentLpa, notice, about] = row;
  const [first, ...rest] = name.split(" ");
  const email = `demo.${first.toLowerCase()}.${rest[rest.length - 1].toLowerCase().replace(/[^a-z]/g, "")}@${DOMAIN}`;
  const account = await createAccount({ email, name, role: "candidate" });
  if (!account) return log(`skip candidate (exists): ${name}`);

  const [degree, college = ""] = qualificationText.split(",").map((s) => s.trim());
  const years = Number((experience.match(/\d+(\.\d+)?/) || [0])[0]) || 0;
  const female = FEMALE.has(first.toLowerCase());
  const phone = `+91 90000 ${String(10000 + index).slice(-5)}`;
  const modes = [["onsite"], ["hybrid"], ["remote", "hybrid"], ["onsite", "hybrid"]][index % 4];
  const types = /fresher|intern/i.test(role + experience) ? ["full-time", "internship"] : ["full-time"];

  must(
    await api("PUT", "/candidates/me/profile", {
      token: account.token,
      body: {
        desiredRole: role, phone, age, gender: female ? "Female" : "Male", location,
        qualification: qualificationOf(degree), degree, college,
        graduationYear: Math.max(2008, 2026 - Math.ceil(years) - 1),
        skills, experience: experience === "Fresher" ? "Fresher" : experience,
        currentCompany: company === "Fresher" ? "" : company,
        currentPost: company === "Fresher" ? "" : role,
        currentSalaryLpa: currentLpa, expectedSalaryLpa: expected,
        expectedSalaryMaxLpa: Math.round(expected * 1.25 * 10) / 10,
        salaryNegotiable: index % 3 === 0, noticePeriod: notice, about,
        workModes: modes, jobTypes: types, photoUrl: photoFor(name, index),
      },
    }),
    `profile ${name}`,
  );
  must(
    await api("PUT", "/candidates/me/preferences", {
      token: account.token,
      body: { openToWork: true, workModes: modes, jobTypes: types, preferredLocations: [location, ["Remote", "Pune", "Bengaluru", "Hyderabad"][index % 4]].filter((v, i, a) => a.indexOf(v) === i) },
    }),
    `preferences ${name}`,
  );
  must(await api("PATCH", "/users/me", { token: account.token, body: { profileComplete: true } }), `complete ${name}`);
  log(`candidate ready (${index + 1}/${CANDIDATES.length}): ${name}`);
}

// ---- main --------------------------------------------------------------
(async () => {
  log(`target: ${BASE}  state: ${STATE_FILE}  (${state.accounts.length} accounts remembered)`);
  const health = await api("GET", "/health");
  if (health.status !== 200) throw new Error(`backend not healthy: ${health.status}`);

  if (ONLY !== "candidates") {
    for (const c of COMPANIES) {
      try { await seedCompany(c); } catch (e) { log(`FAILED company ${c.name}: ${e.message}`); }
    }
  }
  if (ONLY !== "companies") {
    for (const [i, row] of CANDIDATES.entries()) {
      try { await seedCandidate(row, i); } catch (e) { log(`FAILED candidate ${row[0]}: ${e.message}`); }
    }
  }
  const byRole = state.accounts.reduce((m, a) => ((m[a.role] = (m[a.role] || 0) + 1), m), {});
  log("done.", JSON.stringify(byRole));
})().catch((e) => {
  console.error("Seed failed:", e.message);
  process.exit(1);
});
