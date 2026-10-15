// End-to-end API tests: the real Express app, the real database, real HTTP.
//
//   npm test
//
// See helpers.js for the harness (fakes for Firebase and Resend).

const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const h = require("./helpers");
const hc = require("./hiring-helpers");
const { api, signup, prisma, pushes, emails } = h;

const {
  runTaskReminders,
  runReviewReminders,
  runInterviewReminders,
} = require("../src/jobs/taskReminders");
const { cleanupExpiredOtps } = require("../src/jobs/maintenance");

before(() => h.start());
after(() => h.stop());

describe("health", () => {
  it("reports ok when the database is reachable", async () => {
    const res = await api("GET", "/health");
    assert.equal(res.status, 200);
    assert.equal(res.json.ok, true);
  });
});

describe("accounts", () => {
  it("signs up with an OTP and logs in", async () => {
    const user = await signup("candidate", "Cand Account");
    const login = await api("POST", "/auth/login", { body: { email: user.email, password: user.password } });
    assert.equal(login.status, 200);
    assert.equal(login.json.user.role, "candidate");
    assert.equal(login.json.user.emailNotifications, true);
    assert.ok(login.json.token && login.json.firebaseToken);
  });

  it("refuses a short password", async () => {
    const email = h.emailFor("short");
    await api("POST", "/auth/otp/send", { body: { email } });
    await api("POST", "/auth/otp/verify", { body: { email, otp: await h.latestOtp(email) } });
    const res = await api("POST", "/auth/signup", { body: { name: "Short", email, password: "abc123", role: "candidate" } });
    assert.equal(res.status, 400);
  });

  it("will not create an account without a verified OTP", async () => {
    const res = await api("POST", "/auth/signup", {
      body: { name: "No Otp", email: h.emailFor("nootp"), password: "password123", role: "candidate" },
    });
    assert.equal(res.status, 400);
  });

  it("rejects a wrong OTP and answers a wrong password like an unknown email", async () => {
    const email = h.emailFor("wrongotp");
    await api("POST", "/auth/otp/send", { body: { email } });
    assert.equal((await api("POST", "/auth/otp/verify", { body: { email, otp: "000000" } })).status, 400);

    const user = await signup("candidate", "Login Check");
    const wrongPassword = await api("POST", "/auth/login", { body: { email: user.email, password: "nope-nope" } });
    const unknownEmail = await api("POST", "/auth/login", { body: { email: h.emailFor("ghost"), password: "nope-nope" } });
    assert.equal(wrongPassword.status, 401);
    assert.deepEqual(wrongPassword.json, unknownEmail.json);
  });

  it("does not reveal whether an email has an account when resetting a password", async () => {
    const user = await signup("candidate", "Reset Check");
    const known = await api("POST", "/auth/password/forgot", { body: { email: user.email } });
    const unknown = await api("POST", "/auth/password/forgot", { body: { email: h.emailFor("nobody") } });
    assert.equal(known.status, 200);
    assert.deepEqual(Object.keys(known.json).sort(), Object.keys(unknown.json).sort());
  });

  it("resets a password with the emailed code", async () => {
    const user = await signup("candidate", "Reset Flow");
    await api("POST", "/auth/password/forgot", { body: { email: user.email } });
    const reset = await api("POST", "/auth/password/reset", {
      body: { email: user.email, otp: await h.latestOtp(user.email, "reset"), newPassword: "a-new-password" },
    });
    assert.equal(reset.status, 200);
    assert.equal((await api("POST", "/auth/login", { body: { email: user.email, password: "a-new-password" } })).status, 200);
    assert.equal((await api("POST", "/auth/login", { body: { email: user.email, password: user.password } })).status, 401);
  });

  it("validates profile edits and stores the email preference", async () => {
    const rec = await signup("recruiter", "Profile Rec");
    const bad = await api("PATCH", "/users/me", { token: rec.token, body: { phone: "wdwcde2", designation: "3e2d" } });
    assert.equal(bad.status, 400);
    const ok = await api("PATCH", "/users/me", {
      token: rec.token,
      body: { phone: "+91 98765-43210", designation: "HR Manager", emailNotifications: false },
    });
    assert.equal(ok.status, 200);
    assert.equal(ok.json.designation, "HR Manager");
    assert.equal(ok.json.emailNotifications, false);
  });

  it("requires a token for protected routes", async () => {
    assert.equal((await api("GET", "/users/me")).status, 401);
    assert.equal((await api("GET", "/jobs")).status, 401);
    assert.equal((await api("GET", "/notifications")).status, 401);
  });
});

describe("google sign-in", () => {
  it("asks for a role for a new account, then creates it and cleans up the temporary Firebase user", async () => {
    const email = h.emailFor("google");
    h.googleClaims.next = { uid: "temp-firebase-uid", email, name: "Gina Google", email_verified: true };

    const noRole = await api("POST", "/auth/google", { body: { idToken: "fake" } });
    assert.equal(noRole.status, 409);
    assert.equal(noRole.json.needsRole, true);

    const created = await api("POST", "/auth/google", { body: { idToken: "fake", role: "candidate" } });
    assert.equal(created.status, 200);
    assert.equal(created.json.user.email, email);
    assert.equal(created.json.user.name, "Gina Google");
    assert.equal(created.json.user.role, "candidate");
    assert.ok(created.json.firebaseToken);
    assert.ok(h.deletedFirebaseUsers.includes("temp-firebase-uid"));

    // the second time it is a plain sign-in, and the role in the request is ignored
    const again = await api("POST", "/auth/google", { body: { idToken: "fake", role: "recruiter" } });
    assert.equal(again.status, 200);
    assert.equal(again.json.user.uid, created.json.user.uid);
    assert.equal(again.json.user.role, "candidate");
  });

  it("signs in an existing password account that uses the same email", async () => {
    const user = await signup("recruiter", "Both Ways");
    h.googleClaims.next = { uid: "temp-2", email: user.email, name: "Both Ways", email_verified: true };
    const res = await api("POST", "/auth/google", { body: { idToken: "fake" } });
    assert.equal(res.status, 200);
    assert.equal(res.json.user.uid, user.uid);
  });

  it("rejects a token that does not verify and an unverified Google email", async () => {
    h.googleClaims.next = null;
    assert.equal((await api("POST", "/auth/google", { body: { idToken: "garbage" } })).status, 401);
    h.googleClaims.next = { uid: "t", email: h.emailFor("unverified"), email_verified: false };
    assert.equal((await api("POST", "/auth/google", { body: { idToken: "fake", role: "candidate" } })).status, 400);
    h.googleClaims.next = null;
  });
});

