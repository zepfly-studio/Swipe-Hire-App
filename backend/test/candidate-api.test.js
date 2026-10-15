// Phase 1 (candidate side) API tests: profile validation, resume autofill,
// taxonomy, active ring, preferences, stats anonymity and deck ranking.
// Same harness as api.test.js (real app, real dev database, real HTTP).

const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const h = require("./helpers");
const hc = require("./hiring-helpers");
const { api, signup, prisma } = h;

before(() => h.start());
after(() => h.stop());

const DAY = 24 * 60 * 60 * 1000;

// A one-page PDF with `lines` of text, with a correct cross-reference table.
function pdfWith(lines) {
  const esc = (s) => s.replace(/[\\()]/g, (c) => `\\${c}`);
  const content = `BT /F1 11 Tf 40 780 Td 14 TL ${lines.map((l) => `(${esc(l)}) Tj T*`).join(" ")} ET`;
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let out = "%PDF-1.4\n";
  const offsets = [];
  objects.forEach((body, i) => {
    offsets.push(out.length);
    out += `${i + 1} 0 obj\n${body}\nendobj\n`;
  });
  const xref = out.length;
  out += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`;
  for (const off of offsets) out += `${String(off).padStart(10, "0")} 00000 n \n`;
  out += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;
  return Buffer.from(out, "latin1");
}

async function upload(token, buffer, { name = "resume.pdf", type = "application/pdf", field = "resume" } = {}) {
  const form = new FormData();
  if (buffer) form.append(field, new Blob([buffer], { type }), name);
  const res = await fetch(`${h.getBase()}/candidates/me/resume/autofill`, {
    method: "POST",
    headers: token ? { Authorization: `Bearer ${token}` } : {},
    body: form,
  });
  return { status: res.status, json: await res.json().catch(() => ({})) };
}

// Phase 2 decks need a posting and swipe credits (and the 30-card page cap),
// so a recruiter without either gets a generous job and balance on demand.
const prepared = new Set();
async function prepare(token) {
  if (prepared.has(token)) return;
  prepared.add(token);
  const me = await api("GET", "/users/me", { token });
  const rec = { token, uid: me.json.uid, name: me.json.name };
  const mine = await api("GET", "/jobs/mine", { token });
  if (mine.json.jobs.length === 0) await h.postJob(rec, { salaryMaxLpa: 1000, salaryMinLpa: 0 });
  await hc.giveSwipes(rec, 1000);
}

async function deckIds(token, query = "") {
  await prepare(token);
  const ids = [];
  let cursor = "";
  for (let i = 0; i < 40; i++) {
    const page = await api("GET", `/candidates?limit=30${query}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`, { token });
    assert.equal(page.status, 200, JSON.stringify(page.json));
    ids.push(...page.json.candidates.map((c) => c.id));
    if (!page.json.hasMore) break;
    cursor = page.json.nextCursor;
  }
  return ids;
}

describe("candidate profile", () => {
  it("saves every new field and returns the full profile to its owner", async () => {
    const cand = await signup("candidate", "Full Profile");
    const res = await api("PUT", "/candidates/me/profile", {
      token: cand.token,
      body: {
        ...h.profileBody,
        gender: "Female",
        phone: "9876543210",
        degree: "B.Tech (CSE)",
        college: "VIT Vellore",
        graduationYear: 2021,
        currentPost: "Mobile Developer",
        expectedSalaryLpa: 1200000, // rupees: stored as LPA
        expectedSalaryMaxLpa: 18,
        salaryNegotiable: true,
        workModes: ["remote", "hybrid", "teleport"],
        jobTypes: ["full-time"],
      },
    });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.gender, "Female");
    assert.equal(res.json.phone, "9876543210");
    assert.equal(res.json.age, 26);
    assert.equal(res.json.degree, "B.Tech (CSE)");
    assert.equal(res.json.college, "VIT Vellore");
    assert.equal(res.json.graduationYear, 2021);
    assert.equal(res.json.currentPost, "Mobile Developer");
    assert.equal(res.json.expectedSalaryLpa, 12);
    assert.equal(res.json.expectedSalaryMaxLpa, 18);
    assert.equal(res.json.salaryNegotiable, true);
    assert.deepEqual(res.json.workModes, ["remote", "hybrid"]);
    assert.deepEqual(res.json.jobTypes, ["full-time"]);
    assert.deepEqual(res.json.preferredLocations, []);
    assert.equal(res.json.openToWork, true);
    assert.ok(Date.now() - new Date(res.json.activeAt).getTime() < 60000);

    const again = await api("GET", "/candidates/me/profile", { token: cand.token });
    assert.deepEqual(again.json, res.json);

    // A later save that leaves the optional fields out keeps them.
    const { college, ...withoutCollege } = h.profileBody;
    const keep = await api("PUT", "/candidates/me/profile", { token: cand.token, body: { ...withoutCollege, about: "Updated" } });
    assert.equal(keep.json.about, "Updated");
    assert.equal(keep.json.college, "VIT Vellore", "optional fields that were not sent are kept");
    assert.equal(keep.json.graduationYear, 2021);
    assert.deepEqual(keep.json.workModes, ["remote", "hybrid"]);
  });

  it("answers 400 with { error, field } for invalid input", async () => {
    const cand = await signup("candidate", "Invalid Profile");
    const put = (body) => api("PUT", "/candidates/me/profile", { token: cand.token, body });
    const cases = [
      [{ ...h.profileBody, desiredRole: "" }, "desiredRole"],
      [{ ...h.profileBody, phone: "" }, "phone"],
      [{ ...h.profileBody, phone: "12345" }, "phone"],
      [{ ...h.profileBody, age: 15 }, "age"],
      [{ ...h.profileBody, age: 80 }, "age"],
      [{ ...h.profileBody, gender: "" }, "gender"],
      [{ ...h.profileBody, location: "" }, "location"],
      [{ ...h.profileBody, qualification: "" }, "qualification"],
      [{ ...h.profileBody, degree: "" }, "degree"],
      [{ ...h.profileBody, skills: [] }, "skills"],
      [{ ...h.profileBody, skills: Array.from({ length: 31 }, (_, i) => `Skill${i}`) }, "skills"],
      [{ ...h.profileBody, experience: "" }, "experience"],
      [{ ...h.profileBody, expectedSalaryLpa: 0 }, "expectedSalaryLpa"],
      [{ ...h.profileBody, expectedSalaryLpa: 10, expectedSalaryMaxLpa: 8 }, "expectedSalaryMaxLpa"],
      [{ ...h.profileBody, graduationYear: 1950 }, "graduationYear"],
      [{ ...h.profileBody, graduationYear: 2050 }, "graduationYear"],
    ];
    for (const [body, field] of cases) {
      const res = await put(body);
      assert.equal(res.status, 400, `${field}: ${JSON.stringify(res.json)}`);
      assert.equal(res.json.field, field);
      assert.equal(typeof res.json.error, "string");
      assert.ok(res.json.error.length > 0);
    }
    assert.equal((await put(h.profileBody)).status, 200);
  });

  it("shows a recruiter a card without age, gender, phone or email", async () => {
    const rec = await signup("recruiter", "Privacy Rec");
    const tag = `Pv${Date.now() % 100000}`;
    const cand = await h.candidateWithProfile("Privacy Cand", { desiredRole: `${tag} Dev`, college: "IIT Bombay", degree: "B.Tech (CSE)" });

    await prepare(rec.token);
    const list = await api("GET", `/candidates?q=${tag}`, { token: rec.token });
    const card = list.json.candidates.find((c) => c.id === cand.uid);
    assert.ok(card);
    const one = await api("GET", `/candidates/${cand.uid}`, { token: rec.token });
    for (const c of [card, one.json]) {
      for (const key of ["age", "gender", "phone", "email"]) assert.equal(key in c, false, `card leaks ${key}`);
      assert.equal(c.role, `${tag} Dev`);
      assert.equal(c.degree, "B.Tech (CSE)");
      assert.equal(c.college, "IIT Bombay");
    }
    // Contact details appear only after a right swipe, and only in `contact`.
    assert.equal("contact" in card, false);
    const swiped = await hc.swipe(rec, cand.uid, "right");
    assert.equal(swiped.status, 200, JSON.stringify(swiped.json));
    assert.equal(swiped.json.contact.email, cand.email);
    const funnel = await api("GET", "/company/shortlisted", { token: rec.token });
    const row = funnel.json.candidates[0];
    for (const key of ["age", "gender", "phone", "email"]) assert.equal(key in row, false, `row leaks ${key}`);
    assert.equal(row.contact.email, cand.email);
  });
});

describe("resume autofill", () => {
  it("returns the fields found in a PDF and stores nothing", async () => {
    const cand = await signup("candidate", "Autofill Cand");
    const pdf = pdfWith([
      "Rahul Sharma",
      "Full Stack Developer",
      "Mobile: +91 98765 43210   Jaipur",
      "",
      "Skills",
      "React, Node.js, MongoDB, Python",
      "",
      "Education",
      "B.Tech in Computer Science, Rajasthan Technical University 2016 - 2020",
    ]);
    const res = await upload(cand.token, pdf);
    assert.equal(res.status, 200, JSON.stringify(res.json));
    const f = res.json.fields;
    assert.equal(f.phone, "+919876543210");
    assert.equal(f.desiredRole, "Full Stack Developer");
    assert.equal(f.location, "Jaipur");
    assert.equal(f.degree, "B.Tech (CSE)");
    assert.equal(f.graduationYear, 2020);
    assert.ok(f.skills.includes("React") && f.skills.includes("MongoDB"));
    assert.equal("profile" in res.json, false);
    // No profile row was created or changed by autofill.
    assert.equal(await prisma.candidateProfile.count({ where: { userId: cand.uid } }), 0);
  });

  it("gives empty fields for a PDF without text", async () => {
    const cand = await signup("candidate", "Scanned Cand");
    const res = await upload(cand.token, pdfWith([]));
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.deepEqual(res.json.fields, {});
  });

  it("rejects a missing file, a non-PDF, an oversized file, and other roles", async () => {
    const cand = await signup("candidate", "Bad Upload");
    const rec = await signup("recruiter", "Upload Rec");

    const none = await upload(cand.token, null);
    assert.equal(none.status, 400);
    assert.equal(none.json.error, "Please choose your resume (PDF)");

    const fake = await upload(cand.token, Buffer.from("just some text, not a pdf"));
    assert.equal(fake.status, 400);
    assert.equal(fake.json.error, "This file is not a valid PDF");

    const wrongField = await upload(cand.token, pdfWith(["x"]), { field: "file" });
    assert.equal(wrongField.status, 400);

    const big = Buffer.concat([Buffer.from("%PDF-1.4\n"), Buffer.alloc(5 * 1024 * 1024 + 10, 32)]);
    const tooBig = await upload(cand.token, big);
    assert.equal(tooBig.status, 400);

    const broken = await upload(cand.token, Buffer.from("%PDF-1.4\nthis is not really a pdf"));
    assert.equal(broken.status, 400);
    assert.equal(broken.json.error, "This file is not a valid PDF");

    assert.equal((await upload(rec.token, pdfWith(["x"]))).status, 403);
    assert.equal((await upload(null, pdfWith(["x"]))).status, 401);
  });
});

describe("taxonomy endpoint", () => {
  it("serves the lists to any signed-in user and not to strangers", async () => {
    assert.equal((await api("GET", "/taxonomy")).status, 401);
    for (const role of ["candidate", "recruiter"]) {
      const user = await signup(role, `Tax ${role}`);
      const res = await api("GET", "/taxonomy", { token: user.token });
      assert.equal(res.status, 200);
      assert.deepEqual(Object.keys(res.json).sort(), ["cities", "degrees", "locations", "roles", "skills", "states"]);
      assert.ok(res.json.roles.includes("Web Developer"));
      assert.ok(res.json.skills.includes("Node.js"));
      assert.ok(res.json.degrees.includes("B.Tech (CSE)"));
      assert.equal(res.json.cities[res.json.cities.length - 1], "Remote");
      assert.equal(res.json.states.length, 36);
    }
  });
});

describe("active ring and preferences", () => {
  it("refreshes activeAt", async () => {
    const cand = await h.candidateWithProfile("Ring Cand");
    await prisma.candidateProfile.update({ where: { userId: cand.uid }, data: { activeAt: new Date(Date.now() - 20 * DAY) } });
    const before = await api("GET", "/candidates/me/profile", { token: cand.token });
    assert.ok(Date.now() - new Date(before.json.activeAt).getTime() > 19 * DAY);

    const res = await api("POST", "/candidates/me/active", { token: cand.token });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.ok(Date.now() - new Date(res.json.activeAt).getTime() < 60000);
    assert.equal(res.json.desiredRole, "Flutter Developer");

    const rec = await signup("recruiter", "Ring Rec");
    assert.equal((await api("POST", "/candidates/me/active", { token: rec.token })).status, 403);
    const fresh = await signup("candidate", "No Profile Yet");
    assert.equal((await api("POST", "/candidates/me/active", { token: fresh.token })).status, 404);
  });

  it("saves preferences, filters junk, and hides the candidate when open-to-work is off", async () => {
    const cand = await h.candidateWithProfile("Pref Cand");
    const rec = await signup("recruiter", "Pref Rec");
    assert.ok((await deckIds(rec.token)).includes(cand.uid));

    const res = await api("PUT", "/candidates/me/preferences", {
      token: cand.token,
      body: {
        workModes: ["remote", "onsite", "spaceship"],
        jobTypes: ["internship", "gig"],
        preferredLocations: ["Pune", "pune", "Indore", "", "x".repeat(80), ...Array.from({ length: 15 }, (_, i) => `Town ${i}`)],
      },
    });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.deepEqual(res.json.workModes, ["remote", "onsite"]);
    assert.deepEqual(res.json.jobTypes, ["internship"]);
    assert.equal(res.json.preferredLocations.length, 10);
    assert.equal(res.json.preferredLocations[0], "Pune");
    assert.equal(res.json.preferredLocations[1], "Indore");
    assert.equal(res.json.preferredLocations[2].length, 40);
    assert.equal(res.json.openToWork, true, "openToWork untouched when not sent");
    assert.equal(res.json.desiredRole, "Flutter Developer");

    const bad = await api("PUT", "/candidates/me/preferences", { token: cand.token, body: { openToWork: "false" } });
    assert.equal(bad.status, 400);
    assert.equal(bad.json.field, "openToWork");

    const off = await api("PUT", "/candidates/me/preferences", { token: cand.token, body: { openToWork: false } });
    assert.equal(off.json.openToWork, false);
    assert.equal(off.json.workModes.length, 2, "other preferences kept");
    assert.ok(!(await deckIds(rec.token)).includes(cand.uid), "hidden from the deck");
    assert.ok(!(await deckIds(rec.token, "&sort=newest")).includes(cand.uid), "hidden with sort=newest too");

    const on = await api("PUT", "/candidates/me/preferences", { token: cand.token, body: { openToWork: true } });
    assert.equal(on.json.openToWork, true);
    assert.ok((await deckIds(rec.token)).includes(cand.uid));
  });
});

describe("candidate stats", () => {
  // Rewritten for phase 2: stats now read CandidateSwipe / WishlistEntry and
  // company contact (chat message from the company, interview or task).
  it("counts views and keeps shortlisters anonymous until they make contact", async () => {
    const cand = await h.candidateWithProfile("Stats Cand");
    const { rec: quiet } = await hc.recruiterWithJob("Quiet Rec", { signupOptions: { company: "Quiet Co" } });
    const { rec: wisher } = await hc.recruiterWithJob("Wish Rec");
    const { rec: passer } = await hc.recruiterWithJob("Pass Rec");
    const { rec: contacting } = await hc.recruiterWithJob("Contact Rec", {
      signupOptions: { company: "Reveal Co" },
      job: { title: "Flutter Developer", location: "Pune" },
    });

    const empty = await api("GET", "/candidates/me/stats", { token: cand.token });
    assert.deepEqual(empty.json, { viewedCount: 0, wishlistedCount: 0, shortlistedCount: 0, hiddenCount: 0, shortlistedBy: [] });

    assert.equal((await hc.swipe(quiet, cand.uid, "right")).status, 200);
    assert.equal((await api("PUT", `/company/wishlist/${cand.uid}`, { token: wisher.token, body: { wishlisted: true } })).status, 200);
    assert.equal((await hc.swipe(passer, cand.uid, "left")).status, 200);

    const anon = await api("GET", "/candidates/me/stats", { token: cand.token });
    assert.equal(anon.status, 200, JSON.stringify(anon.json));
    assert.equal(anon.json.viewedCount, 2);
    assert.equal(anon.json.wishlistedCount, 1);
    assert.equal(anon.json.shortlistedCount, 1);
    assert.equal(anon.json.hiddenCount, 1);
    assert.deepEqual(anon.json.shortlistedBy, [], "an uncontacted shortlist names nobody");
    assert.equal(JSON.stringify(anon.json).includes("Quiet Co"), false);

    // A recruiter who shortlists AND contacts the candidate is revealed.
    await api("PUT", "/company/me", {
      token: contacting.token,
      body: { name: "Reveal Co", industry: "IT / Software", location: "Pune", website: "https://reveal.example" },
    });
    assert.equal((await hc.swipe(contacting, cand.uid, "right")).status, 200);
    await prisma.chatMessage.create({
      data: { companyId: contacting.uid, candidateId: cand.uid, senderId: contacting.uid, text: "Hello!" },
    });

    const revealed = await api("GET", "/candidates/me/stats", { token: cand.token });
    assert.equal(revealed.json.viewedCount, 3);
    assert.equal(revealed.json.shortlistedCount, 2);
    assert.equal(revealed.json.hiddenCount, 1, "the quiet recruiter is still hidden");
    assert.equal(revealed.json.shortlistedBy.length, 1);
    const entry = revealed.json.shortlistedBy[0];
    assert.equal(entry.recruiterId, contacting.uid);
    assert.equal(entry.companyId, contacting.uid);
    assert.equal(entry.companyName, "Reveal Co");
    assert.equal(entry.industry, "IT / Software");
    assert.equal(entry.hiringFor, "Flutter Developer");
    assert.equal(entry.location, "Pune");
    assert.equal(entry.verified, false);
    assert.equal(entry.stage, "shortlisted");
    assert.equal(typeof entry.id, "string");
    assert.ok(!Number.isNaN(Date.parse(entry.date)));

    assert.equal((await api("GET", "/candidates/me/stats", { token: quiet.token })).status, 403);
  });
});

describe("deck ranking", () => {
  it("puts stale profiles last, boosts new sign-ups, and pages through all of it", async () => {
    const rec = await signup("recruiter", "Rank Rec");
    await hc.giveSwipes(rec, 1000);
    const tag = `Rk${Date.now() % 100000}`;
    const base = { desiredRole: `${tag} Dev`, skills: ["Flutter", "Dart"], experience: "3 years", location: "Delhi", expectedSalaryLpa: 12 };

    // 85 against the posting below: skills + experience + salary, wrong city.
    const settled = await h.candidateWithProfile("Settled Cand", base);
    // 78 on its own, but under a week old so +10 puts it ahead of the 85.
    const fresh = await h.candidateWithProfile("Fresh Cand", { ...base, experience: "1 year", location: "Pune", expectedSalaryLpa: 40, salaryNegotiable: true });
    // A perfect 100 whose "still looking" ring ran out: goes last anyway.
    const stale = await h.candidateWithProfile("Stale Cand", { ...base, location: "Pune" });
    const hidden = await h.candidateWithProfile("Hidden Cand", { ...base, location: "Pune" });

    await prisma.user.update({ where: { id: settled.uid }, data: { createdAt: new Date(Date.now() - 10 * DAY) } });
    await prisma.user.update({ where: { id: stale.uid }, data: { createdAt: new Date(Date.now() - 10 * DAY) } });
    await prisma.candidateProfile.update({ where: { userId: stale.uid }, data: { activeAt: new Date(Date.now() - 16 * DAY) } });
    await prisma.candidateProfile.update({ where: { userId: hidden.uid }, data: { openToWork: false } });
    await h.postJob(rec, { title: "Flutter Developer", location: "Pune", salaryMaxLpa: 15, minExperienceYears: 2 });

    const res = await api("GET", `/candidates?limit=50&q=${tag}`, { token: rec.token });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.deepEqual(res.json.candidates.map((c) => c.id), [fresh.uid, settled.uid, stale.uid]);
    const scores = Object.fromEntries(res.json.candidates.map((c) => [c.id, c.matchScore]));
    assert.equal(scores[settled.uid], 85);
    assert.equal(scores[fresh.uid], 78, "the card shows the real score, not the boosted one");
    assert.equal(scores[stale.uid], 100);

    // One card per page walks the same order.
    const seen = [];
    let cursor = "";
    for (let i = 0; i < 6; i++) {
      const page = await api("GET", `/candidates?limit=1&q=${tag}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`, { token: rec.token });
      seen.push(...page.json.candidates.map((c) => c.id));
      if (!page.json.hasMore) break;
      cursor = page.json.nextCursor;
    }
    assert.deepEqual(seen, [fresh.uid, settled.uid, stale.uid]);

    // Refreshing the ring brings the stale one back to the top (100 beats the rest).
    await api("POST", "/candidates/me/active", { token: stale.token });
    const after = await api("GET", `/candidates?limit=50&q=${tag}`, { token: rec.token });
    assert.deepEqual(after.json.candidates.map((c) => c.id)[0], stale.uid);

    // sort=newest ignores ranking but still hides open-to-work=off.
    const newest = await api("GET", `/candidates?limit=50&q=${tag}&sort=newest`, { token: rec.token });
    assert.deepEqual(newest.json.candidates.map((c) => c.id), [fresh.uid, stale.uid, settled.uid]);
    assert.ok(!newest.json.candidates.some((c) => c.id === hidden.uid));
  });

  // Adapted for phase 2: with no posting there is no deck at all (NO_JOB).
  it("has no deck without a posting, and ranks by freshness then newest with one", async () => {
    const rec = await signup("recruiter", "No Posting Rec");
    const tag = `Np${Date.now() % 100000}`;
    const active = await h.candidateWithProfile("Active Ring", { desiredRole: `${tag} Dev` });
    const lapsed = await h.candidateWithProfile("Lapsed Ring", { desiredRole: `${tag} Dev` });
    // Signed up later than `active`, but its ring ran out.
    await prisma.candidateProfile.update({ where: { userId: lapsed.uid }, data: { activeAt: new Date(Date.now() - 30 * DAY) } });
    await prisma.user.update({ where: { id: lapsed.uid }, data: { createdAt: new Date(Date.now() + 1000) } });

    const none = await api("GET", `/candidates?limit=50&q=${tag}`, { token: rec.token });
    assert.equal(none.status, 403);
    assert.equal(none.json.code, "NO_JOB");

    await h.postJob(rec, { salaryMaxLpa: 1000, salaryMinLpa: 0 });
    await hc.giveSwipes(rec, 1000);
    const res = await api("GET", `/candidates?limit=50&q=${tag}`, { token: rec.token });
    assert.deepEqual(res.json.candidates.map((c) => c.id), [active.uid, lapsed.uid]);
  });
});
