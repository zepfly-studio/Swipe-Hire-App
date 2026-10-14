// Pure-function tests: no database, no network.

const assert = require("node:assert/strict");
const { describe, it } = require("node:test");

const { normalizeSkills, parseExperienceYears, parseNoticeDays } = require("../src/lib/derive");
const { matchScore, bestMatch } = require("../src/lib/matching");
const { buildInterviewIcs } = require("../src/lib/ics");
const { automaticVerification, domainFromUrl, domainFromEmail, normalizeWebsite } = require("../src/lib/company");

describe("derive", () => {
  it("normalises skills: trimmed, lower-cased, de-duplicated, blanks dropped", () => {
    assert.deepEqual(normalizeSkills([" Flutter ", "flutter", "Dart", "", "  "]), ["flutter", "dart"]);
    assert.deepEqual(normalizeSkills(null), []);
  });

  it("reads years of experience out of free text", () => {
    assert.equal(parseExperienceYears("3 years"), 3);
    assert.equal(parseExperienceYears("1.5 years"), 1.5);
    assert.equal(parseExperienceYears("Fresher"), 0);
    assert.equal(parseExperienceYears("6 months"), 0.5);
    assert.equal(parseExperienceYears(""), 0);
  });

  it("turns a notice period into days", () => {
    assert.equal(parseNoticeDays("Immediate"), 0);
    assert.equal(parseNoticeDays("30 days"), 30);
    assert.equal(parseNoticeDays("2 months"), 60);
    assert.equal(parseNoticeDays("3 weeks"), 21);
    assert.equal(parseNoticeDays("Serving notice"), 0);
    assert.equal(parseNoticeDays("15"), 15);
  });
});

describe("matching", () => {
  const job = {
    id: "j1",
    title: "Flutter Developer",
    skillsNormalized: ["flutter", "dart", "firebase", "rest apis"],
    minExperienceYears: 3,
    location: "Pune",
    salaryMinLpa: 8,
    salaryMaxLpa: 15,
  };
  const candidate = (overrides) => ({
    skillsNormalized: ["flutter", "dart", "firebase", "rest apis"],
    experienceYears: 3,
    location: "Pune",
    expectedSalaryLpa: 12,
    ...overrides,
  });

  it("scores a perfect fit 100", () => {
    assert.equal(matchScore(job, candidate()).score, 100);
  });

  it("weighs skills most", () => {
    const half = matchScore(job, candidate({ skillsNormalized: ["flutter", "dart"] })).score;
    const none = matchScore(job, candidate({ skillsNormalized: ["cobol"] })).score;
    assert.equal(half, 73); // 0.5 * 55 + 45 = 72.5 of 100, rounded
    assert.equal(none, 45);
    assert.ok(half > none);
  });

  it("gives partial credit for experience and salary", () => {
    assert.ok(matchScore(job, candidate({ experienceYears: 1.5 })).score < 100);
    assert.equal(matchScore(job, candidate({ expectedSalaryLpa: 17 })).score, 93); // half of the salary slice: 100 - 7.5
    assert.ok(matchScore(job, candidate({ expectedSalaryLpa: 40 })).score < 90);
  });

  it("treats remote roles as a location fit", () => {
    const remote = { ...job, location: "Remote" };
    assert.equal(matchScore(remote, candidate({ location: "Delhi" })).score, 100);
    assert.ok(matchScore(job, candidate({ location: "Delhi" })).score < 100);
  });

  it("shares the skills weight out when a posting lists none", () => {
    const open = { ...job, skillsNormalized: [] };
    assert.equal(matchScore(open, candidate({ skillsNormalized: [] })).score, 100);
  });

  it("never leaves 0-100 and explains itself", () => {
    const worst = matchScore(job, candidate({ skillsNormalized: [], experienceYears: 0, location: "Mars", expectedSalaryLpa: 999 }));
    assert.ok(worst.score >= 0 && worst.score <= 100);
    assert.ok(matchScore(job, candidate()).reasons.length > 0);
  });

  it("picks the best of several postings", () => {
    const qa = { id: "j2", title: "QA", skillsNormalized: ["selenium"], minExperienceYears: 0, location: "Delhi", salaryMaxLpa: 6 };
    const best = bestMatch([qa, job], candidate());
    assert.equal(best.jobId, "j1");
    assert.equal(best.jobTitle, "Flutter Developer");
  });
});

describe("calendar file", () => {
  it("builds a valid single-event calendar", () => {
    const ics = buildInterviewIcs({
      uid: "abc",
      start: new Date(Date.UTC(2026, 9, 19, 9, 30)),
      summary: "Interview: Dev, at Acme; round 1",
      description: "Mode: Video\nDetails: https://meet.example.com/x",
      location: "https://meet.example.com/x",
    });
    assert.match(ics, /^BEGIN:VCALENDAR\r\n/);
    assert.match(ics, /DTSTART:20261019T093000Z\r\n/);
    assert.match(ics, /DTEND:20261019T103000Z\r\n/);
    assert.match(ics, /SUMMARY:Interview: Dev\\, at Acme\\; round 1\r\n/);
    assert.match(ics, /DESCRIPTION:Mode: Video\\nDetails/);
    assert.match(ics, /END:VEVENT\r\nEND:VCALENDAR\r\n$/);
    for (const line of ics.split("\r\n")) assert.ok(line.length <= 75, `line too long: ${line.length}`);
  });
});

describe("company verification", () => {
  it("compares the website's domain with the work email's", () => {
    assert.equal(domainFromUrl("https://www.Acme.com/careers"), "acme.com");
    assert.equal(domainFromUrl("acme.com"), "acme.com");
    assert.equal(domainFromEmail("Priya@Acme.com"), "acme.com");

    assert.equal(automaticVerification({ website: "https://acme.com", ownerEmail: "hr@acme.com" }), "verified");
    assert.equal(automaticVerification({ website: "https://careers.acme.com", ownerEmail: "hr@acme.com" }), "verified");
    assert.equal(automaticVerification({ website: "https://acme.com", ownerEmail: "hr@other.com" }), "unverified");
    assert.equal(automaticVerification({ website: "https://gmail.com", ownerEmail: "someone@gmail.com" }), "unverified");
    assert.equal(automaticVerification({ website: "", ownerEmail: "hr@acme.com" }), "unverified");
  });

  it("normalises a typed website and rejects junk", () => {
    assert.equal(normalizeWebsite("acme.com"), "https://acme.com");
    assert.equal(normalizeWebsite("http://acme.com/"), "http://acme.com");
    assert.equal(normalizeWebsite("javascript:alert(1)"), "");
    assert.equal(normalizeWebsite(""), "");
  });
});