describe("recruiter deck, filters and match scores", () => {
  // Adapted for phase 2: the deck needs a job, is capped by swipe credits and
  // is de-duplicated through CandidateSwipe (POST /company/swipe), not the old
  // /swipes table.
  it("lists a finished candidate, keeps roles apart, and remembers swipes per recruiter", async () => {
    const { rec } = await hc.recruiterWithJob("Deck Rec");
    const { rec: other } = await hc.recruiterWithJob("Other Rec");
    const cand = await h.candidateWithProfile("Deck Cand");
    const q = `&q=${encodeURIComponent("Deck Cand")}`;
    const deck = (who) => hc.deckAll(who, q);

    assert.ok((await deck(rec)).some((c) => c.id === cand.uid));
    assert.equal((await api("GET", "/candidates", { token: cand.token })).status, 403);
    assert.equal((await api("GET", "/candidates/me/profile", { token: rec.token })).status, 403);

    const card = (await deck(rec)).find((c) => c.id === cand.uid);
    assert.equal(card.role, "Flutter Developer");
    assert.equal("email" in card, false, "a deck card must not expose contact details");
    assert.equal("contact" in card, false);

    // Wishlisting keeps them on the deck (it is a flag), swiping removes them.
    await api("PUT", `/company/wishlist/${cand.uid}`, { token: rec.token, body: { wishlisted: true } });
    assert.equal((await deck(rec)).find((c) => c.id === cand.uid).wishlisted, true);

    assert.equal((await hc.swipe(rec, cand.uid, "right")).status, 200);
    assert.ok(!(await deck(rec)).some((c) => c.id === cand.uid));
    assert.ok((await deck(other)).some((c) => c.id === cand.uid), "another recruiter still sees them");

    const list = await api("GET", "/company/shortlisted", { token: rec.token });
    assert.equal(list.json.candidates.length, 1);

    assert.equal((await api("POST", "/company/swipe/undo", { token: rec.token })).status, 200);
    assert.ok((await deck(rec)).some((c) => c.id === cand.uid), "undo brings them back");
  });

  it("filters the deck by skills, location, experience, CTC and notice period", async () => {
    const { rec } = await hc.recruiterWithJob("Filter Rec");
    const tag = `Zq${Date.now() % 100000}`;
    const senior = await h.candidateWithProfile("Senior Filter", {
      desiredRole: `${tag} Engineer`, location: "Pune", skills: ["Flutter", "Kotlin"], experience: "6 years", expectedSalaryLpa: 22, noticePeriod: "60 days",
    });
    const junior = await h.candidateWithProfile("Junior Filter", {
      desiredRole: `${tag} Engineer`, location: "Indore", skills: ["Python"], experience: "Fresher", expectedSalaryLpa: 4, noticePeriod: "Immediate",
    });

    const ids = async (query) => {
      const res = await api("GET", `/candidates?limit=50&q=${tag}${query}`, { token: rec.token });
      assert.equal(res.status, 200, JSON.stringify(res.json));
      return res.json.candidates.map((c) => c.id).sort();
    };

    assert.deepEqual(await ids(""), [senior.uid, junior.uid].sort());
    assert.deepEqual(await ids("&skills=kotlin"), [senior.uid]);
    assert.deepEqual(await ids("&skills=PYTHON,rust"), [junior.uid]);
    assert.deepEqual(await ids("&location=indo"), [junior.uid]);
    assert.deepEqual(await ids("&expMin=5"), [senior.uid]);
    assert.deepEqual(await ids("&expMax=1"), [junior.uid]);
    assert.deepEqual(await ids("&ctcMax=10"), [junior.uid]);
    assert.deepEqual(await ids("&ctcMin=15"), [senior.uid]);
    assert.deepEqual(await ids("&noticeMax=30"), [junior.uid]);
    assert.deepEqual(await ids("&skills=kotlin&expMax=1"), []);
  });

  it("scores candidates against the recruiter's open postings and can rank by it", async () => {
    const rec = await signup("recruiter", "Match Rec");
    await hc.giveSwipes(rec, 1000);
    const tag = `Mq${Date.now() % 100000}`;
    const strong = await h.candidateWithProfile("Strong Match", {
      desiredRole: `${tag} Dev`, skills: ["Flutter", "Dart"], experience: "3 years", location: "Pune", expectedSalaryLpa: 12,
    });
    const weak = await h.candidateWithProfile("Weak Match", {
      desiredRole: `${tag} Dev`, skills: ["Cobol"], experience: "Fresher", location: "Delhi", expectedSalaryLpa: 40, salaryNegotiable: true,
    });
    await h.postJob(rec, { title: "Flutter Developer" });

    const res = await api("GET", `/candidates?limit=50&q=${tag}&sort=match`, { token: rec.token });
    const [first, second] = res.json.candidates;
    assert.equal(first.id, strong.uid);
    assert.equal(second.id, weak.uid);
    assert.equal(first.matchScore, 100);
    assert.equal(first.matchJobTitle, "Flutter Developer");
    assert.ok(second.matchScore < 40);
  });

  it("shows the best match first by default, newest first among equals, and pages without gaps", async () => {
    const rec = await signup("recruiter", "Order Rec");
    await hc.giveSwipes(rec, 1000);
    const tag = `Oq${Date.now() % 100000}`;
    const fit = { desiredRole: `${tag} Dev`, skills: ["Flutter", "Dart"], experience: "3 years", location: "Pune", expectedSalaryLpa: 12 };
    const olderFit = await h.candidateWithProfile("Older Fit", fit);
    const weak = await h.candidateWithProfile("Weak Fit", { ...fit, skills: ["Cobol"], experience: "Fresher", location: "Delhi", expectedSalaryLpa: 40, salaryNegotiable: true });
    const newerFit = await h.candidateWithProfile("Newer Fit", fit);
    await h.postJob(rec, { title: "Flutter Developer" });

    // No `sort` at all: same ranking as sort=match.
    const all = await api("GET", `/candidates?limit=50&q=${tag}`, { token: rec.token });
    assert.deepEqual(
      all.json.candidates.map((c) => c.id),
      [newerFit.uid, olderFit.uid, weak.uid],
    );
    assert.equal(all.json.candidates[0].matchScore, 100);

    // One card per page, following the cursor, hits every candidate once.
    const seen = [];
    let cursor = "";
    for (let i = 0; i < 5; i++) {
      const page = await api("GET", `/candidates?limit=1&q=${tag}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`, { token: rec.token });
      seen.push(...page.json.candidates.map((c) => c.id));
      if (!page.json.hasMore) break;
      cursor = page.json.nextCursor;
    }
    assert.deepEqual(seen, [newerFit.uid, olderFit.uid, weak.uid]);

    // Swiping someone away mid-paging must not skip the next candidate.
    const first = await api("GET", `/candidates?limit=1&q=${tag}`, { token: rec.token });
    assert.equal((await hc.swipe(rec, newerFit.uid, "left")).status, 200);
    const next = await api("GET", `/candidates?limit=1&q=${tag}&cursor=${encodeURIComponent(first.json.nextCursor)}`, { token: rec.token });
    assert.equal(next.json.candidates[0].id, olderFit.uid);

    // sort=newest ignores the match ranking.
    const newest = await api("GET", `/candidates?limit=50&q=${tag}&sort=newest`, { token: rec.token });
    assert.deepEqual(newest.json.candidates.map((c) => c.id), [weak.uid, olderFit.uid]);
  });
});

