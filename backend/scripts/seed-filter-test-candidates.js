// Adds demo candidates built to TEST the recruiter's filters through a deployed
// backend's public API (same way as seed-demo-via-api.js). The first 50 demo
// candidates only ever have the full-time job type, no remote-only people and
// nobody with a 15/90-day notice or a part-time/contract preference, so those
// filter options returned nothing. Every candidate here has a role/about text
// that says which filter values it should match.
//
//   node scripts/seed-filter-test-candidates.js
//
// Environment: API_BASE_URL (default the Render backend), FILTER_STATE_FILE
// (default scripts/.filter-test-accounts.json, gitignored).
// Safe to re-run: an email that already exists is skipped. The auth routes
// allow 30 requests per 15 minutes per IP (3 per candidate), so a full run
// takes about 35 minutes; it waits for the window to reset on its own.

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { api, must, emailOf, profileBody, BASE } = require("./seed-demo-via-api");

const STATE_FILE = process.env.FILTER_STATE_FILE || path.join(__dirname, ".filter-test-accounts.json");
const log = (...a) => console.log(new Date().toISOString().slice(11, 19), ...a);

// name, age, role, experience, qualification, city, skills, expected LPA,
// current company, current LPA, notice, about, work modes, job types, negotiable
const ROWS = [
  ["Ritika Sharma", 24, "Content Writer", "1 year", "BA English, University of Rajasthan", "Jaipur",
    ["Content Writing", "SEO", "WordPress"], 3.0, "Pinkcity Media", 2.2, "Immediate",
    "TEST: Jaipur · 1 yr · remote · part-time · Immediate notice · budget up to 3 LPA.",
    ["remote"], ["part-time"], false],
  ["Manish Yadav", 28, "Freelance Flutter Developer", "4 years", "B.Tech Computer Science, JECRC Jaipur", "Jaipur",
    ["Flutter", "Dart", "Firebase"], 9.0, "Freelance", 8.0, "15 days",
    "TEST: Jaipur · 4 yrs · remote · contract · 15 days notice · Flutter.",
    ["remote"], ["contract"], false],
  ["Aarti Bhatt", 27, "React Developer (Contract)", "3 years", "B.Tech IT, COEP Pune", "Pune",
    ["React", "JavaScript", "Node.js"], 11.0, "Freelance", 9.0, "Immediate",
    "TEST: Pune · 3 yrs · remote or hybrid · contract · Immediate notice · React.",
    ["remote", "hybrid"], ["contract"], true],
  ["Zubin Irani", 26, "QA Tester", "2 years", "BCA, Mumbai University", "Mumbai",
    ["Selenium", "Postman", "JIRA"], 4.5, "Testwave", 3.6, "15 days",
    "TEST: Mumbai · 2 yrs · on-site · part-time · 15 days notice · QA.",
    ["onsite"], ["part-time"], false],
  ["Lakshmi Narayan", 31, "Data Analyst", "6 years", "M.Sc Statistics, Madras University", "Chennai",
    ["SQL", "Python", "Tableau"], 18.0, "Anvaya Analytics", 14.0, "90 days",
    "TEST: Chennai · 6 yrs · hybrid · full-time · 90 days notice · budget 18 LPA.",
    ["hybrid"], ["full-time"], false],
  ["Gaurav Tiwari", 30, "DevOps Engineer", "5 years", "B.Tech Computer Science, VIT Bengaluru", "Bengaluru",
    ["AWS", "Docker", "Kubernetes", "Terraform"], 21.0, "CloudNest", 16.0, "60 days",
    "TEST: Bengaluru · 5 yrs · remote · full-time or contract · 60 days notice · DevOps.",
    ["remote"], ["full-time", "contract"], false],
  ["Pallavi Deshpande", 21, "Graphic Design Intern", "Fresher", "B.Des, MIT Pune", "Pune",
    ["Figma", "Photoshop", "Illustrator"], 1.8, "Fresher", 0, "Immediate",
    "TEST: Pune · fresher · on-site · internship · Immediate notice · budget 1.8 LPA.",
    ["onsite"], ["internship"], true],
  ["Rajat Bhargava", 22, "Marketing Intern", "Fresher", "BBA, Delhi University", "Delhi",
    ["SEO", "Social Media", "Canva"], 1.5, "Fresher", 0, "Immediate",
    "TEST: Delhi · fresher · hybrid · internship or part-time · Immediate notice.",
    ["hybrid"], ["internship", "part-time"], true],
  ["Ishita Kaur", 26, "Android Developer", "2 years", "B.Tech CSE, Chandigarh University", "Chandigarh",
    ["Kotlin", "Android", "Jetpack Compose"], 8.0, "Tricity Apps", 6.0, "30 days",
    "TEST: Chandigarh · 2 yrs · on-site or hybrid · full-time · 30 days notice · Kotlin.",
    ["onsite", "hybrid"], ["full-time"], false],
  ["Imran Pathan", 35, "Java Architect", "8 years", "BE Computer Engineering, Pune University", "Pune",
    ["Java", "Spring Boot", "Microservices"], 28.0, "Finserv Labs", 23.0, "90 days",
    "TEST: Pune · 8 yrs · hybrid · full-time · 90 days notice · budget 28 LPA.",
    ["hybrid"], ["full-time"], false],
  ["Nandini Rao", 23, "Python Developer", "1 year", "B.Tech CSE, JNTU Hyderabad", "Hyderabad",
    ["Python", "Django", "SQL"], 5.0, "Charminar Soft", 3.8, "15 days",
    "TEST: Hyderabad · 1 yr · on-site · full-time · 15 days notice · Python.",
    ["onsite"], ["full-time"], false],
  ["Vivek Anand", 38, "Principal Full Stack Engineer", "10 years", "B.Tech CSE, IIT Kanpur", "Bengaluru",
    ["React", "Node.js", "AWS", "System Design"], 38.0, "Scaleup Labs", 32.0, "60 days",
    "TEST: Bengaluru · 10 yrs · remote or hybrid · full-time · 60 days notice · budget 38 LPA.",
    ["remote", "hybrid"], ["full-time"], false],
  ["Aditi Wadhwa", 27, "HR Executive", "2 years", "MBA HR, Symbiosis Pune", "Delhi",
    ["Recruitment", "Excel", "Communication"], 4.0, "PeopleFirst", 3.2, "30 days",
    "TEST: Delhi · 2 yrs · on-site · full-time · 30 days notice · HR.",
    ["onsite"], ["full-time"], false],
  ["Tarun Mishra", 29, "Sales Executive", "3 years", "BBA, Rajasthan University", "Jaipur",
    ["Sales", "CRM", "Negotiation"], 5.5, "Gems & Co", 4.5, "15 days",
    "TEST: Jaipur · 3 yrs · on-site · full-time or part-time · 15 days notice · Sales.",
    ["onsite"], ["full-time", "part-time"], true],
  ["Payal Chawla", 30, "UI/UX Designer (Contract)", "4 years", "B.Des, NIFT Mumbai", "Mumbai",
    ["Figma", "Prototyping", "User Research"], 12.0, "Freelance", 10.0, "Immediate",
    "TEST: Mumbai · 4 yrs · remote · contract · Immediate notice · Figma.",
    ["remote"], ["contract"], false],
  ["Dev Malhotra", 25, "Backend Developer", "2 years", "B.Tech IT, DTU Delhi", "Gurugram",
    ["Node.js", "PostgreSQL", "Docker"], 10.0, "Cyberhub Tech", 7.5, "60 days",
    "TEST: Gurugram · 2 yrs · hybrid · full-time · 60 days notice · Node.js.",
    ["hybrid"], ["full-time"], false],
  ["Sakshi Verma", 28, "Digital Marketer", "3 years", "MBA Marketing, JK Lakshmipat Jaipur", "Jaipur",
    ["SEO", "Google Ads", "Analytics"], 6.0, "Brandcraft", 4.8, "30 days",
    "TEST: Jaipur · 3 yrs · hybrid · full-time · 30 days notice · SEO.",
    ["hybrid"], ["full-time"], false],
  ["Harpreet Gill", 32, "Data Engineer", "5 years", "B.Tech CSE, Thapar University", "Hyderabad",
    ["Python", "Spark", "Airflow", "SQL"], 20.0, "Datagrid", 16.0, "90 days",
    "TEST: Hyderabad · 5 yrs · remote · full-time · 90 days notice · Spark.",
    ["remote"], ["full-time"], false],
  ["Anjali Menon", 24, "iOS Developer", "1 year", "B.Tech CSE, CUSAT Kochi", "Kochi",
    ["Swift", "SwiftUI", "iOS"], 6.5, "Spice Coast Apps", 4.8, "Immediate",
    "TEST: Kochi · 1 yr · on-site or remote · full-time or contract · Immediate notice · Swift.",
    ["onsite", "remote"], ["full-time", "contract"], true],
  ["Kunal Saxena", 34, "Accountant", "6 years", "B.Com, Lucknow University", "Lucknow",
    ["Tally", "GST", "Excel"], 5.0, "Nawab Traders", 4.2, "30 days",
    "TEST: Lucknow · 6 yrs · on-site · full-time · 30 days notice · Tally.",
    ["onsite"], ["full-time"], false],
  ["Rhea D'Souza", 25, "Flutter Developer (Part-time)", "2 years", "B.Tech CSE, Fr. Agnel Mumbai", "Mumbai",
    ["Flutter", "Dart", "Firebase"], 5.0, "Freelance", 4.0, "Immediate",
    "TEST: Mumbai · 2 yrs · remote · part-time · Immediate notice · Flutter.",
    ["remote"], ["part-time"], true],
  ["Omkar Patil", 28, "Machine Learning Engineer", "3 years", "M.Tech AI, COEP Pune", "Pune",
    ["Python", "TensorFlow", "SQL"], 16.0, "Visionary AI", 12.0, "60 days",
    "TEST: Pune · 3 yrs · hybrid · full-time · 60 days notice · Python.",
    ["hybrid"], ["full-time"], false],
];

