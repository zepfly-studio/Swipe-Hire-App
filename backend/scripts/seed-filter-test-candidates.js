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

// name, age, role, experience, degree + college, city, skills, expected LPA,
// current company, current LPA, notice, about, work modes, job types, negotiable,
// [education level override: 10th / 12th / PhD, which the degree text cannot say]
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
  // ---- education level / degree / college filters
  ["Rohit Chauhan", 22, "Computer Hardware Technician", "2 years", "Diploma in Computer Engineering, Government Polytechnic Jaipur", "Jaipur",
    ["Hardware", "Networking", "Troubleshooting"], 3.0, "Pinkcity Computers", 2.4, "15 days",
    "TEST: Diploma · Jaipur · 2 yrs · on-site · full-time.", ["onsite"], ["full-time"], false],
  ["Salman Qureshi", 24, "Web Designer", "3 years", "Diploma in Information Technology, Government Polytechnic Lucknow", "Lucknow",
    ["HTML", "CSS", "Photoshop"], 4.0, "Awadh Digital", 3.2, "30 days",
    "TEST: Diploma · Lucknow · 3 yrs · hybrid · full-time or part-time.", ["hybrid"], ["full-time", "part-time"], true],
  ["Kajal Rawat", 20, "Customer Support Executive", "1 year", "Senior Secondary (CBSE), Delhi Public School", "Delhi",
    ["Communication", "CRM", "Typing"], 2.4, "CallDesk", 1.9, "Immediate",
    "TEST: 12th · Delhi · 1 yr · on-site · full-time.", ["onsite"], ["full-time"], false, "12th"],
  ["Sandeep Yadav", 25, "Delivery Coordinator", "3 years", "Senior Secondary (RBSE), Government Senior Secondary School Jaipur", "Jaipur",
    ["Logistics", "Excel", "Communication"], 2.8, "Swift Couriers", 2.2, "15 days",
    "TEST: 12th · Jaipur · 3 yrs · on-site · full-time or contract.", ["onsite"], ["full-time", "contract"], true, "12th"],
  ["Ravi Meena", 28, "Warehouse Associate", "4 years", "Secondary (RBSE), Government School Dausa", "Jaipur",
    ["Packing", "Inventory", "Forklift"], 1.8, "Gati Storage", 1.5, "Immediate",
    "TEST: 10th · Jaipur · 4 yrs · on-site · full-time.", ["onsite"], ["full-time"], false, "10th"],
  ["Bhavna Iyer", 36, "Research Scientist (AI)", "7 years", "PhD Computer Science, IISc Bengaluru", "Bengaluru",
    ["Python", "Machine Learning", "PyTorch", "Research"], 30.0, "Neuronest Labs", 26.0, "90 days",
    "TEST: PhD · IISc · Bengaluru · 7 yrs · hybrid · full-time or contract.", ["hybrid"], ["full-time", "contract"], false, "PhD"],
  ["Karthik Subramanian", 30, "Embedded Engineer", "4 years", "M.Tech Embedded Systems, NIT Trichy", "Chennai",
    ["C", "Embedded Systems", "RTOS"], 14.0, "Chola Devices", 11.0, "60 days",
    "TEST: Post Graduate · M.Tech · NIT Trichy · Chennai · 4 yrs · on-site.", ["onsite"], ["full-time"], false],
  ["Tanvi Arora", 33, "HR Manager", "7 years", "MBA Human Resources, XLRI Jamshedpur", "Delhi",
    ["Recruitment", "Payroll", "Employee Relations"], 16.0, "Zenith People", 13.0, "60 days",
    "TEST: Post Graduate · MBA · XLRI · Delhi · 7 yrs · hybrid.", ["hybrid"], ["full-time"], false],
  ["Arnav Khanna", 26, "Finance Analyst", "3 years", "B.Com (Hons), Shri Ram College of Commerce", "Delhi",
    ["Excel", "Financial Modelling", "Tally"], 7.0, "Capitol Finserv", 5.8, "30 days",
    "TEST: Graduate · B.Com · SRCC · Delhi · 3 yrs · on-site.", ["onsite"], ["full-time"], false],
  ["Pooja Rawat", 27, "Maths Tutor (Part-time)", "2 years", "B.Sc Mathematics, University of Rajasthan", "Jaipur",
    ["Teaching", "Mathematics", "Communication"], 2.0, "Freelance", 1.6, "Immediate",
    "TEST: Graduate · B.Sc · Jaipur · 2 yrs · remote · part-time.", ["remote"], ["part-time"], true],
  ["Yash Vardhan", 21, "Software Engineering Intern", "Fresher", "BCA, Manipal University Jaipur", "Jaipur",
    ["Java", "Git", "SQL"], 1.2, "Fresher", 0, "Immediate",
    "TEST: Graduate · BCA · Manipal University Jaipur · fresher · remote or hybrid · internship.", ["remote", "hybrid"], ["internship"], true],
  // ---- job titles people search for (role / job title filter)
  ["Aman Verma", 24, "Web Developer", "2 years", "BCA, Rajasthan University", "Jaipur",
    ["HTML", "CSS", "JavaScript", "React"], 6.0, "Pixel Crafts", 4.5, "30 days",
    "TEST: Web Developer · Jaipur · 2 yrs · hybrid · full-time.", ["hybrid"], ["full-time"], false],
  ["Neha Bajaj", 26, "Web Developer", "4 years", "B.Tech Information Technology, Pune University", "Pune",
    ["PHP", "Laravel", "MySQL", "JavaScript"], 9.0, "Webwise Solutions", 7.0, "60 days",
    "TEST: Web Developer · Pune · 4 yrs · on-site · full-time.", ["onsite"], ["full-time"], true],
  ["Rishabh Saini", 22, "Web Developer (Freelance)", "1 year", "Diploma in Computer Science, Government Polytechnic Jaipur", "Jaipur",
    ["HTML", "CSS", "WordPress"], 3.0, "Freelance", 2.0, "Immediate",
    "TEST: Web Developer · Jaipur · 1 yr · remote · contract or part-time.", ["remote"], ["contract", "part-time"], true],
  ["Rishi Kapoor", 29, "Data Scientist", "4 years", "M.Tech Data Science, IIT Madras", "Bengaluru",
    ["Python", "Machine Learning", "SQL", "TensorFlow"], 22.0, "Insightloop", 17.0, "60 days",
    "TEST: Data Scientist · Bengaluru · 4 yrs · hybrid · full-time.", ["hybrid"], ["full-time"], false],
  ["Meera Pillai", 27, "Data Scientist", "2 years", "M.Sc Statistics, University of Hyderabad", "Hyderabad",
    ["Python", "R", "Statistics", "Pandas"], 12.0, "Healthmetrics", 9.0, "30 days",
    "TEST: Data Scientist · Hyderabad · 2 yrs · remote · full-time.", ["remote"], ["full-time"], false],
  ["Vinod Rathore", 32, "Network Engineer", "6 years", "B.Tech Electronics and Communication, MNIT Jaipur", "Jaipur",
    ["CCNA", "Networking", "Firewalls", "Routing"], 8.0, "Maru Telecom", 6.5, "30 days",
    "TEST: Network Engineer · Jaipur · 6 yrs · on-site · full-time.", ["onsite"], ["full-time"], false],
  ["Aditi Kulkarni", 28, "Cyber Security Analyst", "3 years", "B.Tech Computer Science, COEP Pune", "Pune",
    ["Cyber Security", "SIEM", "Penetration Testing", "Linux"], 14.0, "Sentinel Infosec", 11.0, "60 days",
    "TEST: Cyber Security Analyst · Pune · 3 yrs · hybrid · full-time.", ["hybrid"], ["full-time"], false],
  ["Harshit Jain", 25, "WordPress Developer", "3 years", "BCA, Devi Ahilya University Indore", "Indore",
    ["WordPress", "PHP", "WooCommerce", "CSS"], 5.5, "Webnest", 4.2, "15 days",
    "TEST: WordPress Developer · Indore · 3 yrs · remote · full-time or contract.", ["remote"], ["full-time", "contract"], true],
  ["Ankit Tripathi", 27, "PHP Developer", "4 years", "MCA, Lucknow University", "Lucknow",
    ["PHP", "Laravel", "MySQL", "REST APIs"], 7.5, "Nawab Soft", 6.0, "30 days",
    "TEST: PHP Developer · Lucknow · 4 yrs · on-site · full-time.", ["onsite"], ["full-time"], false],
  ["Gopal Reddy", 30, ".NET Developer", "6 years", "B.Tech Computer Science, JNTU Hyderabad", "Hyderabad",
    ["C#", ".NET", "SQL Server", "Azure"], 16.0, "Deccan Systems", 13.0, "90 days",
    "TEST: .NET Developer · Hyderabad · 6 yrs · hybrid · full-time.", ["hybrid"], ["full-time"], false],
  ["Karan Malhotra", 26, "Video Editor", "3 years", "B.A. Mass Communication, Mumbai University", "Mumbai",
    ["Premiere Pro", "After Effects", "Video Editing"], 5.0, "Freelance", 4.0, "Immediate",
    "TEST: Video Editor · Mumbai · 3 yrs · remote · part-time or contract.", ["remote"], ["part-time", "contract"], true],
  ["Divya Nair", 25, "Mobile App Developer", "2 years", "B.Tech Computer Science, Cochin University", "Kochi",
    ["Flutter", "React Native", "Firebase"], 8.0, "Spice Coast Apps", 6.2, "30 days",
    "TEST: Mobile App Developer · Kochi · 2 yrs · hybrid · full-time.", ["hybrid"], ["full-time"], false],
  ["Siddharth Rao", 29, "Software Engineer", "5 years", "B.E. Information Science, RV College of Engineering", "Bengaluru",
    ["Java", "Python", "System Design", "AWS"], 20.0, "Orbitron", 16.0, "60 days",
    "TEST: Software Engineer · Bengaluru · 5 yrs · remote or hybrid · full-time.", ["remote", "hybrid"], ["full-time"], false],
  ["Rahul Dubey", 24, "Technical Support Engineer", "2 years", "B.Sc Information Technology, Noida International University", "Noida",
    ["Troubleshooting", "Linux", "SQL", "Customer Support"], 4.5, "Helpline Tech", 3.6, "15 days",
    "TEST: Technical Support Engineer · Noida · 2 yrs · on-site · full-time.", ["onsite"], ["full-time"], false],
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
  const [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about, modes, types, negotiable, level] = row;
  const account = await createAccount({ email: emailOf(row), name });
  if (!account) return log(`skip (exists): ${name}`);

  // profileBody() reads the shared demo-row layout and spreads the signup order
  // over modes/negotiable; take its body and put this row's own values on top.
  const demoRow = [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about];
  const { body } = profileBody(demoRow, 100 + i);
  Object.assign(body, { workModes: modes, jobTypes: types, salaryNegotiable: negotiable, about: aboutOf(row) });
  if (level) body.qualification = level;
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
  const [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about, modes, types, negotiable, level] = row;
  const account = state.accounts.find((a) => a.email === emailOf(row));
  if (!account) return log(`no account for ${name}`);
  const login = must(await api("POST", "/auth/login", { body: { email: account.email, password: account.password } }), `login ${name}`);
  const demoRow = [name, age, role, experience, qualification, city, skills, expected, company, currentLpa, notice, about];
  const { body } = profileBody(demoRow, 100 + i);
  Object.assign(body, { workModes: modes, jobTypes: types, salaryNegotiable: negotiable, about: aboutOf(row) });
  if (level) body.qualification = level;
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