describe("jobs, filters, recommendations and applicants", () => {
  it("posts, browses, saves, applies once, and keeps strangers out", async () => {
    const rec = await signup("recruiter", "Job Rec");
    const cand = await signup("candidate", "Job Cand");

    const job = await h.postJob(rec);
    assert.equal((await api("POST", "/jobs", { token: cand.token, body: { title: "x" } })).status, 403);
    assert.ok((await api("GET", "/jobs", { token: cand.token })).json.jobs.some((j) => j.id === job.id));

    await api("PUT", `/jobs/saved/${job.id}`, { token: cand.token });
    const saved = await api("GET", "/jobs/saved", { token: cand.token });
    assert.deepEqual(saved.json.ids, [job.id]);
    assert.equal(saved.json.jobs[0].title, "Flutter Developer");
    await api("DELETE", `/jobs/saved/${job.id}`, { token: cand.token });
    assert.deepEqual((await api("GET", "/jobs/saved", { token: cand.token })).json.ids, []);

    const applied = await api("POST", `/jobs/${job.id}/apply`, { token: cand.token });
    assert.equal(applied.status, 201);
    assert.equal(applied.json.status, "applied");
    assert.equal((await api("POST", `/jobs/${job.id}/apply`, { token: cand.token })).status, 409);

    await api("PATCH", `/jobs/${job.id}`, { token: rec.token, body: { isOpen: false } });
    const late = await signup("candidate", "Late Cand");
    assert.equal((await api("POST", `/jobs/${job.id}/apply`, { token: late.token })).status, 409);
  });

  it("filters open postings and recommends the ones that fit", async () => {
    const rec = await signup("recruiter", "Filter Jobs Rec");
    const tag = `Jq${Date.now() % 100000}`;
    const fit = await h.postJob(rec, { title: `${tag} Flutter Dev`, skills: ["Flutter", "Dart"], location: "Pune", salaryMaxLpa: 20, minExperienceYears: 2 });
    const remote = await h.postJob(rec, { title: `${tag} Remote QA`, skills: ["Selenium"], location: "Remote", employmentType: "Contract", salaryMinLpa: 3, salaryMaxLpa: 6, minExperienceYears: 0 });
    const senior = await h.postJob(rec, { title: `${tag} Principal`, skills: ["Flutter"], location: "Pune", salaryMaxLpa: 60, minExperienceYears: 10 });

    const cand = await h.candidateWithProfile("Jobs Cand", { skills: ["Flutter", "Dart"], experience: "3 years", location: "Pune", expectedSalaryLpa: 14 });

    const ids = async (query) => (await api("GET", `/jobs?q=${tag}${query}`, { token: cand.token })).json.jobs.map((j) => j.id).sort();
    assert.deepEqual(await ids(""), [fit.id, remote.id, senior.id].sort());
    assert.deepEqual(await ids("&type=contract"), [remote.id]);
    assert.deepEqual(await ids("&remote=1"), [remote.id]);
    assert.deepEqual(await ids("&salaryMin=30"), [senior.id]);
    assert.deepEqual(await ids("&skills=selenium"), [remote.id]);
    assert.deepEqual(await ids("&experience=3"), [fit.id, remote.id].sort(), "hides roles asking for more experience");

    const ranked = await api("GET", `/jobs?q=${tag}&sort=match`, { token: cand.token });
    assert.equal(ranked.json.jobs[0].id, fit.id);
    assert.equal(ranked.json.jobs[0].matchScore, 100);

    const rec2 = await api("GET", "/jobs/recommended", { token: cand.token });
    const recommended = rec2.json.jobs.map((j) => j.id);
    assert.ok(recommended.includes(fit.id));
    assert.ok(rec2.json.jobs.every((j) => j.matchScore >= 40));

    await api("POST", `/jobs/${fit.id}/apply`, { token: cand.token });
    const afterApply = (await api("GET", "/jobs/recommended", { token: cand.token })).json.jobs.map((j) => j.id);
    assert.ok(!afterApply.includes(fit.id), "roles already applied to are not recommended again");
  });

  it("lists applicants per posting, best match first, and counts them", async () => {
    const rec = await signup("recruiter", "Applicants Rec");
    const job = await h.postJob(rec, { skills: ["Flutter", "Dart"], location: "Pune", minExperienceYears: 2 });
    const strong = await h.candidateWithProfile("Applicant Strong", { skills: ["Flutter", "Dart"], experience: "3 years", location: "Pune" });
    const weak = await h.candidateWithProfile("Applicant Weak", { skills: ["Cobol"], experience: "Fresher", location: "Delhi", expectedSalaryLpa: 50 });
    await api("POST", `/jobs/${job.id}/apply`, { token: weak.token });
    await api("POST", `/jobs/${job.id}/apply`, { token: strong.token });

    const res = await api("GET", `/jobs/${job.id}/applicants`, { token: rec.token });
    assert.equal(res.status, 200);
    assert.equal(res.json.applicants.length, 2);
    assert.equal(res.json.applicants[0].candidate.id, strong.uid);
    assert.equal(res.json.applicants[0].candidate.matchScore, 100);
    assert.equal(res.json.applicants[0].opportunity.status, "applied");
    assert.equal("email" in res.json.applicants[0].candidate, false);

    const mine = await api("GET", "/jobs/mine", { token: rec.token });
    assert.equal(mine.json.jobs.find((j) => j.id === job.id).applicantsCount, 2);

    const stranger = await signup("recruiter", "Not The Owner");
    assert.equal((await api("GET", `/jobs/${job.id}/applicants`, { token: stranger.token })).status, 403);
    assert.equal((await api("GET", `/jobs/${job.id}/applicants`, { token: strong.token })).status, 403);

    // a withdrawn application stops counting
    await api("POST", `/opportunities/${res.json.applicants[1].opportunity.id}/withdraw`, { token: weak.token, body: {} });
    const after = await api("GET", "/jobs/mine", { token: rec.token });
    assert.equal(after.json.jobs.find((j) => j.id === job.id).applicantsCount, 1);
  });
});

