// Phase 2 company-side API tests: onboarding, jobs, deck rules, swipe
// credits, undo, wishlist, shortlist pipeline, saved searches + alerts,
// payments and candidate stats. Same harness as api.test.js (real app, real
// dev database, real HTTP).

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { describe, it, before, after } = require("node:test");
const h = require("./helpers");
const hc = require("./hiring-helpers");
const { api, signup, prisma } = h;

before(() => h.start());
after(() => h.stop());

const unique = () => `Hq${Date.now() % 1000000}${Math.floor(Math.random() * 1000)}`;

async function notificationsOf(user, type) {
  const res = await api("GET", "/notifications?limit=100", { token: user.token });
  return res.json.notifications.filter((n) => !type || n.type === type);
}

const onboardingBody = (overrides = {}) => ({
  company: { name: "Acme Hiring", industry: "IT / Software", size: "11-50", location: "Pune", about: "We build.", ...overrides.company },
  job: { title: "Flutter Developer", skills: ["Flutter", "Dart"], salaryMaxLpa: 15, salaryMinLpa: 8, minExperienceYears: 1, maxExperienceYears: 5, workMode: "hybrid", ...overrides.job },
});

describe("company onboarding and profile", () => {
  it("validates with field names, then creates the company, first job and completes the account", async () => {
    const rec = await signup("recruiter", "Onboard Rec");

    const noName = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ company: { name: "" } }) });
    assert.equal(noName.status, 400);
    assert.equal(noName.json.field, "company.name");
    const noLoc = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ company: { location: "" } }) });
    assert.equal(noLoc.json.field, "company.location");
    const noTitle = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ job: { title: "" } }) });
    assert.equal(noTitle.json.field, "job.title");
    const noSkills = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ job: { skills: [] } }) });
    assert.equal(noSkills.json.field, "job.skills");
    const noMax = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ job: { salaryMaxLpa: "" } }) });
    assert.equal(noMax.json.field, "job.salaryMaxLpa");
    const badRange = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ job: { salaryMinLpa: 20, salaryMaxLpa: 10 } }) });
    assert.equal(badRange.json.field, "job.salaryMinLpa");
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company, null, "nothing saved by failed attempts");

    const ok = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody() });
    assert.equal(ok.status, 200, JSON.stringify(ok.json));
    assert.equal(ok.json.company.name, "Acme Hiring");
    assert.equal(ok.json.company.swipesLeft, 5);
    assert.equal(ok.json.company.swipesPurchased, 0);
    assert.equal(ok.json.company.verified, false);
    assert.equal(ok.json.job.title, "Flutter Developer");
    assert.equal(ok.json.job.status, "open");
    assert.equal(ok.json.job.workMode, "hybrid");
    assert.equal(ok.json.job.location, "Pune", "job location defaults to the company location");
    assert.equal((await api("GET", "/users/me", { token: rec.token })).json.profileComplete, true);

    // A second call updates the company but does not create another job.
    const again = await api("POST", "/company/onboarding", { token: rec.token, body: onboardingBody({ company: { about: "Updated" } }) });
    assert.equal(again.status, 200);
    assert.equal(again.json.job.id, ok.json.job.id);
    const mine = await api("GET", "/jobs/mine", { token: rec.token });
    assert.equal(mine.json.jobs.length, 1);

    const me = await api("GET", "/company/me", { token: rec.token });
    assert.equal(me.json.company.about, "Updated");
    assert.equal(me.json.company.swipesLeft, 5);
    for (const key of ["address", "phone", "contactEmail", "linkedin", "foundedYear", "verificationStatus", "swipesPurchased"]) {
      assert.ok(key in me.json.company, `company.${key} missing`);
    }
  });

  it("saves the extra company fields (partially), validates them, and hides credits from others", async () => {
    const rec = await signup("recruiter", "Fields Rec");
    const created = await api("PUT", "/company/me", { token: rec.token, body: { name: "Fields Co", location: "Indore" } });
    assert.equal(created.status, 200, JSON.stringify(created.json));

    const updated = await api("PUT", "/company/me", {
      token: rec.token,
      body: { phone: "+91 98765 43210", contactEmail: "HR@Fields.example", linkedin: "linkedin.com/company/fields", foundedYear: 2015, address: "MG Road" },
    });
    assert.equal(updated.status, 200, JSON.stringify(updated.json));
    assert.equal(updated.json.company.name, "Fields Co", "fields not sent are kept");
    assert.equal(updated.json.company.contactEmail, "hr@fields.example");
    assert.equal(updated.json.company.linkedin, "https://linkedin.com/company/fields");
    assert.equal(updated.json.company.foundedYear, 2015);

    for (const [body, field] of [
      [{ phone: "abc" }, "phone"],
      [{ contactEmail: "nope" }, "contactEmail"],
      [{ foundedYear: 1700 }, "foundedYear"],
      [{ foundedYear: 3000 }, "foundedYear"],
    ]) {
      const bad = await api("PUT", "/company/me", { token: rec.token, body });
      assert.equal(bad.status, 400);
      assert.equal(bad.json.field, field);
    }

    const cand = await signup("candidate", "Public Viewer");
    const page = await api("GET", `/company/${updated.json.company.id}`, { token: cand.token });
    assert.equal(page.status, 200);
    // The same page resolves from the owner's user id (what /chats gives the app),
    // and lists only open postings.
    await h.postJob(rec, { title: "Visible Role" });
    const closed = await h.postJob(rec, { title: "Hidden Role" });
    await api("PATCH", `/jobs/${closed.id}/status`, { token: rec.token, body: { status: "closed" } });
    const byOwner = await api("GET", `/company/${rec.uid}`, { token: cand.token });
    assert.equal(byOwner.status, 200, JSON.stringify(byOwner.json));
    assert.equal(byOwner.json.company.id, updated.json.company.id);
    assert.deepEqual(byOwner.json.jobs.map((j) => j.title), ["Visible Role"]);
    assert.equal((await api("GET", "/company/00000000-0000-4000-8000-000000000000", { token: cand.token })).status, 404);
    assert.equal("swipesLeft" in page.json.company, false);
    assert.equal("phone" in page.json.company, false);
  });
});

