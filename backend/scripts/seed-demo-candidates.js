// Seeds 50 realistic demo Job Seeker (candidate) accounts so the recruiter's
// deck has real-looking people to match against. Never creates recruiters,
// jobs, swipes or chats.
//
//   node scripts/seed-demo-candidates.js                          dry run (writes nothing)
//   node scripts/seed-demo-candidates.js --apply                  insert into a LOCAL database
//   node scripts/seed-demo-candidates.js --apply --allow-remote   insert into the database DATABASE_URL points at
//
// Safety:
//   - a non-localhost DATABASE_URL (e.g. the hosted one) is refused unless
//     --allow-remote is passed; NODE_ENV=production is always refused
//   - idempotent: an email that already exists is skipped; for those only the
//     derived match columns (skillsNormalized, experienceYears, noticeDays)
//     are refreshed
//   - everything is written in one transaction (all 50 or nothing)
//   - sends no email, SMS or push; every address is on reserved example.com
//   - the accounts get a random password nobody knows, so they can be seen
//     on the recruiter's deck but cannot be signed into. Set SEED_PASSWORD to
//     make them loginable (local testing only).
//
// To remove them again:
//   DELETE FROM users WHERE email LIKE 'demo.%@example.com' AND role = 'candidate';
// (profiles cascade).

require("dotenv").config();
const crypto = require("crypto");
const bcrypt = require("bcryptjs");
const { PrismaClient } = require("@prisma/client");
const { normalizeSkills, parseExperienceYears, parseNoticeDays } = require("../src/lib/derive");