describe("pipeline, tasks, interview and chat", () => {
  it("runs shortlist -> task -> review -> interview with the right messages and permissions", async () => {
    const rec = await signup("recruiter", "Flow Rec");
    const intruder = await signup("recruiter", "Intruder Rec");
    const cand = await signup("candidate", "Flow Cand");
    const stranger = await signup("candidate", "Stranger Cand");

    let r = await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Flutter Developer", status: "shortlisted" } });
    assert.equal(r.status, 201);
    const oppId = r.json.id;

    r = await api("PUT", `/opportunities/${oppId}`, { token: rec.token, body: { role: "x", status: "taskAssigned" } });
    assert.equal(r.status, 400, "task statuses can only be reached through the task routes");

    const task = { title: "Build a login screen", description: "Use Flutter", dueDate: new Date(Date.now() + 3 * 86400000).toISOString() };
    assert.equal((await api("POST", `/opportunities/${oppId}/tasks`, { token: cand.token, body: task })).status, 403);
    assert.equal((await api("POST", `/opportunities/${oppId}/tasks`, { token: intruder.token, body: task })).status, 403);
    assert.equal((await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "" } })).status, 400);

    r = await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: task });
    assert.equal(r.status, 201);
    assert.equal(r.json.opportunity.status, "taskAssigned");
    const taskId = r.json.task.id;

    const mine = await api("GET", "/opportunities", { token: cand.token });
    assert.equal(mine.json.opportunities[0].task.title, "Build a login screen");
    assert.equal(mine.json.opportunities[0].tasks.length, 1);

    const submitPath = `/opportunities/${oppId}/tasks/${taskId}/submit`;
    assert.equal((await api("POST", submitPath, { token: cand.token, body: {} })).status, 400);
    assert.equal((await api("POST", submitPath, { token: cand.token, body: { link: "javascript:alert(1)" } })).status, 400);
    assert.equal((await api("POST", submitPath, { token: cand.token, body: { fileUrl: "https://evil.example/x.pdf" } })).status, 400);
    assert.equal((await api("POST", submitPath, { token: stranger.token, body: { answer: "x" } })).status, 403);
    r = await api("POST", submitPath, {
      token: cand.token,
      body: { answer: "Done", link: "https://github.com/example/login", fileUrl: "https://res.cloudinary.com/demo/raw/upload/solution.pdf", fileName: "solution.pdf" },
    });
    assert.equal(r.status, 200);
    assert.equal(r.json.opportunity.status, "taskSubmitted");
    assert.equal(r.json.task.submissionFileName, "solution.pdf");

    const reviewPath = `/opportunities/${oppId}/tasks/${taskId}/review`;
    assert.equal((await api("POST", reviewPath, { token: cand.token, body: { decision: "approved" } })).status, 403);
    assert.equal((await api("POST", reviewPath, { token: rec.token, body: { decision: "changes", feedback: "" } })).status, 400);
    r = await api("POST", reviewPath, { token: rec.token, body: { decision: "changes", feedback: "Add an error state" } });
    assert.equal(r.json.opportunity.status, "taskAssigned");
    assert.equal(r.json.task.feedback, "Add an error state");

    await api("POST", submitPath, { token: cand.token, body: { answer: "Fixed" } });
    r = await api("POST", reviewPath, { token: rec.token, body: { decision: "approved", feedback: "Great" } });
    assert.equal(r.json.task.status, "approved");
    assert.equal((await api("POST", submitPath, { token: cand.token, body: { answer: "again" } })).status, 409);

    // interview: one chat card with time, mode and link; no duplicate when nothing changed
    pushes.length = 0;
    emails.length = 0;
    const when = new Date(Date.now() + 5 * 86400000);
    when.setUTCHours(9, 30, 0, 0);
    const interview = { role: "Flutter Developer", status: "interviewScheduled", interviewDate: when.toISOString(), interviewMode: "Video call", interviewDetails: "https://meet.example.com/abc" };
    r = await api("PUT", `/opportunities/${oppId}`, { token: rec.token, body: interview });
    assert.equal(r.status, 200);
    await h.idle();
    let msgs = (await api("GET", `/opportunities/${oppId}/messages`, { token: cand.token })).json.messages;
    const iv = msgs.filter((m) => m.kind === "interview");
    assert.equal(iv.length, 1);
    assert.match(iv[0].text, /3:00 pm IST/i);
    assert.ok(iv[0].text.includes("Video call") && iv[0].text.includes("meet.example.com"));
    assert.ok(pushes.some((p) => /interview/i.test(p.body)));

    const invite = emails.find((e) => e.to === cand.email && /interview/i.test(e.subject));
    assert.ok(invite, "the candidate is emailed");
    assert.equal(invite.attachments[0].filename, "interview.ics");
    assert.match(invite.attachments[0].content.toString(), /BEGIN:VEVENT[\s\S]*DTSTART:\d{8}T\d{6}Z/);

    await api("PUT", `/opportunities/${oppId}`, { token: rec.token, body: interview });
    await h.idle();
    msgs = (await api("GET", `/opportunities/${oppId}/messages`, { token: rec.token })).json.messages;
    assert.equal(msgs.filter((m) => m.kind === "interview").length, 1, "an unchanged save adds nothing");

    await api("PUT", `/opportunities/${oppId}`, {
      token: rec.token,
      body: { ...interview, interviewDate: new Date(when.getTime() + 86400000).toISOString() },
    });
    msgs = (await api("GET", `/opportunities/${oppId}/messages`, { token: rec.token })).json.messages;
    assert.equal(msgs.filter((m) => m.kind === "interview").length, 2, "a reschedule posts a new message");

    assert.equal((await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "Too late" } })).status, 409);

    assert.equal((await api("POST", `/opportunities/${oppId}/messages`, { token: rec.token, body: { text: "Hi" } })).status, 201);
    assert.equal((await api("GET", `/opportunities/${oppId}/messages`, { token: intruder.token })).status, 403);
    assert.equal((await api("PUT", `/opportunities/${oppId}`, { token: cand.token, body: { status: "hired" } })).status, 403);
  });

  it("rejecting a submission marks the candidate not selected", async () => {
    const rec = await signup("recruiter", "Reject Rec");
    const cand = await signup("candidate", "Reject Cand");
    const opp = await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "QA", status: "shortlisted" } });
    const t = await api("POST", `/opportunities/${opp.json.id}/tasks`, { token: rec.token, body: { title: "Quiz" } });
    await api("POST", `/opportunities/${opp.json.id}/tasks/${t.json.task.id}/submit`, { token: cand.token, body: { answer: "meh" } });
    const r = await api("POST", `/opportunities/${opp.json.id}/tasks/${t.json.task.id}/review`, {
      token: rec.token,
      body: { decision: "rejected", feedback: "Not a fit" },
    });
    assert.equal(r.json.opportunity.status, "rejected");
  });

  it("supports several tasks at once and keeps the status honest", async () => {
    const rec = await signup("recruiter", "Multi Rec");
    const cand = await signup("candidate", "Multi Cand");
    const opp = await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Dev", status: "shortlisted" } });
    const oppId = opp.json.id;

    const first = await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "Task one" } });
    const second = await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "Task two", saveAsTemplate: true } });
    assert.equal(first.status, 201);
    assert.equal(second.status, 201);

    // submitting one still leaves the candidate with something to do
    const sub = await api("POST", `/opportunities/${oppId}/tasks/${first.json.task.id}/submit`, { token: cand.token, body: { answer: "one" } });
    assert.equal(sub.json.opportunity.status, "taskAssigned");
    assert.equal(sub.json.opportunity.task.title, "Task two", "the primary task is the one still waiting on the candidate");
    assert.equal(sub.json.opportunity.tasks.length, 2);

    await api("POST", `/opportunities/${oppId}/tasks/${second.json.task.id}/submit`, { token: cand.token, body: { answer: "two" } });
    const approve = await api("POST", `/opportunities/${oppId}/tasks/${first.json.task.id}/review`, { token: rec.token, body: { decision: "approved" } });
    assert.equal(approve.json.opportunity.status, "taskSubmitted");
    const approve2 = await api("POST", `/opportunities/${oppId}/tasks/${second.json.task.id}/review`, { token: rec.token, body: { decision: "approved" } });
    assert.equal(approve2.json.opportunity.status, "taskSubmitted");

    const templates = await api("GET", "/templates", { token: rec.token });
    assert.equal(templates.json.templates.length, 1);
    assert.equal(templates.json.templates[0].title, "Task two");
  });

  it("caps the number of open tasks", async () => {
    const rec = await signup("recruiter", "Cap Rec");
    const cand = await signup("candidate", "Cap Cand");
    const opp = await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Dev", status: "shortlisted" } });
    for (let i = 0; i < 5; i++) {
      const ok = await api("POST", `/opportunities/${opp.json.id}/tasks`, { token: rec.token, body: { title: `Task ${i}` } });
      assert.equal(ok.status, 201);
    }
    const sixth = await api("POST", `/opportunities/${opp.json.id}/tasks`, { token: rec.token, body: { title: "Task 6" } });
    assert.equal(sixth.status, 409);
  });
});

