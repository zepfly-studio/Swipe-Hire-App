// Pure-function tests for the candidate side (phase 1): resume parser,
// taxonomy and profile validation. No database, no network.

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { extractProfile } = require("../src/lib/resumeParser");
const taxonomy = require("../src/lib/taxonomy");
const { parseProfileBody, parsePreferencesBody, FieldError } = require("../src/lib/candidateProfile");

const NOW = new Date("2026-10-15T00:00:00Z");

const RESUME = `Rahul Sharma
Full Stack Developer
rahul.sharma@gmail.com | +91 98765 43210 | Jaipur, Rajasthan

Professional Summary
Full Stack Developer with 3+ years of experience building web apps in React and Node.js.

Experience
Software Engineer
Infosys Pvt Ltd Jan 2021 - Present
- Built REST API using Node.js and MongoDB
Web Developer Intern
Acme Technologies | Jun 2020 - Dec 2020

Education
B.Tech in Computer Science, Rajasthan Technical University, Kota 2016 - 2020
CGPA 8.2
Senior Secondary (12th) - Kendriya Vidyalaya School, CBSE 2016

Skills
HTML, CSS, Java Script, React, Node.js, MongoDB, Git, AWS, Python, Figma, Communication

Languages
Hindi, English
`;

describe("resume parser", () => {
  it("finds phone, skills, degree, college, role, city, experience and current job", () => {
    const f = extractProfile(RESUME, { now: NOW });
    assert.equal(f.phone, "+919876543210");
    assert.equal(f.degree, "B.Tech (CSE)");
    assert.equal(f.qualification, "Graduate");
    assert.equal(f.graduationYear, 2020);
    assert.equal(f.college, "Rajasthan Technical University");
    assert.equal(f.desiredRole, "Full Stack Developer");
    assert.equal(f.location, "Jaipur");
    assert.equal(f.experienceYears, 3);
    assert.equal(f.currentCompany, "Infosys Pvt Ltd");
    assert.equal(f.currentPost, "Software Engineer");
    for (const skill of ["React", "Node.js", "MongoDB", "JavaScript", "Python", "Figma"]) {
      assert.ok(f.skills.includes(skill), `missing ${skill}`);
    }
  });

  it("reads 'Java Script' as JavaScript, keeps Java apart, and skips spoken languages", () => {
    const f = extractProfile("Skills\nJava Script, Java, Spring Boot\n\nLanguages\nHindi, English, Tamil", { now: NOW });
    assert.ok(f.skills.includes("JavaScript"));
    assert.ok(f.skills.includes("Java"));
    assert.ok(!f.skills.includes("Hindi"));
    assert.ok(!f.skills.includes("English"));
  });

  it("returns at most 15 skills and only the fields it found", () => {
    const many = "Skills\n" + taxonomy.SKILLS.slice(0, 60).join(", ");
    assert.ok(extractProfile(many, { now: NOW }).skills.length <= 15);
    assert.deepEqual(extractProfile("", { now: NOW }), {});
    assert.deepEqual(extractProfile("   \n  ", { now: NOW }), {});
    assert.deepEqual(extractProfile("nothing useful here at all", { now: NOW }), {});
  });

  it("sums date ranges when no experience is stated, merging overlaps and rounding down to 0.5", () => {
    const text = "Work Experience\nDeveloper, Alpha Pvt Ltd (Jan 2020 - Dec 2021)\nDeveloper, Beta Pvt Ltd (Jun 2021 - Jun 2022)";
    // Jan 2020 .. Jun 2022 merged = 30 months = 2.5 years
    assert.equal(extractProfile(text, { now: NOW }).experienceYears, 2.5);
  });

  it("counts fresher as 0 years and reads a 10-digit mobile without a prefix", () => {
    const f = extractProfile("Priya Singh\nFresher\nBCA, Delhi University 2024\nMobile: 9876543210", { now: NOW });
    assert.equal(f.experienceYears, 0);
    assert.equal(f.phone, "9876543210");
    assert.equal(f.degree, "BCA");
    assert.equal(f.graduationYear, 2024);
  });

  it("picks the highest degree and ignores a school board as the college", () => {
    const f = extractProfile(
      "Education\nMBA Marketing, Symbiosis Institute of Business Management, Pune 2017 - 2019\nB.Com, Delhi University 2013-2016\n12th, Delhi Public School, CBSE 2013",
      { now: NOW },
    );
    assert.equal(f.degree, "MBA");
    assert.equal(f.qualification, "Post Graduate");
    assert.equal(f.graduationYear, 2019);
    assert.equal(f.college, "Symbiosis Institute of Business Management");
  });

  it("ignores a graduation year too far in the future", () => {
    const f = extractProfile("Education\nB.Tech, Some Institute of Technology 2016 - 2090", { now: NOW });
    assert.equal(f.graduationYear, 2016);
  });
});