const PASSWORD = process.env.SEED_PASSWORD || crypto.randomBytes(24).toString("hex");
const EXPECTED_COUNT = 50;
const HOURS_BETWEEN_SIGNUPS = 7; // spreads sign-ups over the last ~two weeks, so "new" means something

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

  // ---- More mobile developers (4)
  ["Ananya Iyer", 24, "Android Developer (Kotlin)", "2 years", "B.Tech Computer Science, SRM Institute of Science and Technology", "Chennai",
    ["Kotlin", "Android", "Jetpack Compose", "Room", "Retrofit"], 9.0, "Tamarind Mobile", 6.5, "30 days",
    "Built a ride-booking app and a grocery app in Kotlin with Jetpack Compose. Care about smooth scrolling and offline-first design. Looking for a product team shipping weekly."],
  ["Rishabh Jain", 27, "iOS Developer (Swift)", "4 years", "B.E. Computer Science, BITS Pilani", "Bengaluru",
    ["Swift", "SwiftUI", "iOS", "Core Data", "Combine"], 18.0, "Mintbox Labs", 14.0, "60 days",
    "Shipped a payments SDK and two consumer iOS apps. Comfortable with SwiftUI, accessibility and App Store release management."],
  ["Divya Pillai", 26, "Flutter Developer", "3 years", "B.Tech Information Technology, Cochin University", "Kochi",
    ["Flutter", "Dart", "Firebase", "Provider", "REST APIs"], 11.0, "Backwater Apps", 8.0, "45 days",
    "Delivered a telemedicine app with video calls and a booking flow. Write widget tests and keep the app size down. Open to remote roles."],
  ["Manish Tiwari", 23, "React Native Developer", "1 year", "B.Tech Computer Science, KIIT Bhubaneswar", "Bhubaneswar",
    ["React Native", "JavaScript", "Redux", "Firebase", "Git"], 5.5, "Odisha Softworks", 3.6, "15 days",
    "Built cross-platform apps for local retail and logistics clients. Quick to pick up new libraries and happy to learn native modules."],

  // ---- DevOps, cloud and data engineering (4)
  ["Gaurav Bhatt", 30, "DevOps Engineer", "5 years", "B.Tech Computer Science, Graphic Era University", "Gurugram",
    ["AWS", "Docker", "Kubernetes", "Terraform", "CI/CD"], 21.0, "Cloudnine Systems", 16.5, "60 days",
    "Own the infrastructure for a SaaS platform: Terraform, EKS and blue-green deployments. Cut cloud spend by 30 percent without hurting uptime."],
  ["Lakshmi Narayanan", 27, "Cloud Engineer", "3 years", "B.E. Computer Science, PSG College of Technology", "Coimbatore",
    ["AWS", "Linux", "Python", "Terraform", "Monitoring"], 14.0, "Kovai Cloudworks", 10.5, "45 days",
    "Migrated on-premise workloads to AWS and set up alerting and runbooks. Looking for a platform engineering team."],
  ["Sahil Arora", 28, "Data Engineer", "4 years", "B.Tech Computer Science, Thapar University", "Gurugram",
    ["Python", "SQL", "Spark", "Airflow", "AWS"], 19.0, "Fractal Metrics", 15.0, "60 days",
    "Build batch and streaming pipelines moving billions of rows a day. Enjoy making data reliable and well documented."],
  ["Bhavna Solanki", 26, "Machine Learning Engineer", "3 years", "M.Tech Data Science, IIIT Hyderabad", "Hyderabad",
    ["Python", "Machine Learning", "TensorFlow", "SQL", "Docker"], 18.0, "Insightloop AI", 14.0, "60 days",
    "Deployed recommendation and demand-forecasting models into production. Interested in MLOps and applied research with a product team."],

  // ---- Product, project and operations (4)
  ["Aarav Sharma", 29, "Product Manager", "5 years", "MBA, IIM Indore", "Mumbai",
    ["Product Strategy", "Roadmapping", "SQL", "User Research", "Agile"], 26.0, "Fintrail", 21.0, "60 days",
    "Grew a lending app from 50k to 600k users. Run discovery with customers, write crisp specs and work closely with engineering and design."],
  ["Ritika Sethi", 27, "Business Analyst", "3 years", "B.Tech Computer Science and MBA, SP Jain", "Mumbai",
    ["SQL", "Excel", "Requirements Gathering", "JIRA", "Power BI"], 12.0, "Northbridge Consulting", 9.0, "45 days",
    "Translate business needs into clear requirements and dashboards. Comfortable with stakeholders at every level."],
  ["Pranav Kulshreshtha", 31, "Project Manager", "7 years", "B.E. Mechanical, MNNIT Allahabad and PMP", "Noida",
    ["Project Management", "Agile", "Scrum", "JIRA", "Stakeholder Management"], 25.0, "Kestrel IT Services", 20.0, "90 days",
    "Delivered 20+ software projects on time with distributed teams. Strong on risk tracking and client communication."],
  ["Aditi Rao", 24, "Scrum Master", "2 years", "B.Tech Information Technology, Manipal Institute of Technology", "Bengaluru",
    ["Scrum", "Agile", "JIRA", "Facilitation", "Coaching"], 10.0, "Orchid Digital", 7.5, "30 days",
    "Help two squads ship predictably with clean retros and honest burndown charts. Certified Scrum Master."],

  // ---- Marketing, sales and content (5)
  ["Simran Kaur", 25, "Digital Marketing Executive", "2 years", "BBA, Chandigarh University", "Chandigarh",
    ["SEO", "Google Ads", "Social Media", "Content Marketing", "Analytics"], 5.5, "Pixel Reach Media", 4.0, "30 days",
    "Run paid and organic campaigns for D2C brands and report on ROAS weekly. Looking for a growth marketing role in a startup."],
  ["Varun Oberoi", 28, "Growth Marketing Manager", "5 years", "MBA Marketing, Symbiosis Pune", "Delhi",
    ["SEO", "Performance Marketing", "Google Analytics", "CRM", "A/B Testing"], 18.0, "Bazaarline", 14.0, "60 days",
    "Scaled acquisition from 5k to 80k monthly signups while lowering CAC. Own the funnel from ad to activation."],
  ["Ishita Bose", 26, "Content Writer", "3 years", "MA English, Jadavpur University", "Kolkata",
    ["Content Writing", "SEO", "Copywriting", "Editing", "Research"], 6.5, "Wordcraft Studio", 4.8, "30 days",
    "Write blogs, product pages and email sequences that rank and convert. Comfortable with technical topics."],
  ["Kunal Mehra", 27, "Sales Executive (B2B SaaS)", "3 years", "BBA, Christ University", "Bengaluru",
    ["B2B Sales", "CRM", "Lead Generation", "Negotiation", "Cold Calling"], 8.0, "Cloudreach Software", 6.0, "30 days",
    "Closed 1.2 crore in annual contracts last year and consistently beat quota. Comfortable with demos and long sales cycles."],
  ["Payal Gandhi", 24, "Social Media Manager", "2 years", "B.Com, HR College Mumbai", "Mumbai",
    ["Social Media", "Content Creation", "Canva", "Instagram", "Analytics"], 5.0, "Glow Collective", 3.8, "15 days",
    "Grew a beauty brand's Instagram from 12k to 90k followers. Plan content calendars and work with creators."],

  // ---- HR, finance and support (4)
  ["Nandini Verma", 28, "HR Executive (Talent Acquisition)", "4 years", "MBA HR, Xavier Institute Bhubaneswar", "Pune",
    ["Recruitment", "Sourcing", "Interviewing", "HR Operations", "LinkedIn Recruiter"], 8.5, "TalentBridge India", 6.5, "30 days",
    "Closed 150+ tech and non-tech roles per year. Know how to source passive candidates and keep hiring managers aligned."],
  ["Chirag Shah", 29, "Accountant", "5 years", "B.Com and CA Inter, Gujarat University", "Ahmedabad",
    ["Tally", "GST", "Accounting", "Excel", "Financial Reporting"], 6.5, "Shah and Associates", 5.0, "30 days",
    "Handle books, GST filing and month-end closing for a mid-size trading company. Detail oriented and deadline driven."],
  ["Ayesha Siddiqui", 25, "Customer Support Executive", "2 years", "B.A., Aligarh Muslim University", "Lucknow",
    ["Customer Support", "Communication", "Zendesk", "Problem Solving", "CRM"], 3.8, "Careline Solutions", 2.8, "Immediate",
    "Resolve customer issues over chat and email with high satisfaction scores. Calm under pressure and good with escalations."],
  ["Sumit Pandey", 26, "Operations Executive", "3 years", "BBA, Amity University Lucknow", "Lucknow",
    ["Operations", "Excel", "Logistics", "Vendor Management", "Reporting"], 5.5, "Swift Supply Co", 4.2, "30 days",
    "Coordinate vendors and daily dispatch reports for a regional warehouse. Looking for a growth role in operations."],

  // ---- Additional engineers and freshers (4)
  ["Tushar Wagh", 22, "Junior Flutter Developer", "Fresher", "B.Tech Computer Science, MIT World Peace University", "Pune",
    ["Flutter", "Dart", "Firebase", "Git", "REST APIs"], 4.0, "Fresher", 0, "Immediate",
    "Published two Flutter apps while in college, one with 5k downloads. Eager to join a team that mentors and reviews code."],
  ["Pallavi Hegde", 23, "Junior Backend Developer", "6 months", "B.E. Computer Science, NMAMIT Nitte", "Mangaluru",
    ["Node.js", "Express", "MongoDB", "REST APIs", "Git"], 4.5, "Coastal Digital (intern)", 1.8, "Immediate",
    "Completed a six-month backend internship building REST APIs and writing tests. Looking for a junior role in a product team."],
  ["Ojas Kelkar", 28, "Senior Full Stack Engineer", "6 years", "B.Tech Computer Science, IIT Roorkee", "Pune",
    ["React", "Node.js", "TypeScript", "AWS", "PostgreSQL"], 30.0, "Helio Technologies", 24.0, "90 days",
    "Architected a booking platform handling 50k orders a day. Mentor engineers and drive technical design reviews."],
  ["Zoya Ansari", 25, "Software Engineer (Java)", "2 years", "B.Tech Computer Science, Jamia Millia Islamia", "Delhi",
    ["Java", "Spring Boot", "MySQL", "REST APIs", "JUnit"], 9.0, "Capital Stack", 6.8, "30 days",
    "Develop and maintain loan-processing services with strong unit-test coverage. Looking to grow into a backend lead."],
];