describe("candidate answers: withdraw, offer, interview", () => {
  async function scheduledInterview() {
    const rec = await signup("recruiter", "Answer Rec");
    const cand = await signup("candidate", "Answer Cand");
    const opp = await api("POST", "/opportunities", {
      token: rec.token,
      body: {
        candidateUid: cand.uid, role: "Dev", status: "interviewScheduled",
        interviewDate: new Date(Date.now() + 3 * 86400000).toISOString(), interviewMode: "Video", interviewDetails: "https://meet.example.com/x",
      },
    });
    return { rec, cand, oppId: opp.json.id };
  }

  it("confirms an interview, asks to reschedule, and the recruiter's new time resets the answer", async () => {
    const { rec, cand, oppId } = await scheduledInterview();
    const stranger = await signup("candidate", "Not Mine");

    assert.equal((await api("POST", `/opportunities/${oppId}/interview-response`, { token: stranger.token, body: { decision: "confirm" } })).status, 403);
    assert.equal((await api("POST", `/opportunities/${oppId}/interview-response`, { token: cand.token, body: { decision: "maybe" } })).status, 400);
    assert.equal((await api("POST", `/opportunities/${oppId}/interview-response`, { token: cand.token, body: { decision: "reschedule", note: "" } })).status, 400);

    pushes.length = 0;
    let r = await api("POST", `/opportunities/${oppId}/interview-response`, { token: cand.token, body: { decision: "confirm" } });
    assert.equal(r.status, 200);
    assert.equal(r.json.interviewResponse, "confirmed");

    r = await api("POST", `/opportunities/${oppId}/interview-response`, { token: cand.token, body: { decision: "reschedule", note: "Evenings after 6 pm work" } });
    assert.equal(r.json.interviewResponse, "reschedule_requested");
    assert.equal(r.json.interviewResponseNote, "Evenings after 6 pm work");
    const inbox = await api("GET", "/notifications", { token: rec.token });
    assert.ok(inbox.json.notifications.some((n) => n.type === "interview_reschedule" && n.body.includes("6 pm")));

    // the recruiter moves it: the candidate's answer is cleared
    const current = (await api("GET", `/opportunities/${oppId}`, { token: rec.token })).json;
    const moved = await api("PUT", `/opportunities/${oppId}`, {
      token: rec.token,
      body: {
        role: "Dev", status: "interviewScheduled", interviewMode: "Video", interviewDetails: "https://meet.example.com/x",
        interviewDate: new Date(new Date(current.interviewDate).getTime() + 86400000).toISOString(),
      },
    });
    assert.equal(moved.json.interviewResponse, "");
    assert.equal(moved.json.interviewResponseNote, "");
  });

  it("answers an offer: accept keeps it open for the recruiter, decline withdraws", async () => {
    const rec = await signup("recruiter", "Offer Rec");
    const cand = await signup("candidate", "Offer Cand");
    const cand2 = await signup("candidate", "Offer Cand Two");
    const mk = async (c) =>
      (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: c.uid, role: "Dev", status: "offered", offerSalaryLpa: 15, offerNotes: "Welcome" } })).json.id;
    const a = await mk(cand);
    const b = await mk(cand2);

    assert.equal((await api("POST", `/opportunities/${a}/offer-response`, { token: cand.token, body: { decision: "later" } })).status, 400);
    const accepted = await api("POST", `/opportunities/${a}/offer-response`, { token: cand.token, body: { decision: "accepted" } });
    assert.equal(accepted.json.offerResponse, "accepted");
    assert.equal(accepted.json.status, "offered");
    assert.equal((await api("POST", `/opportunities/${a}/offer-response`, { token: cand.token, body: { decision: "declined" } })).status, 409, "an answer is final");

    const declined = await api("POST", `/opportunities/${b}/offer-response`, { token: cand2.token, body: { decision: "declined" } });
    assert.equal(declined.json.status, "withdrawn");
    assert.equal(declined.json.offerResponse, "declined");

    // nothing to answer once the recruiter hasn't made an offer
    const open = (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "QA", status: "shortlisted" } })).json.id;
    assert.equal((await api("POST", `/opportunities/${open}/offer-response`, { token: cand.token, body: { decision: "accepted" } })).status, 409);
  });

  it("lets a candidate withdraw, and freezes the entry for the recruiter", async () => {
    const rec = await signup("recruiter", "Withdraw Rec");
    const cand = await signup("candidate", "Withdraw Cand");
    const oppId = (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Dev", status: "shortlisted" } })).json.id;

    assert.equal((await api("POST", `/opportunities/${oppId}/withdraw`, { token: rec.token, body: {} })).status, 403);
    const r = await api("POST", `/opportunities/${oppId}/withdraw`, { token: cand.token, body: { reason: "Took another offer" } });
    assert.equal(r.status, 200);
    assert.equal(r.json.status, "withdrawn");

    const msgs = (await api("GET", `/opportunities/${oppId}/messages`, { token: rec.token })).json.messages;
    assert.ok(msgs.some((m) => m.kind === "application" && m.text.includes("Took another offer")));
    assert.equal((await api("POST", `/opportunities/${oppId}/withdraw`, { token: cand.token, body: {} })).status, 409);
    assert.equal(
      (await api("PUT", `/opportunities/${oppId}`, { token: rec.token, body: { role: "Dev", status: "interviewScheduled" } })).status,
      409,
    );
    assert.equal((await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "Late" } })).status, 409);
  });
});