describe("jobs lifecycle", () => {
  it("keeps status and isOpen in sync, limits active jobs to 25, and reports stats", async () => {
    const rec = await signup("recruiter", "Jobs Rec");
    const cand = await signup("candidate", "Jobs Viewer");

    const posted = await h.postJob(rec, { title: "Lifecycle Role", openings: 3, workMode: "remote", maxExperienceYears: 6, employmentType: "Part-time" });
    assert.equal(posted.status, "open");
    assert.equal(posted.isOpen, true);
    assert.equal(posted.openings, 3);
    assert.equal(posted.workMode, "remote");
    assert.equal(posted.maxExperienceYears, 6);
    assert.equal(posted.employmentType, "part-time");

    assert.ok((await api("GET", "/jobs", { token: cand.token })).json.jobs.some((j) => j.id === posted.id));

    const paused = await api("PATCH", `/jobs/${posted.id}/status`, { token: rec.token, body: { status: "paused" } });
    assert.equal(paused.status, 200);
    assert.equal(paused.json.job.status, "paused");
    assert.equal(paused.json.job.isOpen, false);
    assert.ok(!(await api("GET", "/jobs", { token: cand.token })).json.jobs.some((j) => j.id === posted.id), "paused postings are not public");

    const reopened = await api("PATCH", `/jobs/${posted.id}`, { token: rec.token, body: { isOpen: true } });
    assert.equal(reopened.json.status, "open");
    const off = await api("PATCH", `/jobs/${posted.id}`, { token: rec.token, body: { isOpen: false } });
    assert.equal(off.json.status, "paused");
    assert.equal(off.json.isOpen, false);

    const bad = await api("PATCH", `/jobs/${posted.id}/status`, { token: rec.token, body: { status: "archived" } });
    assert.equal(bad.status, 400);
    assert.equal((await api("PATCH", `/jobs/${posted.id}/status`, { token: cand.token, body: { status: "open" } })).status, 403);
    const stranger = await signup("recruiter", "Stranger Rec");
    assert.equal((await api("PATCH", `/jobs/${posted.id}/status`, { token: stranger.token, body: { status: "open" } })).status, 403);

    // Required fields carry a `field`.
    const noSkills = await api("POST", "/jobs", { token: rec.token, body: { title: "No skills", salaryMaxLpa: 10 } });
    assert.equal(noSkills.status, 400);
    assert.equal(noSkills.json.field, "skills");
    const noMax = await api("POST", "/jobs", { token: rec.token, body: { title: "No max", skills: ["a"] } });
    assert.equal(noMax.json.field, "salaryMaxLpa");
    const inverted = await api("POST", "/jobs", { token: rec.token, body: { title: "x", skills: ["a"], salaryMinLpa: 9, salaryMaxLpa: 8 } });
    assert.equal(inverted.json.error, "Minimum salary cannot be more than maximum salary");
    const equal = await api("POST", "/jobs", { token: rec.token, body: { title: "Equal", skills: ["a"], salaryMinLpa: 8, salaryMaxLpa: 8, status: "closed" } });
    assert.equal(equal.status, 201, "min == max is allowed");
    assert.equal(equal.json.status, "closed");

    // /jobs/mine: open, paused, closed, newest first; stats come from CandidateSwipe.
    const open2 = await h.postJob(rec, { title: "Second Open" });
    const mine = await api("GET", "/jobs/mine", { token: rec.token });
    assert.deepEqual(mine.json.jobs.map((j) => j.status), ["open", "paused", "closed"]);
    assert.equal(mine.json.jobs[0].id, open2.id);
    assert.deepEqual(mine.json.jobs[0].stats, { swiped: 0, shortlisted: 0, interviewing: 0, hired: 0 });

    // 25 non-closed jobs maximum.
    const existing = mine.json.jobs.filter((j) => j.status !== "closed").length;
    for (let i = existing; i < 25; i++) await h.postJob(rec, { title: `Bulk ${i}` });
    const over = await api("POST", "/jobs", {
      token: rec.token,
      body: { title: "One too many", skills: ["a"], salaryMaxLpa: 10 },
    });
    assert.equal(over.status, 400);
    assert.equal(over.json.error, "You can have up to 25 active jobs. Close an old one first.");
    // The closed job cannot be reopened while 25 are active ...
    const reopen = await api("PATCH", `/jobs/${equal.json.id}/status`, { token: rec.token, body: { status: "open" } });
    assert.equal(reopen.status, 400);
    // ... but closing one makes room.
    assert.equal((await api("PATCH", `/jobs/${open2.id}/status`, { token: rec.token, body: { status: "closed" } })).status, 200);
    assert.equal((await api("PATCH", `/jobs/${equal.json.id}/status`, { token: rec.token, body: { status: "open" } })).status, 200);
  });

  it("computes per-job stats from swipes and pipeline stages", async () => {
    const { rec, job } = await hc.recruiterWithJob("Stats Rec");
    const tag = unique();
    const people = [];
    for (let i = 0; i < 4; i++) people.push(await h.candidateWithProfile(`${tag} Person${i}`, { desiredRole: `${tag} Dev` }));

    assert.equal((await hc.swipe(rec, people[0].uid, "left")).status, 200);
    for (const p of people.slice(1)) assert.equal((await hc.swipe(rec, p.uid, "right")).status, 200);
    const list = (await api("GET", "/company/shortlisted", { token: rec.token })).json.candidates;
    const byCand = Object.fromEntries(list.map((r) => [r.id, r.swipeId]));
    await api("PATCH", `/company/pipeline/${byCand[people[2].uid]}`, { token: rec.token, body: { stage: "interview" } });
    await api("PATCH", `/company/pipeline/${byCand[people[3].uid]}`, { token: rec.token, body: { stage: "hired" } });

    const mine = await api("GET", "/jobs/mine", { token: rec.token });
    assert.deepEqual(mine.json.jobs.find((j) => j.id === job.id).stats, { swiped: 4, shortlisted: 3, interviewing: 1, hired: 1 });
  });
});

