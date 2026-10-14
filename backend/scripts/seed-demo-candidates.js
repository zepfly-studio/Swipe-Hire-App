// Seeds 25 realistic demo Job Seeker (candidate) accounts into the LOCAL
// development database. Never creates recruiters, jobs, swipes or chats.
//
//   node scripts/seed-demo-candidates.js            dry run (writes nothing)
//   node scripts/seed-demo-candidates.js --apply    insert for real
//
// Safety:
//   - refuses to run when NODE_ENV=production or DATABASE_URL isn't localhost
//   - idempotent: an email that already exists is skipped, never updated
//   - everything is written in one transaction (all 25 or nothing)
//   - sends no email, SMS or push; every address is on reserved example.com
//
// Sign in with any seeded email and the password below (default user123,
// override with SEED_PASSWORD). To remove them again:
//   DELETE FROM users WHERE email LIKE 'demo.%@example.com' AND role = 'candidate';
// (profiles cascade).

require("dotenv").config();
const bcrypt = require("bcryptjs");
const { PrismaClient } = require("@prisma/client");

const PASSWORD = process.env.SEED_PASSWORD || "user123";

// name, age, role, experience, qualification, location, skills, expectedLpa,
// currentCompany, currentLpa, notice, about
const CANDIDATES = [
  // ---- Freshers (4)
  ["Riya Patel", 22, "Junior Software Developer", "Fresher", "B.Tech Computer Science, Nirma University", "Ahmedabad",
    ["Java", "SQL", "Git", "Data Structures", "OOP"], 4.0, "Fresher", 0, "Immediate",
    "2026 graduate with two internships in backend testing. Solid on data structures and Java, looking for a first full-time role where I can learn from senior engineers. Open to relocating."],
  ["Karan Singh Rathore", 21, "Junior Web Developer", "Fresher", "BCA, Manipal University Jaipur", "Jaipur",
    ["HTML", "CSS", "JavaScript", "React", "Git"], 3.5, "Fresher", 0, "Immediate",
    "Built a portfolio site, a quiz app and a small e-commerce front end during college. Quick learner who enjoys turning designs into clean, responsive pages. Prefer a team that does code reviews."],
  ["Sneha Nair", 23, "Junior Data Analyst", "Fresher", "B.Sc Information Technology, University of Mumbai", "Mumbai",
    ["Excel", "SQL", "Power BI", "Python", "Statistics"], 3.6, "Fresher", 0, "Immediate",
    "Completed a data analytics certification and a retail sales dashboard project. Comfortable cleaning messy data and presenting findings to non-technical people. Hybrid or on-site both fine."],
  ["Mohit Verma", 22, "Junior Python Developer", "Fresher", "B.Tech Electronics and Communication, IET DAVV", "Indore",
    ["Python", "Django", "SQL", "REST APIs", "Git"], 3.8, "Fresher", 0, "15 days",
    "Self-taught Python developer with a Django expense-tracker and a few open-source bug fixes. Looking for a junior backend role and mentorship."],

  // ---- Flutter developers (4)
  ["Arjun Mehta", 26, "Flutter Developer", "3 years", "B.Tech Computer Science, VIT Pune", "Pune",
    ["Flutter", "Dart", "Firebase", "Riverpod", "REST APIs"], 12.0, "Pixelwave Technologies", 9.0, "60 days",
    "Shipped four consumer apps to Play Store and App Store, the biggest with 200k downloads. Strong on state management and app performance. Looking for a product company with ownership of mobile releases."],
  ["Priya Deshmukh", 25, "Flutter Developer", "2 years", "MCA, Savitribai Phule Pune University", "Pune",
    ["Flutter", "Dart", "Bloc", "SQLite", "Google Maps API"], 8.5, "Nimbus Apps", 6.0, "30 days",
    "Built logistics and delivery tracking apps with live maps and push notifications. Care about clean architecture and widget tests. Remote or hybrid preferred."],
  ["Rahul Khanna", 29, "Senior Flutter Developer", "5 years", "BE Information Technology, PES University", "Bengaluru",
    ["Flutter", "Dart", "Kotlin", "CI/CD", "Clean Architecture"], 22.0, "BrightPath Software", 17.0, "90 days",
    "Led a team of four mobile engineers and moved a legacy native app to Flutter. Experienced with release pipelines, code reviews and hiring. Looking for a tech lead role."],
  ["Sana Qureshi", 24, "Flutter Developer", "1.5 years", "B.Tech Computer Science, JNTU Hyderabad", "Hyderabad",
    ["Flutter", "Dart", "GetX", "Firebase", "Figma"], 7.0, "Zenith Infosystems", 4.8, "30 days",
    "Worked on a fintech wallet app and an education app. Good eye for UI and comfortable translating Figma designs pixel by pixel. Want to grow into backend integration too."],

  // ---- Backend developers (3)
  ["Vikram Reddy", 28, "Backend Developer (Node.js)", "4 years", "B.Tech Computer Science, Osmania University", "Hyderabad",
    ["Node.js", "Express", "PostgreSQL", "Redis", "Docker"], 16.0, "CodeCrest Solutions", 12.5, "60 days",
    "Designed REST APIs serving a million requests a day and cut average response time by 40 percent with caching and query tuning. Looking for a role with system design ownership."],
  ["Deepak Joshi", 31, "Java Backend Engineer", "6 years", "BE Computer Engineering, Government College of Engineering Nagpur", "Nagpur",
    ["Java", "Spring Boot", "Microservices", "Kafka", "MySQL"], 24.0, "Orbit Digital", 19.0, "90 days",
    "Built payment and order-management microservices in Spring Boot. Comfortable with event-driven design and production on-call. Interested in senior or lead roles."],
  ["Nikhil Gupta", 27, "Backend Developer", "3 years", "B.Tech Information Technology, Delhi Technological University", "Noida",
    ["Node.js", "TypeScript", "PostgreSQL", "AWS", "Prisma"], 14.0, "Lumina Tech", 10.0, "30 days",
    "Enjoy database design and API reliability. Moved a monolith to modular services and set up monitoring with alerts. Open to Delhi NCR or remote."],

  // ---- Full stack developers (3)
  ["Aditya Kulkarni", 27, "Full Stack Developer", "3 years", "B.E. Computer Engineering, College of Engineering Pune", "Pune",
    ["React", "Node.js", "MongoDB", "TypeScript", "Tailwind CSS"], 13.0, "Kiteworks Labs", 10.0, "45 days",
    "MERN developer who has taken features from idea to production alone. Like startups where I can touch both the UI and the database."],
  ["Pooja Bansal", 28, "Full Stack Developer", "4 years", "B.Tech Computer Science, Amity University", "Gurugram",
    ["React", "Node.js", "PostgreSQL", "GraphQL", "Docker"], 17.0, "Vertex Cloudworks", 13.0, "60 days",
    "Built a multi-tenant SaaS dashboard end to end, including billing and role-based access. Strong in GraphQL and testing. Looking for a product team."],
  ["Harsh Agarwal", 25, "Full Stack Developer", "2 years", "B.Tech Computer Science, LNMIIT Jaipur", "Jaipur",
    ["Next.js", "Python", "Django", "PostgreSQL", "Tailwind CSS"], 9.0, "Saffron Softech", 6.5, "30 days",
    "Worked on an HR portal and an inventory system. Like clean APIs and fast pages. Looking to move to a bigger team with real engineering process."],

  // ---- UI/UX designers (3)
  ["Isha Kapoor", 27, "UI/UX Designer", "3 years", "B.Des Interaction Design, NID Ahmedabad", "Delhi",
    ["Figma", "User Research", "Prototyping", "Design Systems", "Usability Testing"], 12.0, "Studio Mosaic", 9.0, "45 days",
    "Designed onboarding and checkout flows that improved conversion by 18 percent. Run user interviews and turn findings into clear specs for engineers."],
  ["Tanvi Joshi", 30, "Senior Product Designer", "5 years", "M.Des, IDC School of Design IIT Bombay", "Mumbai",
    ["Figma", "Design Systems", "Product Strategy", "Wireframing", "Accessibility"], 20.0, "Bluebird Digital", 16.0, "60 days",
    "Own the design system for a lending app used by 2 million people. Work closely with product managers and mentor junior designers."],
  ["Rohan Das", 25, "UI Designer", "2 years", "B.Des Visual Communication, Pearl Academy", "Kolkata",
    ["Figma", "Adobe XD", "Illustrator", "Motion Design", "Responsive Design"], 7.5, "Inkwell Creative", 5.5, "30 days",
    "Visual designer for mobile and web with a strong eye for typography and colour. Comfortable handing off assets and working with Flutter developers."],

  // ---- Data analysts (3)
  ["Meera Krishnan", 26, "Data Analyst", "3 years", "B.Sc Statistics, Loyola College Chennai", "Chennai",
    ["SQL", "Power BI", "Tableau", "Excel", "Python"], 10.0, "Anvaya Analytics", 7.5, "45 days",
    "Build weekly business dashboards for a retail chain and automate reports that used to take two days. Like asking why numbers moved, not only showing them."],
  ["Siddharth Malhotra", 28, "Data Analyst", "4 years", "B.Tech Mathematics and Computing, NIT Trichy", "Bengaluru",
    ["Python", "SQL", "Pandas", "Looker", "A/B Testing"], 15.0, "Quantiva", 12.0, "60 days",
    "Run experiment analysis for a subscription product and built churn and funnel models. Want a role closer to product decisions."],
  ["Neha Saxena", 24, "Business Data Analyst", "2 years", "B.Com, Lucknow University and Google Data Analytics Certificate", "Lucknow",
    ["Excel", "SQL", "Looker Studio", "Google Sheets", "Reporting"], 6.0, "Gomti Financial Services", 4.2, "30 days",
    "Handle MIS reporting and monthly performance packs for the finance team. Looking to move into a tech company and grow into analytics engineering."],

  // ---- Python developers (2)
  ["Amit Choudhary", 29, "Python Developer", "4 years", "B.Tech Computer Science, Medi-Caps University", "Indore",
    ["Python", "Django", "FastAPI", "Celery", "PostgreSQL"], 15.0, "Rasoi Tech", 11.5, "60 days",
    "Built order and notification services in FastAPI and Django REST. Care about test coverage and clear documentation."],
  ["Kavya Rao", 25, "Python Automation Engineer", "2 years", "B.E. Information Science, RV College of Engineering", "Bengaluru",
    ["Python", "Selenium", "Pytest", "Airflow", "AWS"], 9.5, "Helix Systems", 7.0, "30 days",
    "Write automation and data pipeline scripts that remove manual work. Looking for a team where backend and data engineering overlap."],

  // ---- React developers (2)
  ["Shreya Menon", 27, "React Developer", "3 years", "B.Tech Computer Science, CUSAT Kochi", "Kochi",
    ["React", "TypeScript", "Next.js", "Redux Toolkit", "Jest"], 13.5, "Malabar Digital", 10.0, "45 days",
    "Build accessible, fast interfaces and care about component quality and tests. Led the migration of a large app from JavaScript to TypeScript."],
  ["Yash Thakur", 25, "Frontend Developer (React)", "2 years", "B.Tech Information Technology, UIET Panjab University", "Chandigarh",
    ["React", "JavaScript", "Redux", "Tailwind CSS", "REST APIs"], 8.0, "Punjab Webcraft", 5.8, "30 days",
    "Develop dashboards and landing pages for e-commerce clients. Looking for a product company with a proper design system."],

  // ---- QA engineer (1)
  ["Farhan Sheikh", 28, "QA Engineer", "4 years", "B.Tech Computer Science, Muffakham Jah College of Engineering", "Hyderabad",
    ["Selenium", "Postman", "API Testing", "Cypress", "JIRA"], 11.0, "Deccan Quality Labs", 8.5, "45 days",
    "Own regression suites for a banking web app and automate API checks. Comfortable writing test plans and working with developers to reproduce bugs."],
];