describe("notifications, unread chat and email", () => {
  it("keeps an inbox, counts unread chat, and marks things read", async () => {
    const rec = await signup("recruiter", "Inbox Rec");
    const cand = await signup("candidate", "Inbox Cand");
    const oppId = (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Dev", status: "shortlisted" } })).json.id;
    await api("POST", `/opportunities/${oppId}/tasks`, { token: rec.token, body: { title: "Inbox task" } });

    const inbox = await api("GET", "/notifications", { token: cand.token });
    assert.ok(inbox.json.unreadCount >= 2, "shortlisted + task assigned");
    assert.ok(inbox.json.notifications.some((n) => n.type === "task" && n.body.includes("Inbox task")));
    assert.ok(inbox.json.notifications.every((n) => n.read === false));

    await api("POST", `/opportunities/${oppId}/messages`, { token: rec.token, body: { text: "Hello" } });
    await api("POST", `/opportunities/${oppId}/messages`, { token: rec.token, body: { text: "Are you there?" } });
    await h.idle();

    assert.equal((await api("GET", "/notifications", { token: cand.token })).json.notifications.some((n) => n.type === "chat_message"), false, "chat does not fill the bell");
    const summary = await api("GET", "/notifications/summary", { token: cand.token });
    assert.equal(summary.json.unreadMessages, 2);
    const list = await api("GET", "/opportunities", { token: cand.token });
    assert.equal(list.json.opportunities[0].unreadCount, 2);

    // opening the chat reads it
    await api("GET", `/opportunities/${oppId}/messages`, { token: cand.token });
    assert.equal((await api("GET", "/notifications/summary", { token: cand.token })).json.unreadMessages, 0);
    assert.equal((await api("GET", "/opportunities", { token: cand.token })).json.opportunities[0].unreadCount, 0);
    // ...and the sender's own messages never count for them
    assert.equal((await api("GET", "/notifications/summary", { token: rec.token })).json.unreadMessages, 0);

    const some = inbox.json.notifications[0].id;
    const one = await api("POST", "/notifications/read", { token: cand.token, body: { ids: [some] } });
    assert.equal(one.json.updated, 1);
    assert.equal((await api("GET", "/notifications", { token: cand.token })).json.unreadCount, inbox.json.unreadCount - 1);
    await api("POST", "/notifications/read", { token: cand.token, body: {} });
    assert.equal((await api("GET", "/notifications?unread=1", { token: cand.token })).json.notifications.length, 0);

    // one person's inbox is private
    assert.equal((await api("POST", "/notifications/read", { token: rec.token, body: { ids: [some] } })).json.updated, 0);
  });

  it("emails important updates and honours the opt-out", async () => {
    const rec = await signup("recruiter", "Mail Rec");
    const cand = await signup("candidate", "Mail Cand");
    const quiet = await signup("candidate", "Quiet Cand");
    await api("PATCH", "/users/me", { token: quiet.token, body: { emailNotifications: false } });

    emails.length = 0;
    const a = (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "Dev", status: "shortlisted" } })).json.id;
    await api("POST", `/opportunities/${a}/tasks`, { token: rec.token, body: { title: "Mail task" } });
    const b = (await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: quiet.uid, role: "Dev", status: "shortlisted" } })).json.id;
    await api("POST", `/opportunities/${b}/tasks`, { token: rec.token, body: { title: "Quiet task" } });
    await h.idle();

    assert.ok(emails.some((e) => e.to === cand.email && /task/i.test(e.subject)));
    assert.ok(!emails.some((e) => e.to === quiet.email), "opted-out accounts get nothing");

    emails.length = 0;
    await api("POST", `/opportunities/${a}/tasks/${(await api("GET", `/opportunities/${a}/tasks`, { token: cand.token })).json.tasks[0].id}/submit`, {
      token: cand.token,
      body: { answer: "done" },
    });
    assert.ok(emails.some((e) => e.to === rec.email && /submitted/i.test(e.subject)));
  });
});