describe("deck rules", () => {
  it("needs a job, is job-aware, applies salary fit, exclude and the credit cap", async () => {
    const rec = await signup("recruiter", "Deck2 Rec");
    const none = await api("GET", "/candidates", { token: rec.token });
    assert.equal(none.status, 403);
    assert.equal(none.json.code, "NO_JOB");

    const tag = unique();
    const jobA = await h.postJob(rec, { title: `${tag} A`, salaryMinLpa: 5, salaryMaxLpa: 15, skills: ["Flutter", "Dart"], location: "Pune" });
    const jobB = await h.postJob(rec, { title: `${tag} B`, salaryMinLpa: 5, salaryMaxLpa: 15, skills: ["Flutter"], location: "Pune" });
    await hc.giveSwipes(rec, 50);

    const base = { desiredRole: `${tag} Dev` };
    const fits = await h.candidateWithProfile(`${tag} Fits`, { ...base, expectedSalaryLpa: 12, skills: ["Flutter", "Dart", "Firebase"], noticePeriod: "30 days" });
    const pricey = await h.candidateWithProfile(`${tag} Pricey`, { ...base, expectedSalaryLpa: 40, noticePeriod: "Immediate" });
    const flexible = await h.candidateWithProfile(`${tag} Flexible`, { ...base, expectedSalaryLpa: 40, salaryNegotiable: true, noticePeriod: "60 days", location: "Indore" });
    const away = await h.candidateWithProfile(`${tag} Away`, { ...base, expectedSalaryLpa: 10, location: "Delhi", skills: ["Python"] });
    await api("PUT", "/candidates/me/preferences", { token: away.token, body: { preferredLocations: ["Pune West"] } });
    const q = `&q=${tag}`;
    const ids = async (query = "", jobId = jobA.id) =>
      (await api("GET", `/candidates?limit=30&jobId=${jobId}${q}${query}`, { token: rec.token })).json.candidates.map((c) => c.id).sort();

    // Hard salary fit: Pricey (40 LPA, not negotiable) never shows for a 15 LPA job.
    assert.deepEqual(await ids(), [fits.uid, flexible.uid, away.uid].sort());

    const first = await api("GET", `/candidates?limit=30&jobId=${jobA.id}${q}`, { token: rec.token });
    assert.equal(first.json.swipesLeft, 50);
    assert.equal(first.json.job.id, jobA.id);
    assert.equal(first.json.job.title, `${tag} A`);
    const card = first.json.candidates.find((c) => c.id === fits.uid);
    assert.deepEqual(card.matchedSkills.sort(), ["Dart", "Flutter"]);
    assert.equal(card.wishlisted, false);
    assert.equal("contact" in card, false);
    assert.equal(typeof card.matchScore, "number");

    // Filters: budget (maxSalary = expected <= value OR negotiable), notice buckets, location + preferredLocations.
    assert.deepEqual(await ids("&maxSalary=11"), [away.uid, flexible.uid].sort());
    assert.deepEqual(await ids("&notice=0,30"), [away.uid, fits.uid].sort());
    assert.deepEqual(await ids("&notice=15"), []);
    assert.deepEqual(await ids("&notice=60"), [flexible.uid]);
    assert.deepEqual(await ids("&location=pune"), [away.uid, fits.uid].sort(), "location also matches preferredLocations");
    assert.deepEqual(await ids("&skills=python"), [away.uid]);

    // Dedupe is per job: a swipe for A hides them from A only.
    assert.equal((await hc.swipe(rec, fits.uid, "left", jobA.id)).status, 200);
    assert.ok(!(await ids()).includes(fits.uid));
    assert.ok((await ids("", jobB.id)).includes(fits.uid));

    // exclude removes cards the app already holds.
    assert.deepEqual(await ids(`&exclude=${flexible.uid}`), [away.uid]);

    // The card count never exceeds swipes left minus the excluded ones.
    await hc.giveSwipes(rec, 2);
    const capped = await api("GET", `/candidates?limit=30&jobId=${jobA.id}${q}`, { token: rec.token });
    assert.equal(capped.json.candidates.length, 2);
    assert.equal(capped.json.swipesLeft, 2);
    const cappedExclude = await api("GET", `/candidates?limit=30&jobId=${jobA.id}${q}&exclude=${away.uid}`, { token: rec.token });
    assert.equal(cappedExclude.json.candidates.length, 1);
    assert.ok(!cappedExclude.json.candidates.some((c) => c.id === away.uid));
    const bothHeld = await api("GET", `/candidates?limit=30&jobId=${jobA.id}${q}&exclude=${away.uid},${flexible.uid}`, { token: rec.token });
    assert.deepEqual(bothHeld.json.candidates, []);

    await hc.giveSwipes(rec, 0);
    const empty = await api("GET", `/candidates?limit=30&jobId=${jobA.id}${q}`, { token: rec.token });
    assert.equal(empty.status, 200);
    assert.deepEqual(empty.json.candidates, []);
    assert.equal(empty.json.swipesLeft, 0);

    // Paused / closed jobs and unknown jobs.
    await api("PATCH", `/jobs/${jobB.id}/status`, { token: rec.token, body: { status: "paused" } });
    const paused = await api("GET", `/candidates?jobId=${jobB.id}`, { token: rec.token });
    assert.equal(paused.status, 409);
    assert.equal(paused.json.error, "This job is paused or closed. Reopen it to see candidates.");
    assert.equal((await api("GET", "/candidates?jobId=00000000-0000-4000-8000-000000000000", { token: rec.token })).status, 404);
  });

  it("shows contact details only for candidates this company already shortlisted", async () => {
    const tag = unique();
    const { rec } = await hc.recruiterWithJob("Contact Deck Rec", { job: { title: `${tag} A` } });
    const jobB = await h.postJob(rec, { title: `${tag} B`, salaryMaxLpa: 1000, salaryMinLpa: 0 });
    const cand = await h.candidateWithProfile(`${tag} Person`, { desiredRole: `${tag} Dev` });

    const swiped = await hc.swipe(rec, cand.uid, "right");
    assert.equal(swiped.status, 200);
    assert.equal(swiped.json.contact.email, cand.email);

    // Still on job B's deck, now with contact (right-swiped for another job).
    const deck = await api("GET", `/candidates?jobId=${jobB.id}&q=${tag}`, { token: rec.token });
    const card = deck.json.candidates.find((c) => c.id === cand.uid);
    assert.equal(card.contact.email, cand.email);
    assert.equal(card.contact.phone, h.profileBody.phone);
    for (const key of ["age", "gender", "phone", "email"]) assert.equal(key in card, false);
  });
});