const MODE = { onsite: "on-site", hybrid: "hybrid", remote: "remote" };
const KIND = { "full-time": "full-time", "part-time": "part-time", internship: "internship", contract: "contract" };
const list = (items) => (items.length > 1 ? `${items.slice(0, -1).join(", ")} or ${items[items.length - 1]}` : items[0]);

/**
 * The About text shown on the card: a normal sentence, not the TEST: cheat
 * sheet (that stays in the row above, for whoever checks the filters).
 */
function aboutOf(row) {
  const [, , role, experience, , city, skills, , company, , notice, , modes, types] = row;
  const who = /fresher/i.test(experience) ? "Fresher" : `${experience} of experience`;
  const where = company && company !== "Fresher" && company !== "Freelance" ? ` Currently at ${company}.` : company === "Freelance" ? " Working as a freelancer." : "";
  const joining = /immediate/i.test(notice) ? "can join immediately" : `${notice} notice period`;
  return `${role} in ${city} (${who}).${where} Strong in ${skills.slice(0, 3).join(", ")}. Open to ${list(modes.map((m) => MODE[m]))} ${list(types.map((t) => KIND[t]))} roles, ${joining}.`;
}

let state = { accounts: [] };
try {
  state = JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
} catch {
  /* first run */
}
const remember = (a) => {
  state.accounts.push(a);
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
};