describe("company profile and verification", () => {
  it("verifies automatically when the website matches the work email's domain", async () => {
    const domain = `acme${Date.now() % 100000}.dev`;
    const rec = await signup("recruiter", "Company Rec", { domain });

    const none = await api("GET", "/company/me", { token: rec.token });
    assert.equal(none.json.company, null);

    const saved = await api("PUT", "/company/me", {
      token: rec.token,
      body: { name: "Acme Labs", website: `www.${domain}`, about: "We build things.", industry: "Software", size: "11-50", location: "Pune" },
    });
    assert.equal(saved.status, 200);
    assert.equal(saved.json.company.verified, true);
    assert.equal(saved.json.company.verificationStatus, "verified");
    assert.equal(saved.json.company.website, `https://www.${domain}`);

    // postings now carry the verified company
    const job = await h.postJob(rec);
    assert.equal(job.companyName, "Acme Labs");
    assert.equal(job.companyVerified, true);

    const cand = await signup("candidate", "Company Viewer");
    const page = await api("GET", `/company/${saved.json.company.id}`, { token: cand.token });
    assert.equal(page.json.company.name, "Acme Labs");
    assert.equal(page.json.jobs.length, 1);

    // pointing the website somewhere else un-verifies it
    const moved = await api("PUT", "/company/me", { token: rec.token, body: { name: "Acme Labs", website: "https://somewhere-else.org" } });
    assert.equal(moved.json.company.verified, false);
  });

  it("does not verify on a free mail address, but accepts a manual review request", async () => {
    const rec = await signup("recruiter", "Free Mail Rec", { domain: "gmail.com" });
    const saved = await api("PUT", "/company/me", { token: rec.token, body: { name: "Tiny Co", website: "https://gmail.com" } });
    assert.equal(saved.json.company.verified, false);
    assert.equal(saved.json.company.verificationStatus, "unverified");

    assert.equal((await api("PUT", "/company/me", { token: rec.token, body: { name: "x" } })).status, 400);
    assert.equal((await api("PUT", "/company/me", { token: rec.token, body: { name: "Tiny Co", website: "not a url at all ::" } })).status, 400);

    const asked = await api("POST", "/company/me/verification-request", { token: rec.token, body: { note: "GST certificate available" } });
    assert.equal(asked.json.company.verificationStatus, "pending");
    // saving again keeps the request pending
    const resaved = await api("PUT", "/company/me", { token: rec.token, body: { name: "Tiny Co", website: "https://gmail.com" } });
    assert.equal(resaved.json.company.verificationStatus, "pending");

    const cand = await signup("candidate", "Not A Recruiter");
    assert.equal((await api("PUT", "/company/me", { token: cand.token, body: { name: "Nope" } })).status, 403);
  });
});

describe("task templates", () => {
  it("saves, lists and deletes a recruiter's templates, privately", async () => {
    const rec = await signup("recruiter", "Template Rec");
    const other = await signup("recruiter", "Other Template Rec");

    const made = await api("POST", "/templates", { token: rec.token, body: { title: "Take-home", description: "Build a todo app", link: "https://example.com/brief" } });
    assert.equal(made.status, 201);
    assert.equal((await api("POST", "/templates", { token: rec.token, body: { title: "" } })).status, 400);

    assert.equal((await api("GET", "/templates", { token: rec.token })).json.templates.length, 1);
    assert.equal((await api("GET", "/templates", { token: other.token })).json.templates.length, 0);

    await api("DELETE", `/templates/${made.json.id}`, { token: other.token });
    assert.equal((await api("GET", "/templates", { token: rec.token })).json.templates.length, 1, "someone else can't delete it");
    await api("DELETE", `/templates/${made.json.id}`, { token: rec.token });
    assert.equal((await api("GET", "/templates", { token: rec.token })).json.templates.length, 0);
  });
});