describe("swipe credits", () => {
  it("charges one swipe for left and right, stops at zero, and refunds duplicates and mismatches", async () => {
    const tag = unique();
    const rec = await signup("recruiter", "Credit Rec");
    const job = await h.postJob(rec, { salaryMinLpa: 5, salaryMaxLpa: 15 });
    // Lazily created company starts with the 5 free swipes.
    const people = [];
    for (let i = 0; i < 4; i++) people.push(await h.candidateWithProfile(`${tag} Credit${i}`, { desiredRole: `${tag} Dev`, expectedSalaryLpa: 10 }));
    const pricey = await h.candidateWithProfile(`${tag} Pricey`, { desiredRole: `${tag} Dev`, expectedSalaryLpa: 30 });
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company, null);

    const left = await hc.swipe(rec, people[0].uid, "left");
    assert.equal(left.status, 200, JSON.stringify(left.json));
    assert.equal(left.json.swipesLeft, 4);
    assert.equal("contact" in left.json, false);
    const right = await hc.swipe(rec, people[1].uid, "right");
    assert.equal(right.json.swipesLeft, 3);
    assert.equal(right.json.contact.email, people[1].email);

    const dupe = await hc.swipe(rec, people[1].uid, "left");
    assert.equal(dupe.status, 409);
    assert.equal(dupe.json.error, "You have already swiped this candidate for this job");
    assert.equal(await hc.swipesLeft(rec), 3, "duplicate is not charged");

    const mismatch = await hc.swipe(rec, pricey.uid, "right");
    assert.equal(mismatch.status, 409);
    assert.equal(mismatch.json.code, "SALARY_MISMATCH");
    assert.match(mismatch.json.error, /expects at least ₹30 LPA, above this job's budget of ₹15 LPA, and is not open to negotiate\.$/);
    assert.equal(await hc.swipesLeft(rec), 3, "salary mismatch is not charged");
    // A left swipe on the same person is allowed (a pass costs 1).
    assert.equal((await hc.swipe(rec, pricey.uid, "left")).json.swipesLeft, 2);

    assert.equal((await api("POST", "/company/swipe", { token: rec.token, body: { candidateId: people[2].uid, action: "up" } })).status, 400);
    assert.equal((await api("POST", "/company/swipe", { token: rec.token, body: { action: "left" } })).status, 400);
    assert.equal((await hc.swipe(rec, "00000000-0000-4000-8000-000000000000", "left")).status, 404);
    assert.equal((await api("POST", "/company/swipe", { token: rec.token, body: { candidateId: people[2].uid, action: "left", jobId: "00000000-0000-4000-8000-000000000000" } })).status, 404);
    assert.equal(await hc.swipesLeft(rec), 2);

    assert.equal((await hc.swipe(rec, people[2].uid, "left", job.id)).json.swipesLeft, 1);
    assert.equal((await hc.swipe(rec, people[3].uid, "right")).json.swipesLeft, 0);
    const out = await hc.swipe(rec, people[3].uid, "left");
    // already swiped AND out of credits: the credit check wins.
    assert.equal(out.status, 402);
    assert.equal(out.json.code, "NO_SWIPES");
    assert.equal(out.json.error, "You have used all your swipes. Buy a plan to keep swiping.");
  });

  it("never overspends when swipes race", async () => {
    const tag = unique();
    const { rec } = await hc.recruiterWithJob("Race Rec", { swipes: 1 });
    const people = [];
    for (let i = 0; i < 4; i++) people.push(await h.candidateWithProfile(`${tag} Race${i}`));
    const results = await Promise.all(people.map((p) => hc.swipe(rec, p.uid, "left")));
    assert.equal(results.filter((r) => r.status === 200).length, 1);
    assert.equal(results.filter((r) => r.status === 402).length, 3);
    assert.equal(await hc.swipesLeft(rec), 0);

    // Two identical swipes at once: one row, one charge.
    await hc.giveSwipes(rec, 5);
    const x = await h.candidateWithProfile(`${tag} RaceX`);
    const y = await h.candidateWithProfile(`${tag} RaceY`);
    const pair = await Promise.all([hc.swipe(rec, x.uid, "right"), hc.swipe(rec, y.uid, "right"), hc.swipe(rec, y.uid, "right")]);
    assert.equal(pair.filter((r) => r.status === 200).length, 2, JSON.stringify(pair.map((r) => r.status)));
    assert.equal(await hc.swipesLeft(rec), 3);
  });

  it("tells a shortlisted candidate anonymously, and only live candidates can be swiped", async () => {
    const tag = unique();
    const { rec } = await hc.recruiterWithJob("Notify Rec", { signupOptions: { company: "Secret Corp" } });
    const cand = await h.candidateWithProfile(`${tag} Notified`);
    await hc.swipe(rec, cand.uid, "right");
    await h.idle();
    const [note] = await notificationsOf(cand, "shortlisted");
    assert.equal(note.title, "A company shortlisted you!");
    assert.equal(note.link, "/candidate");
    assert.equal(JSON.stringify(note).includes("Secret Corp"), false);
    assert.ok(h.pushes.some((p) => p.title === "A company shortlisted you!"));

    const hidden = await h.candidateWithProfile(`${tag} Hidden`);
    await api("PUT", "/candidates/me/preferences", { token: hidden.token, body: { openToWork: false } });
    assert.equal((await hc.swipe(rec, hidden.uid, "right")).status, 404);
    const unfinished = await signup("candidate", `${tag} Unfinished`);
    assert.equal((await hc.swipe(rec, unfinished.uid, "left")).status, 404);
    const cand2 = await signup("candidate", `${tag} Not Recruiter`);
    assert.equal((await api("POST", "/company/swipe", { token: cand2.token, body: { candidateId: cand.uid, action: "left" } })).status, 403);
  });
});

describe("undo", () => {
  it("refunds a left swipe, not a right one, and refuses once contacted or too late", async () => {
    const tag = unique();
    const { rec } = await hc.recruiterWithJob("Undo Rec", { swipes: 10 });
    const a = await h.candidateWithProfile(`${tag} UndoA`);
    const b = await h.candidateWithProfile(`${tag} UndoB`);
    const c = await h.candidateWithProfile(`${tag} UndoC`);

    assert.equal((await api("POST", "/company/swipe/undo", { token: rec.token })).status, 404);

    await hc.swipe(rec, a.uid, "left");
    assert.equal(await hc.swipesLeft(rec), 9);
    const undoLeft = await api("POST", "/company/swipe/undo", { token: rec.token });
    assert.equal(undoLeft.status, 200, JSON.stringify(undoLeft.json));
    assert.equal(undoLeft.json.swipesLeft, 10);
    assert.equal(undoLeft.json.action, "left");
    assert.equal(undoLeft.json.card.id, a.uid);
    assert.ok(undoLeft.json.jobId);
    assert.equal("contact" in undoLeft.json.card, false);

    await hc.swipe(rec, b.uid, "right");
    await h.idle();
    assert.equal((await notificationsOf(b, "shortlisted")).length, 1);
    const undoRight = await api("POST", "/company/swipe/undo", { token: rec.token });
    assert.equal(undoRight.status, 200);
    assert.equal(undoRight.json.action, "right");
    assert.equal(undoRight.json.swipesLeft, 9, "a right swipe is not refunded");
    assert.equal((await notificationsOf(b, "shortlisted")).length, 0, "the notification is withdrawn");
    assert.equal((await api("GET", "/company/shortlisted", { token: rec.token })).json.candidates.length, 0);

    // Once the company has messaged, the right swipe is final.
    await hc.swipe(rec, c.uid, "right");
    await prisma.chatMessage.create({ data: { companyId: rec.uid, candidateId: c.uid, senderId: rec.uid, text: "Hi" } });
    const blocked = await api("POST", "/company/swipe/undo", { token: rec.token });
    assert.equal(blocked.status, 409);
    assert.equal(blocked.json.error, "You have already contacted this candidate, so this swipe cannot be undone");
    await prisma.chatMessage.deleteMany({ where: { companyId: rec.uid, candidateId: c.uid } });

    // A moved stage also blocks it; so does an interview created since.
    const row = (await api("GET", "/company/shortlisted", { token: rec.token })).json.candidates[0];
    await prisma.candidateSwipe.update({ where: { id: row.swipeId }, data: { stage: "contacted" } });
    assert.equal((await api("POST", "/company/swipe/undo", { token: rec.token })).status, 409);
    await prisma.candidateSwipe.update({ where: { id: row.swipeId }, data: { stage: "shortlisted" } });
    const interview = await prisma.interview.create({
      data: { companyId: rec.uid, candidateId: c.uid, slots: [new Date(Date.now() + 86400000)] },
    });
    assert.equal((await api("POST", "/company/swipe/undo", { token: rec.token })).status, 409);
    await prisma.interview.delete({ where: { id: interview.id } });

    // Older than 10 minutes: nothing to undo.
    await prisma.candidateSwipe.update({ where: { id: row.swipeId }, data: { createdAt: new Date(Date.now() - 11 * 60 * 1000) } });
    assert.equal((await api("POST", "/company/swipe/undo", { token: rec.token })).status, 404);
  });
});