/** otp -> verify -> signup. Returns null when the account already exists. */
async function createAccount({ email, name }) {
  if (state.accounts.some((a) => a.email === email)) return null;
  const send = await api("POST", "/auth/otp/send", { body: { email } });
  if (send.status === 409) return null;
  must(send, `otp/send ${email}`);
  if (!send.json.otp) throw new Error(`no otp returned for ${email} (is OTP_DEV_FALLBACK on?)`);
  must(await api("POST", "/auth/otp/verify", { body: { email, otp: send.json.otp } }), `otp/verify ${email}`);
  const password = "Demo-" + crypto.randomBytes(9).toString("hex");
  const out = must(await api("POST", "/auth/signup", { body: { name, email, password, role: "candidate" } }), `signup ${email}`);
  const user = out.user || {};
  remember({ email, password, role: "candidate", id: user.uid || user.id, name });
  return { token: out.token };
}

async function seed(row, i) {
  const [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about, modes, types, negotiable] = row;
  const account = await createAccount({ email: emailOf(row), name });
  if (!account) return log(`skip (exists): ${name}`);

  // profileBody() reads the shared demo-row layout and spreads the signup order
  // over modes/negotiable; take its body and put this row's own values on top.
  const demoRow = [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about];
  const { body } = profileBody(demoRow, 100 + i);
  Object.assign(body, { workModes: modes, jobTypes: types, salaryNegotiable: negotiable, about: aboutOf(row) });
  must(await api("PUT", "/candidates/me/profile", { token: account.token, body }), `profile ${name}`);
  must(
    await api("PUT", "/candidates/me/preferences", {
      token: account.token,
      body: { openToWork: true, workModes: modes, jobTypes: types, preferredLocations: [city] },
    }),
    `preferences ${name}`,
  );
  must(await api("PATCH", "/users/me", { token: account.token, body: { profileComplete: true } }), `complete ${name}`);
  log(`ready (${i + 1}/${ROWS.length}): ${name}`);
}

/** --polish: rewrite the About of the already created accounts with the natural text. */
async function polish(row, i) {
  const [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about, modes, types, negotiable] = row;
  const account = state.accounts.find((a) => a.email === emailOf(row));
  if (!account) return log(`no account for ${name}`);
  const login = must(await api("POST", "/auth/login", { body: { email: account.email, password: account.password } }), `login ${name}`);
  const demoRow = [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about];
  const { body } = profileBody(demoRow, 100 + i);
  Object.assign(body, { workModes: modes, jobTypes: types, salaryNegotiable: negotiable, about: aboutOf(row) });
  must(await api("PUT", "/candidates/me/profile", { token: login.token, body }), `profile ${name}`);
  log(`polished (${i + 1}/${ROWS.length}): ${name}`);
}

async function main() {
  log(`target: ${BASE}  state: ${STATE_FILE}  (${state.accounts.length} accounts remembered)`);
  if (process.argv.includes("--polish")) {
    for (const [i, row] of ROWS.entries()) {
      try {
        await polish(row, i);
      } catch (e) {
        log(`FAILED ${row[0]}: ${e.message}`);
      }
    }
    return;
  }
  const health = await api("GET", "/health");
  if (health.status !== 200) throw new Error(`backend not healthy: ${health.status}`);
  for (const [i, row] of ROWS.entries()) {
    try {
      await seed(row, i);
    } catch (e) {
      log(`FAILED ${row[0]}: ${e.message}`);
    }
  }
  log("done.", state.accounts.length, "accounts remembered");
}

main().catch((e) => {
  console.error("Seed failed:", e.message);
  process.exit(1);
});