describe("taxonomy", () => {
  it("has the pick-lists the app needs, with Remote last and major cities first", () => {
    for (const role of ["Web Developer", "Full Stack Developer", "Android Developer", "Data Analyst", "UI/UX Designer", "HR Executive", "Telecaller", "Fresher / Intern"]) {
      assert.ok(taxonomy.ROLES.includes(role), role);
    }
    for (const skill of ["HTML", "JavaScript", "React", "Node.js", "Python", "MongoDB", "AWS", "Figma", "SEO", "Tally", "Communication", "Hindi"]) {
      assert.ok(taxonomy.SKILLS.includes(skill), skill);
    }
    for (const degree of ["B.Tech", "B.Tech (CSE)", "B.E.", "BCA", "MCA", "B.Sc", "B.Com", "MBA", "PGDM", "Diploma (Engineering)", "ITI", "CA", "PhD", "12th (Science)", "10th"]) {
      assert.ok(taxonomy.DEGREES.includes(degree), degree);
    }
    assert.equal(taxonomy.CITIES[0], "Jaipur");
    assert.equal(taxonomy.CITIES[taxonomy.CITIES.length - 1], "Remote");
    assert.equal(taxonomy.LOCATIONS[taxonomy.LOCATIONS.length - 1], "Remote");
    assert.equal(taxonomy.STATES.length, 36);
    assert.ok(taxonomy.ROLES.length >= 150 && taxonomy.SKILLS.length >= 180 && taxonomy.CITIES.length >= 150);
  });
});

describe("candidate profile validation", () => {
  const valid = {
    desiredRole: "Web Developer",
    phone: "+91 98765 43210",
    age: 25,
    gender: "Female",
    location: "Pune",
    qualification: "Graduate",
    degree: "B.Tech",
    skills: ["React", "react", "Node.js"],
    experience: "2 years",
    expectedSalaryLpa: 8,
  };
  const failingField = (body) => {
    try {
      parseProfileBody(body);
    } catch (err) {
      assert.ok(err instanceof FieldError);
      return err.field;
    }
    return null;
  };

  it("accepts a full profile, dedupes skills and derives the numbers", () => {
    const data = parseProfileBody({ ...valid, expectedSalaryLpa: 1200000, about: "x".repeat(900), graduationYear: 2022 });
    assert.deepEqual(data.skills, ["React", "Node.js"]);
    assert.equal(data.expectedSalaryLpa, 12, "rupees are converted to LPA");
    assert.equal(data.experienceYears, 2);
    assert.equal(data.about.length, 600);
    assert.equal(data.graduationYear, 2022);
  });

  it("names the field that failed", () => {
    for (const key of ["desiredRole", "phone", "age", "gender", "location", "qualification", "degree", "skills", "experience", "expectedSalaryLpa"]) {
      assert.equal(failingField({ ...valid, [key]: key === "skills" ? [] : "" }), key, key);
    }
    assert.equal(failingField({ ...valid, phone: "12345" }), "phone");
    assert.equal(failingField({ ...valid, phone: "98765abcde" }), "phone");
    assert.equal(failingField({ ...valid, age: 15 }), "age");
    assert.equal(failingField({ ...valid, age: 76 }), "age");
    assert.equal(failingField({ ...valid, skills: Array.from({ length: 31 }, (_, i) => `Skill ${i}`) }), "skills");
    assert.equal(failingField({ ...valid, graduationYear: 1959 }), "graduationYear");
    assert.equal(failingField({ ...valid, graduationYear: 2041 }), "graduationYear");
    assert.equal(failingField({ ...valid, expectedSalaryMaxLpa: 5 }), "expectedSalaryMaxLpa");
    assert.equal(failingField({ ...valid, expectedSalaryLpa: "lots" }), "expectedSalaryLpa");
    assert.equal(failingField(valid), null);
  });

  it("only touches optional new fields that were sent", () => {
    const data = parseProfileBody(valid);
    for (const key of ["college", "currentPost", "graduationYear", "expectedSalaryMaxLpa", "salaryNegotiable", "workModes", "jobTypes"]) {
      assert.ok(!(key in data), key);
    }
    const sent = parseProfileBody({ ...valid, workModes: ["remote", "moon"], jobTypes: ["contract"], salaryNegotiable: true, expectedSalaryMaxLpa: 10 });
    assert.deepEqual(sent.workModes, ["remote"]);
    assert.deepEqual(sent.jobTypes, ["contract"]);
    assert.equal(sent.salaryNegotiable, true);
    assert.equal(sent.expectedSalaryMaxLpa, 10);
  });

  it("filters preferences to the allowed values", () => {
    const data = parsePreferencesBody({
      workModes: ["Remote", "hybrid", "teleport"],
      jobTypes: ["full-time", "gig"],
      preferredLocations: ["Pune", "pune", " Delhi ", "", "x".repeat(60), ...Array.from({ length: 20 }, (_, i) => `City ${i}`)],
    });
    assert.deepEqual(data.workModes, ["remote", "hybrid"]);
    assert.deepEqual(data.jobTypes, ["full-time"]);
    assert.equal(data.preferredLocations.length, 10);
    assert.equal(data.preferredLocations[0], "Pune");
    assert.equal(data.preferredLocations[1], "Delhi");
    assert.equal(data.preferredLocations[2].length, 40);
    assert.throws(() => parsePreferencesBody({ openToWork: "yes" }), FieldError);
    assert.deepEqual(parsePreferencesBody({}), {});
  });
});