describe("wishlist", () => {
  it("is free, idempotent, boolean-only, live-only, and shows contact once shortlisted", async () => {
    const tag = unique();
    const { rec, job } = await hc.recruiterWithJob("Wish2 Rec", { swipes: 3 });
    const cand = await h.candidateWithProfile(`${tag} Wished`);

    assert.equal((await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: "yes" } })).status, 400);
    for (let i = 0; i < 2; i++) {
      const res = await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: true } });
      assert.deepEqual(res.json, { wishlisted: true });
    }
    assert.equal(await hc.swipesLeft(rec), 3, "wishlisting is free");

    const list = await api("GET", "/company/wishlist", { token: rec.token });
    assert.equal(list.json.candidates.length, 1);
    assert.equal(list.json.candidates[0].wishlisted, true);
    assert.equal("contact" in list.json.candidates[0], false);
    assert.equal(typeof list.json.candidates[0].matchScore, "number");

    await hc.swipe(rec, cand.uid, "right", job.id);
    const after = await api("GET", "/company/wishlist", { token: rec.token });
    assert.equal(after.json.candidates[0].contact.email, cand.email);
    const sl = await api("GET", "/company/shortlisted", { token: rec.token });
    assert.equal(sl.json.candidates[0].wishlisted, true);

    assert.deepEqual((await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: false } })).json, { wishlisted: false });
    assert.deepEqual((await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: false } })).json, { wishlisted: false });
    assert.equal((await api("GET", "/company/wishlist", { token: rec.token })).json.candidates.length, 0);

    await api("PUT", "/candidates/me/preferences", { token: cand.token, body: { openToWork: false } });
    assert.equal((await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: true } })).status, 404);
  });
});

describe("shortlisted pipeline", () => {
  it("lists one row per right swipe, moves stages, keeps notes and notifies on hired once", async () => {
    const tag = unique();
    const { rec, job } = await hc.recruiterWithJob("Pipe Rec", { signupOptions: { company: "Pipe Co" }, job: { title: `${tag} Lead` } });
    await api("PUT", "/company/me", { token: rec.token, body: { name: "Pipe Co" } });
    const job2 = await h.postJob(rec, { title: `${tag} Other`, salaryMaxLpa: 1000, salaryMinLpa: 0 });
    const cand = await h.candidateWithProfile(`${tag} Pipeline`);
    const other = await h.candidateWithProfile(`${tag} Passed`);

    await hc.swipe(rec, cand.uid, "right", job.id);
    await hc.swipe(rec, cand.uid, "right", job2.id);
    await hc.swipe(rec, other.uid, "left", job.id);

    const all = await api("GET", "/company/shortlisted", { token: rec.token });
    assert.equal(all.json.candidates.length, 2, "left swipes are not shortlisted");
    const forJob = await api("GET", `/company/shortlisted?jobId=${job.id}`, { token: rec.token });
    assert.equal(forJob.json.candidates.length, 1);
    const row = forJob.json.candidates[0];
    assert.equal(row.stage, "shortlisted");
    assert.equal(row.notes, "");
    assert.equal(row.job.title, `${tag} Lead`);
    assert.equal(row.contact.email, cand.email);
    assert.ok(row.swipeId && row.shortlistedAt && row.jobId === job.id);

    const patch = (swipeId, body) => api("PATCH", `/company/pipeline/${swipeId}`, { token: rec.token, body });
    assert.equal((await patch(row.swipeId, { stage: "bogus" })).status, 400);
    assert.equal((await patch(row.swipeId, { notes: "x".repeat(2001) })).status, 400);
    assert.equal((await patch("00000000-0000-4000-8000-000000000000", { stage: "contacted" })).status, 404);

    const noted = await patch(row.swipeId, { notes: "  Strong on Flutter  " });
    assert.deepEqual(noted.json, { ok: true, notes: "Strong on Flutter" });
    const moved = await patch(row.swipeId, { stage: "interview", notes: "Call on Monday" });
    assert.deepEqual(moved.json, { ok: true, stage: "interview", notes: "Call on Monday" });

    const hired = await patch(row.swipeId, { stage: "hired" });
    assert.equal(hired.json.stage, "hired");
    await h.idle();
    const congrats = await notificationsOf(cand, "hired");
    assert.equal(congrats.length, 1);
    assert.equal(congrats[0].title, "Congratulations! Pipe Co selected you 🎉");
    assert.equal(congrats[0].link, `/messages?with=${rec.uid}`);

    await patch(row.swipeId, { stage: "hired" });
    await h.idle();
    assert.equal((await notificationsOf(cand, "hired")).length, 1, "no second notification for the same stage");

    // Another recruiter cannot touch this row.
    const stranger = await signup("recruiter", "Pipe Stranger");
    const foreign = await api("PATCH", `/company/pipeline/${row.swipeId}`, { token: stranger.token, body: { stage: "rejected" } });
    assert.equal(foreign.status, 404);
  });

  it("removing someone from the shortlist puts them back in the swipe deck (no refund)", async () => {
    const tag = unique();
    const { rec, job } = await hc.recruiterWithJob("Remove Rec", { job: { title: `${tag} Role` } });
    const cand = await h.candidateWithProfile(`${tag} Comeback`);
    const inDeck = async () => (await hc.deckAll(rec, `&jobId=${job.id}&q=${tag}`)).some((c) => c.id === cand.uid);
    const shortlist = async () => (await api("GET", `/company/shortlisted?jobId=${job.id}`, { token: rec.token })).json.candidates;

    assert.equal(await inDeck(), true);
    await hc.swipe(rec, cand.uid, "right", job.id);
    assert.equal(await inDeck(), false, "a shortlisted candidate leaves the deck");
    const balance = await hc.swipesLeft(rec);
    const [row] = await shortlist();
    assert.ok(row && row.swipeId);

    const remove = (swipeId, token = rec.token) => api("DELETE", `/company/shortlisted/${swipeId}`, { token });
    assert.equal((await remove("00000000-0000-4000-8000-000000000000")).status, 404);
    const stranger = await signup("recruiter", "Remove Stranger");
    assert.equal((await remove(row.swipeId, stranger.token)).status, 404, "another company cannot remove it");

    const done = await remove(row.swipeId);
    assert.equal(done.status, 200, JSON.stringify(done.json));
    assert.deepEqual(done.json, { ok: true, candidateId: cand.uid, jobId: job.id, stage: "shortlisted" });
    assert.equal((await shortlist()).length, 0);
    assert.equal(await inDeck(), true, "back in the swipe deck for that job");
    assert.equal(await hc.swipesLeft(rec), balance, "the original swipe is not refunded");

    const again = await hc.swipe(rec, cand.uid, "right", job.id);
    assert.equal(again.status, 200, "they can be shortlisted again");
    assert.equal(await hc.swipesLeft(rec), balance - 1);
  });

  it("refuses to remove a hired candidate or one with a live task or interview", async () => {
    const tag = unique();
    const { rec, job } = await hc.recruiterWithJob("Remove Guard", { job: { title: `${tag} Role` } });
    const cand = await h.candidateWithProfile(`${tag} Guarded`);
    await hc.swipe(rec, cand.uid, "right", job.id);
    const rowOf = async () => (await api("GET", `/company/shortlisted?jobId=${job.id}`, { token: rec.token })).json.candidates[0];
    const remove = (swipeId) => api("DELETE", `/company/shortlisted/${swipeId}`, { token: rec.token });
    const row = await rowOf();

    // A live task blocks removal until it is cancelled.
    const dueAt = new Date(Date.now() + 3 * 86400000).toISOString();
    const task = await api("POST", "/tasks", {
      token: rec.token,
      body: { candidateId: cand.uid, jobId: job.id, title: "Build it", description: "Do the thing", dueAt },
    });
    assert.equal(task.status, 201, JSON.stringify(task.json));
    const blockedByTask = await remove(row.swipeId);
    assert.equal(blockedByTask.status, 409);
    assert.match(blockedByTask.json.error, /task/);
    await api("POST", `/tasks/${task.json.id}/cancel`, { token: rec.token });

    // So does an interview that is waiting for the candidate.
    const slots = [new Date(Date.now() + 2 * 86400000).toISOString()];
    const interview = await api("POST", "/interviews", {
      token: rec.token,
      body: { candidateId: cand.uid, jobId: job.id, slots, durationMins: 30, mode: "video" },
    });
    assert.equal(interview.status, 201, JSON.stringify(interview.json));
    const blockedByInterview = await remove(row.swipeId);
    assert.equal(blockedByInterview.status, 409);
    assert.match(blockedByInterview.json.error, /interview/);
    await api("POST", `/interviews/${interview.json.id}/cancel`, { token: rec.token, body: { reason: "plans changed" } });

    // Hired people stay.
    await api("PATCH", `/company/pipeline/${row.swipeId}`, { token: rec.token, body: { stage: "hired" } });
    const hired = await remove(row.swipeId);
    assert.equal(hired.status, 409);
    assert.match(hired.json.error, /hired/i);

    // Once nothing is open and they are not hired, removal works from any stage.
    await api("PATCH", `/company/pipeline/${row.swipeId}`, { token: rec.token, body: { stage: "contacted" } });
    assert.equal((await remove(row.swipeId)).status, 200);
  });
});