function emailFor(name) {
  const slug = name.toLowerCase().replace(/[^a-z\s]/g, "").trim().split(/\s+/);
  return `demo.${slug[0]}.${slug[slug.length - 1]}@example.com`;
}

async function main() {
  const apply = process.argv.includes("--apply");

  const url = new URL(process.env.DATABASE_URL || "postgresql://invalid");
  const localHosts = ["localhost", "127.0.0.1", "::1"];
  if (process.env.NODE_ENV === "production" || !localHosts.includes(url.hostname)) {
    console.error(`Refusing to seed: NODE_ENV=${process.env.NODE_ENV || "(unset)"}, database host=${url.hostname}. Only a local development database is allowed.`);
    process.exit(1);
  }
  if (CANDIDATES.length !== 25) throw new Error(`Expected 25 candidates, found ${CANDIDATES.length}`);

  const emails = CANDIDATES.map((c) => emailFor(c[0]));
  if (new Set(emails).size !== emails.length) throw new Error("Duplicate email in seed data");

  const prisma = new PrismaClient();
  try {
    const before = {
      candidates: await prisma.user.count({ where: { role: "candidate" } }),
      recruiters: await prisma.user.count({ where: { role: "recruiter" } }),
    };
    const existing = new Set((await prisma.user.findMany({ where: { email: { in: emails } }, select: { email: true } })).map((u) => u.email));
    const toCreate = CANDIDATES.filter((c) => !existing.has(emailFor(c[0])));

    console.log(`Database: ${url.hostname}/${url.pathname.slice(1)}  |  mode: ${apply ? "APPLY" : "DRY RUN"}`);
    console.log(`Before: ${before.candidates} candidates, ${before.recruiters} recruiters`);
    console.log(`Already present (skipped): ${existing.size}  |  to create: ${toCreate.length}`);

    if (!apply) {
      toCreate.forEach((c) => console.log(`  would create ${emailFor(c[0]).padEnd(40)} ${c[2]}`));
      console.log("Dry run only. Re-run with --apply to insert.");
      return;
    }

    const passwordHash = await bcrypt.hash(PASSWORD, 10);
    await prisma.$transaction(async (tx) => {
      for (const [name, age, role, experience, qualification, location, skills, expected, company, currentLpa, notice, about] of toCreate) {
        await tx.user.create({
          data: {
            name,
            email: emailFor(name),
            passwordHash,
            role: "candidate",
            profileComplete: true,
            emailVerified: true,
            candidateProfile: {
              create: {
                age,
                qualification,
                experience,
                desiredRole: role,
                location,
                skills,
                expectedSalaryLpa: expected,
                noticePeriod: notice,
                about,
                currentCompany: company,
                currentSalaryLpa: currentLpa,
              },
            },
          },
        });
      }
    });

    const after = {
      candidates: await prisma.user.count({ where: { role: "candidate" } }),
      recruiters: await prisma.user.count({ where: { role: "recruiter" } }),
    };
    console.log(`After:  ${after.candidates} candidates (+${after.candidates - before.candidates}), ${after.recruiters} recruiters (+${after.recruiters - before.recruiters})`);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error("Seed failed:", e.message.split("\n")[0]);
  process.exit(1);
});