describe("background jobs", () => {
  async function pipelineFixture() {
    const rec = await signup("recruiter", "Remind Rec");
    const cand = await signup("candidate", "Remind Cand");
    return { rec, cand };
  }
  const hour = 3600 * 1000;

  it("reminds once about a task due within 24 hours, and only that one", async () => {
    const { rec, cand } = await pipelineFixture();
    const opp = await prisma.opportunity.create({ data: { candidateId: cand.uid, recruiterId: rec.uid, role: "QA", status: "taskAssigned" } });
    const old = new Date(Date.now() - 2 * hour);
    const mk = (title, dueInHours, status = "assigned") =>
      prisma.task.create({ data: { opportunityId: opp.id, title, status, dueDate: new Date(Date.now() + dueInHours * hour), createdAt: old } });
    const soon = await mk("due soon", 5);
    const far = await mk("due in 3 days", 72);
    const submitted = await mk("already submitted", 5, "submitted");
    const overdue = await mk("overdue", -2);

    const first = await runTaskReminders(new Date());
    assert.ok(first.includes(soon.id));
    for (const t of [far, submitted, overdue]) assert.ok(!first.includes(t.id));
    assert.ok(!(await runTaskReminders(new Date())).includes(soon.id), "never twice");

    const inbox = await api("GET", "/notifications", { token: cand.token });
    assert.ok(inbox.json.notifications.some((n) => n.type === "task_reminder"));
  });

  it("nudges the recruiter about a submission that has waited a day", async () => {
    const { rec, cand } = await pipelineFixture();
    const opp = await prisma.opportunity.create({ data: { candidateId: cand.uid, recruiterId: rec.uid, role: "QA", status: "taskSubmitted" } });
    const waiting = await prisma.task.create({
      data: { opportunityId: opp.id, title: "Waiting", status: "submitted", submittedAt: new Date(Date.now() - 30 * hour) },
    });
    const fresh = await prisma.task.create({
      data: { opportunityId: opp.id, title: "Fresh", status: "submitted", submittedAt: new Date(Date.now() - 2 * hour) },
    });

    const first = await runReviewReminders(new Date());
    assert.ok(first.includes(waiting.id));
    assert.ok(!first.includes(fresh.id));
    assert.ok(!(await runReviewReminders(new Date())).includes(waiting.id), "never twice");
    assert.ok((await api("GET", "/notifications", { token: rec.token })).json.notifications.some((n) => n.type === "review_reminder"));
  });

  it("reminds both sides a day before and an hour before an interview", async () => {
    const { rec, cand } = await pipelineFixture();
    const make = (hoursAway) =>
      prisma.opportunity.create({
        data: { candidateId: cand.uid, recruiterId: rec.uid, role: "Dev", status: "interviewScheduled", interviewDate: new Date(Date.now() + hoursAway * hour) },
      });
    const tomorrow = await make(20);
    const soon = await make(0.5);
    const farAway = await make(72);

    const first = await runInterviewReminders(new Date());
    assert.ok(first.includes(tomorrow.id) && first.includes(soon.id));
    assert.ok(!first.includes(farAway.id));
    assert.equal((await prisma.opportunity.findUnique({ where: { id: tomorrow.id } })).interviewRemindersSent, 1);
    assert.equal((await prisma.opportunity.findUnique({ where: { id: soon.id } })).interviewRemindersSent, 2, "booked within the hour: only the last reminder");
    assert.ok(!(await runInterviewReminders(new Date())).includes(tomorrow.id), "the day-before one goes once");

    // an hour before it: the second reminder
    const later = new Date(Date.now() + 19.5 * hour);
    assert.ok((await runInterviewReminders(later)).includes(tomorrow.id));
    assert.equal((await prisma.opportunity.findUnique({ where: { id: tomorrow.id } })).interviewRemindersSent, 2);

    for (const who of [cand, rec]) {
      const inbox = await api("GET", "/notifications", { token: who.token });
      assert.ok(inbox.json.notifications.some((n) => n.type === "interview_reminder"));
    }
  });

  it("removes OTP codes that expired more than a day ago", async () => {
    const email = h.emailFor("expired");
    await prisma.otpCode.create({ data: { email, code: "111111", expiresAt: new Date(Date.now() - 3 * 86400000) } });
    await prisma.otpCode.create({ data: { email, code: "222222", expiresAt: new Date(Date.now() + 600000) } });
    await cleanupExpiredOtps();
    const left = await prisma.otpCode.findMany({ where: { email } });
    assert.deepEqual(left.map((o) => o.code), ["222222"]);
    await prisma.otpCode.deleteMany({ where: { email } });
  });
});

describe("account deletion", () => {
  it("cascades everything the account owns", async () => {
    const rec = await signup("recruiter", "Delete Rec");
    const cand = await signup("candidate", "Delete Cand");
    const opp = await api("POST", "/opportunities", { token: rec.token, body: { candidateUid: cand.uid, role: "QA", status: "shortlisted" } });
    await api("POST", `/opportunities/${opp.json.id}/messages`, { token: rec.token, body: { text: "hi" } });
    await api("PUT", "/company/me", { token: rec.token, body: { name: "Doomed Co" } });
    await api("POST", "/templates", { token: rec.token, body: { title: "Doomed template" } });

    assert.equal((await api("DELETE", "/users/me", { token: cand.token })).status, 200);
    assert.equal(await prisma.opportunity.count({ where: { id: opp.json.id } }), 0);
    assert.equal(await prisma.message.count({ where: { opportunityId: opp.json.id } }), 0);
    assert.equal(await prisma.notification.count({ where: { userId: cand.uid } }), 0);
    assert.equal((await api("GET", "/users/me", { token: cand.token })).status, 401);

    assert.equal((await api("DELETE", "/users/me", { token: rec.token })).status, 200);
    assert.equal(await prisma.company.count({ where: { ownerId: rec.uid } }), 0);
    assert.equal(await prisma.taskTemplate.count({ where: { recruiterId: rec.uid } }), 0);
  });
});