describe("saved searches and alerts", () => {
  it("validates, caps at 20, and alerts a matching candidate exactly once", async () => {
    const tag = unique();
    const skill = `skill${tag}`.toLowerCase();
    const rec = await signup("recruiter", "Search Rec");
    const search = (body) => api("POST", "/company/searches", { token: rec.token, body });

    assert.equal((await search({ name: "", filters: { skills: [skill] } })).json.error, "Give this search a name");
    assert.equal((await search({ name: "Empty", filters: {} })).json.error, "Set at least one filter before saving the search");
    assert.equal((await search({ name: "Empty", filters: { skills: [], notice: [], location: "  " } })).status, 400);

    // A candidate who already matches never triggers an alert.
    const early = await h.candidateWithProfile(`${tag} Early`, { skills: [skill, "Dart"] });
    const created = await search({ name: "My Pune search", filters: { skills: [skill], maxExp: 10, notice: [30], location: "Pune" } });
    assert.equal(created.status, 201, JSON.stringify(created.json));
    assert.equal(created.json.search.alerts, true);
    assert.deepEqual(created.json.search.filters.skills, [skill]);
    const searchId = created.json.search.id;
    const muted = await search({ name: "Muted", filters: { skills: [skill] }, alerts: false });
    assert.equal(muted.json.search.alerts, false);

    await api("PUT", "/candidates/me/profile", { token: early.token, body: { ...h.profileBody, skills: [skill, "Dart"] } });
    await h.idle();
    assert.equal((await notificationsOf(rec, "alert")).length, 0, "pre-marked candidate does not alert");

    // A new candidate who matches -> exactly one alert, even when saving again.
    const fresh = await signup("candidate", `${tag} Fresh`);
    const body = { ...h.profileBody, skills: [skill, "Flutter"], location: "Pune", experience: "3 years", noticePeriod: "30 days" };
    assert.equal((await api("PUT", "/candidates/me/profile", { token: fresh.token, body })).status, 200);
    await h.idle();
    let alerts = await notificationsOf(rec, "alert");
    assert.equal(alerts.length, 1);
    assert.equal(alerts[0].title, 'New match for "My Pune search"');
    assert.equal(alerts[0].link, `/company/swipe?search=${searchId}`);
    await api("PATCH", "/users/me", { token: fresh.token, body: { profileComplete: true } });
    await api("PUT", "/candidates/me/profile", { token: fresh.token, body: { ...body, about: "again" } });
    await api("PUT", "/candidates/me/preferences", { token: fresh.token, body: { workModes: ["remote"] } });
    await h.idle();
    assert.equal((await notificationsOf(rec, "alert")).length, 1, "once per candidate");

    // Not open to work: skipped; switching it on is a preference change that alerts.
    const sleeper = await h.candidateWithProfile(`${tag} Sleeper`, { skills: ["Cobol"], location: "Pune", noticePeriod: "30 days" });
    await api("PUT", "/candidates/me/preferences", { token: sleeper.token, body: { openToWork: false } });
    await api("PUT", "/candidates/me/profile", { token: sleeper.token, body: { ...h.profileBody, skills: [skill], location: "Pune", noticePeriod: "30 days" } });
    await h.idle();
    assert.equal((await notificationsOf(rec, "alert")).length, 1);
    await api("PUT", "/candidates/me/preferences", { token: sleeper.token, body: { openToWork: true } });
    await h.idle();
    alerts = await notificationsOf(rec, "alert");
    assert.equal(alerts.length, 2);
    // The muted search never alerts; salary fit is not applied to alerts.
    assert.ok(alerts.every((n) => n.title.includes("My Pune search")));

    // A non-matching notice period does not alert.
    const slow = await h.candidateWithProfile(`${tag} Slow`, { skills: [skill], location: "Pune", noticePeriod: "90 days" });
    await api("PUT", "/candidates/me/profile", { token: slow.token, body: { ...h.profileBody, skills: [skill], location: "Pune", noticePeriod: "90 days" } });
    await h.idle();
    assert.equal((await notificationsOf(rec, "alert")).length, 2);

    // List, patch, delete.
    const list = await api("GET", "/company/searches", { token: rec.token });
    assert.equal(list.json.searches.length, 2);
    const patched = await api("PATCH", `/company/searches/${searchId}`, { token: rec.token, body: { alerts: false, name: "Renamed" } });
    assert.equal(patched.json.search.name, "Renamed");
    assert.equal(patched.json.search.alerts, false);
    assert.equal((await api("PATCH", "/company/searches/00000000-0000-4000-8000-000000000000", { token: rec.token, body: { alerts: true } })).status, 404);
    assert.deepEqual((await api("DELETE", `/company/searches/${searchId}`, { token: rec.token })).json, { ok: true });
    assert.equal((await api("GET", "/company/searches", { token: rec.token })).json.searches.length, 1);

    // At most 20 per company.
    for (let i = 0; i < 19; i++) assert.equal((await search({ name: `S${i}`, filters: { location: `Town${i}` } })).status, 201);
    const over = await search({ name: "One more", filters: { location: "Elsewhere" } });
    assert.equal(over.status, 400);
  });
});