// Placeholder portraits (randomuser.me serves these for exactly this purpose),
// picked by the first name's gender so the deck looks like real people. The
// number is fixed per candidate, so re-running never changes anyone's photo.
const FEMALE_FIRST_NAMES = new Set([
  "riya", "sneha", "priya", "sana", "pooja", "isha", "tanvi", "meera", "neha", "kavya", "shreya",
  "ananya", "divya", "bhavna", "lakshmi", "ritika", "aditi", "simran", "ishita", "payal", "nandini",
  "ayesha", "pallavi", "zoya",
]);

function photoFor(name, index) {
  const female = FEMALE_FIRST_NAMES.has(name.toLowerCase().split(/\s+/)[0]);
  const portrait = 11 + ((index * 7) % 80); // 11..90, distinct per index within each gender
  return `https://randomuser.me/api/portraits/${female ? "women" : "men"}/${portrait}.jpg`;
}

function emailFor(name) {
  const slug = name.toLowerCase().replace(/[^a-z\s]/g, "").trim().split(/\s+/);
  return `demo.${slug[0]}.${slug[slug.length - 1]}@example.com`;
}

async function main() {
  const apply = process.argv.includes("--apply");
  const allowRemote = process.argv.includes("--allow-remote");

  const url = new URL(process.env.DATABASE_URL || "postgresql://invalid");
  const localHosts = ["localhost", "127.0.0.1", "::1"];
  const isLocal = localHosts.includes(url.hostname);
  if (process.env.NODE_ENV === "production") {
    console.error("Refusing to seed: NODE_ENV=production.");
    process.exit(1);
  }
  if (!isLocal && !allowRemote) {
    console.error(`Refusing to seed: database host=${url.hostname} is not local. Pass --allow-remote if you really mean to seed this database.`);
    process.exit(1);
  }
  if (CANDIDATES.length !== EXPECTED_COUNT) throw new Error(`Expected ${EXPECTED_COUNT} candidates, found ${CANDIDATES.length}`);

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
    console.log(`Already present: ${existing.size} (match columns refreshed)  |  to create: ${toCreate.length}`);

    if (!apply) {
      toCreate.forEach((c) => console.log(`  would create ${emailFor(c[0]).padEnd(40)} ${c[2]}`));
      console.log("Dry run only. Re-run with --apply to insert.");
      return;
    }

    const passwordHash = await bcrypt.hash(PASSWORD, 10);
    const now = Date.now();
    await prisma.$transaction(async (tx) => {
      // Index 0 is the newest sign-up; the list order then is "newest first".
      for (const [index, c] of CANDIDATES.entries()) {
        const [name, age, role, experience, qualification, location, skills, expected, company, currentLpa, notice, about] = c;
        const email = emailFor(name);
        const derived = {
          skillsNormalized: normalizeSkills(skills),
          experienceYears: parseExperienceYears(experience),
          noticeDays: parseNoticeDays(notice),
        };
        const photoUrl = photoFor(name, index);

        if (existing.has(email)) {
          await tx.candidateProfile.updateMany({ where: { user: { email } }, data: { ...derived, photoUrl } });
          continue;
        }

        await tx.user.create({
          data: {
            name,
            email,
            passwordHash,
            role: "candidate",
            profileComplete: true,
            emailVerified: true,
            createdAt: new Date(now - index * HOURS_BETWEEN_SIGNUPS * 3600 * 1000),
            candidateProfile: {
              create: {
                age,
                qualification,
                experience,
                desiredRole: role,
                location,
                skills,
                ...derived,
                photoUrl,
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

// Run as a script; `require`d by seed-demo-via-api.js for the candidate data.
if (require.main === module) {
  main().catch((e) => {
    console.error("Seed failed:", e.message.split("\n")[0]);
    process.exit(1);
  });
}

module.exports = { CANDIDATES, emailFor, photoFor };