describe("payments", () => {
  const saved = {};
  before(() => {
    for (const key of ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET", "DEMO_PAYMENTS", "NODE_ENV"]) saved[key] = process.env[key];
    for (const key of ["RAZORPAY_KEY_ID", "RAZORPAY_KEY_SECRET", "RAZORPAY_WEBHOOK_SECRET", "DEMO_PAYMENTS"]) delete process.env[key];
  });
  after(() => {
    for (const [key, value] of Object.entries(saved)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it("lists plans publicly and runs the demo order -> verify flow once per order", async () => {
    const plans = await api("GET", "/payment/plans");
    assert.equal(plans.status, 200);
    assert.equal(plans.json.freeSwipes, 5);
    assert.equal(plans.json.demoMode, true);
    assert.deepEqual(plans.json.plans.map((p) => [p.id, p.price, p.swipes]), [["starter", 399, 150]]);

    const rec = await signup("recruiter", "Pay Rec");
    const other = await signup("recruiter", "Pay Other");
    assert.equal((await api("POST", "/payment/order", { token: rec.token, body: { planId: "nope" } })).status, 400);
    const cand = await signup("candidate", "Pay Cand");
    assert.equal((await api("POST", "/payment/order", { token: cand.token, body: { planId: "starter" } })).status, 403);

    const order = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
    assert.equal(order.status, 200, JSON.stringify(order.json));
    assert.equal(order.json.mode, "demo");
    assert.match(order.json.orderId, /^demo_[0-9a-f]{16}$/);
    assert.equal(order.json.amount, 39900);
    assert.equal(order.json.currency, "INR");
    assert.equal(order.json.plan.swipes, 150);

    assert.equal((await api("POST", "/payment/verify", { token: other.token, body: { orderId: order.json.orderId } })).status, 404);
    assert.equal((await api("POST", "/payment/verify", { token: rec.token, body: { orderId: "demo_unknown" } })).status, 404);

    const verified = await api("POST", "/payment/verify", { token: rec.token, body: { orderId: order.json.orderId } });
    assert.equal(verified.status, 200, JSON.stringify(verified.json));
    assert.deepEqual(verified.json, { swipesLeft: 155, added: 150 });
    const twice = await api("POST", "/payment/verify", { token: rec.token, body: { orderId: order.json.orderId } });
    assert.deepEqual(twice.json, { swipesLeft: 155, added: 0 });

    // Parallel verifies of one order credit it once.
    const order2 = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
    const racing = await Promise.all([1, 2, 3].map(() => api("POST", "/payment/verify", { token: rec.token, body: { orderId: order2.json.orderId } })));
    assert.equal(racing.reduce((n, r) => n + r.json.added, 0), 150);
    const me = await api("GET", "/company/me", { token: rec.token });
    assert.equal(me.json.company.swipesLeft, 305);
    assert.equal(me.json.company.swipesPurchased, 300);
  });

  it("refuses demo orders in production unless DEMO_PAYMENTS=true", async () => {
    const rec = await signup("recruiter", "Prod Pay Rec");
    process.env.NODE_ENV = "production";
    try {
      assert.equal((await api("GET", "/payment/plans")).json.demoMode, false);
      const refused = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
      assert.equal(refused.status, 503);
      assert.equal(refused.json.error, "Payments are not available right now");
      process.env.DEMO_PAYMENTS = "true";
      assert.equal((await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } })).status, 200);
    } finally {
      process.env.NODE_ENV = "test";
      delete process.env.DEMO_PAYMENTS;
    }
  });

  it("creates Razorpay orders over REST, checks the checkout signature, and credits via webhook once", async () => {
    const rec = await signup("recruiter", "Razor Rec");
    process.env.RAZORPAY_KEY_ID = "rzp_test_key";
    process.env.RAZORPAY_KEY_SECRET = "rzp_test_secret";
    process.env.RAZORPAY_WEBHOOK_SECRET = "whsec_test";

    const realFetch = globalThis.fetch;
    const razorpayCalls = [];
    globalThis.fetch = async (url, options) => {
      if (String(url).startsWith("https://api.razorpay.com/")) {
        razorpayCalls.push({ url: String(url), options });
        return new Response(JSON.stringify({ id: `order_${crypto.randomBytes(6).toString("hex")}` }), { status: 200, headers: { "Content-Type": "application/json" } });
      }
      return realFetch(url, options);
    };
    try {
      assert.equal((await api("GET", "/payment/plans")).json.demoMode, false);
      const order = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
      assert.equal(order.status, 200, JSON.stringify(order.json));
      assert.equal(order.json.mode, "razorpay");
      assert.equal(order.json.keyId, "rzp_test_key");
      assert.equal(order.json.amount, 39900);
      assert.equal(razorpayCalls.length, 1);
      assert.equal(razorpayCalls[0].url, "https://api.razorpay.com/v1/orders");
      assert.equal(razorpayCalls[0].options.headers.Authorization, `Basic ${Buffer.from("rzp_test_key:rzp_test_secret").toString("base64")}`);
      assert.equal(JSON.parse(razorpayCalls[0].options.body).amount, 39900);

      const orderId = order.json.orderId;
      const paymentId = "pay_abc123";
      const bad = await api("POST", "/payment/verify", { token: rec.token, body: { orderId, paymentId, signature: "0".repeat(64) } });
      assert.equal(bad.status, 400);
      assert.equal(bad.json.error, "Payment verification failed");
      assert.equal((await api("POST", "/payment/verify", { token: rec.token, body: { orderId } })).status, 400, "demo-style verify is refused");

      const signature = crypto.createHmac("sha256", "rzp_test_secret").update(`${orderId}|${paymentId}`).digest("hex");
      const good = await api("POST", "/payment/verify", { token: rec.token, body: { orderId, paymentId, signature } });
      assert.deepEqual(good.json, { swipesLeft: 155, added: 150 });

      // The webhook for the same order cannot credit it again.
      const { handleWebhook } = require("../src/lib/payments");
      const event = Buffer.from(JSON.stringify({ event: "payment.captured", payload: { payment: { entity: { id: paymentId, order_id: orderId, amount: 39900 } } } }));
      const sig = crypto.createHmac("sha256", "whsec_test").update(event).digest("hex");
      assert.equal((await handleWebhook(event, "bad")).status, 400);
      assert.equal((await handleWebhook(event, sig)).status, 200);
      assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.swipesLeft, 155);

      // A webhook that arrives first credits; verify afterwards adds nothing.
      const order2 = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
      const event2 = Buffer.from(JSON.stringify({ event: "order.paid", payload: { order: { entity: { id: order2.json.orderId, amount_paid: 39900 } } } }));
      const sig2 = crypto.createHmac("sha256", "whsec_test").update(event2).digest("hex");
      assert.equal((await handleWebhook(event2, sig2)).status, 200);
      assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.swipesLeft, 305);
      const sig2Checkout = crypto.createHmac("sha256", "rzp_test_secret").update(`${order2.json.orderId}|pay_2`).digest("hex");
      const late = await api("POST", "/payment/verify", { token: rec.token, body: { orderId: order2.json.orderId, paymentId: "pay_2", signature: sig2Checkout } });
      assert.equal(late.json.added, 0);

      // A wrong amount is acknowledged but never credited.
      const order3 = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
      const event3 = Buffer.from(JSON.stringify({ event: "payment.captured", payload: { payment: { entity: { id: "pay_3", order_id: order3.json.orderId, amount: 100 } } } }));
      const sig3 = crypto.createHmac("sha256", "whsec_test").update(event3).digest("hex");
      assert.equal((await handleWebhook(event3, sig3)).status, 200);
      assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.swipesLeft, 305);

      // Over HTTP the signature needs the raw bytes; without them it answers 501, never a guess.
      const http = await api("POST", "/payment/webhook", { body: { event: "payment.captured" } });
      assert.ok([400, 501].includes(http.status), `unexpected ${http.status}`);
      delete process.env.RAZORPAY_WEBHOOK_SECRET;
      assert.equal((await api("POST", "/payment/webhook", { body: {} })).status, 503);
    } finally {
      globalThis.fetch = realFetch;
      delete process.env.RAZORPAY_KEY_ID;
      delete process.env.RAZORPAY_KEY_SECRET;
    }
  });

  it("does not let a demo order be credited once real keys are configured", async () => {
    const rec = await signup("recruiter", "Demo Then Real");
    const order = await api("POST", "/payment/order", { token: rec.token, body: { planId: "starter" } });
    assert.equal(order.json.mode, "demo");
    process.env.RAZORPAY_KEY_ID = "rzp_test_key";
    process.env.RAZORPAY_KEY_SECRET = "rzp_test_secret";
    try {
      const res = await api("POST", "/payment/verify", { token: rec.token, body: { orderId: order.json.orderId } });
      assert.equal(res.status, 503);
    } finally {
      delete process.env.RAZORPAY_KEY_ID;
      delete process.env.RAZORPAY_KEY_SECRET;
    }
  });
});

describe("candidate stats from the new tables", () => {
  it("counts views, wishlists and shortlists; names only companies that made contact", async () => {
    const tag = unique();
    const cand = await h.candidateWithProfile(`${tag} Watched`);
    const { rec: viewer } = await hc.recruiterWithJob("Viewer Rec");
    const { rec: shortlister } = await hc.recruiterWithJob("Shortlister Rec", { signupOptions: { company: "Hidden Hire" } });
    const { rec: tasker } = await hc.recruiterWithJob("Tasker Rec", { signupOptions: { company: "Task Co" } });
    const { rec: interviewer } = await hc.recruiterWithJob("Interviewer Rec", { signupOptions: { company: "Interview Co" } });

    await hc.swipe(viewer, cand.uid, "left");
    await api("PUT", `/company/wishlist/${cand.uid}`, { token: viewer.token, body: { wishlisted: true } });
    await hc.swipe(shortlister, cand.uid, "right");
    await hc.swipe(tasker, cand.uid, "right");
    await hc.swipe(interviewer, cand.uid, "right");

    const mid = await api("GET", "/candidates/me/stats", { token: cand.token });
    assert.deepEqual(
      [mid.json.viewedCount, mid.json.wishlistedCount, mid.json.shortlistedCount, mid.json.hiddenCount, mid.json.shortlistedBy.length],
      [4, 1, 3, 3, 0],
    );
    assert.equal(JSON.stringify(mid.json).includes("Hidden Hire"), false);

    await prisma.hiringTask.create({
      data: { companyId: tasker.uid, candidateId: cand.uid, title: "Build a todo app", dueAt: new Date(Date.now() + 86400000 * 3) },
    });
    await prisma.interview.create({
      data: { companyId: interviewer.uid, candidateId: cand.uid, slots: [new Date(Date.now() + 86400000)], status: "proposed" },
    });
    // The candidate's own chat message is not company contact.
    await prisma.chatMessage.create({ data: { companyId: shortlister.uid, candidateId: cand.uid, senderId: cand.uid, text: "hello" } });

    const after = await api("GET", "/candidates/me/stats", { token: cand.token });
    assert.equal(after.json.hiddenCount, 1);
    assert.deepEqual(after.json.shortlistedBy.map((s) => s.companyName).sort(), ["Interview Co", "Task Co"]);
    for (const entry of after.json.shortlistedBy) {
      assert.equal(entry.stage, "shortlisted");
      assert.equal(entry.hiringFor, "Flutter Developer");
      assert.equal(entry.companyId, entry.recruiterId);
    }
  });
});
