// Phase 4: company verification (work-email code, GST review by an admin),
// the admin routes, and the "reset on rename" rule.

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { describe, it, before, after, afterEach } = require("node:test");
const jwt = require("jsonwebtoken");
const h = require("./helpers");

const { api, prisma, emails, signup } = h;
const mailer = require("../src/lib/mailer");

let counter = 0;
const GSTIN = "27ABCDE1234F1Z5";
const day = 24 * 60 * 60 * 1000;

before(async () => {
  await h.start();
});
after(() => h.stop());

const originalMailer = { ...mailer };
afterEach(() => {
  Object.assign(mailer, originalMailer);
});

/** A recruiter whose login email is on its own work domain. */
async function workRecruiter({ website } = {}) {
  const domain = `verify${Date.now() % 1000000}x${++counter}.dev`;
  const rec = await signup("recruiter", "Work Rec", { domain });
  rec.domain = domain;
  const body = { name: `Verify Co ${counter}`, location: "Pune" };
  if (website !== undefined) body.website = website;
  const saved = await api("PUT", "/company/me", { token: rec.token, body });
  assert.equal(saved.status, 200, JSON.stringify(saved.json));
  rec.company = saved.json.company;
  return rec;
}

/** Puts the website straight into the row (the PUT route would auto-verify it). */
async function setWebsite(rec, website) {
  await prisma.company.update({ where: { ownerId: rec.uid }, data: { website } });
}

const companyRow = (rec) => prisma.company.findUnique({ where: { ownerId: rec.uid } });
const send = (rec) => api("POST", "/company/verification/email/send", { token: rec.token });
const confirm = (rec, code) => api("POST", "/company/verification/email/confirm", { token: rec.token, body: { code } });

/** The code the app emailed to this address most recently. */
function emailedCode(to) {
  const mail = [...emails].reverse().find((e) => e.to === to && /is your Swipe Hire code$/.test(e.subject));
  assert.ok(mail, `no code email for ${to}`);
  return mail.subject.split(" ")[0];
}

function wrongCodeFor(code) {
  return code === "000000" ? "111111" : "000000";
}

describe("work-email verification", () => {
  it("refuses a personal login email", async () => {
    for (const domain of ["gmail.com", "yahoo.co.in", "outlook.com"]) {
      const rec = await signup("recruiter", "Personal Rec", { domain });
      await api("PUT", "/company/me", { token: rec.token, body: { name: "Tiny Co", website: "https://tiny.example.org" } });
      const res = await send(rec);
      assert.equal(res.status, 400, domain);
      assert.equal(res.json.error, "Your login email is a personal email. Use GST verification, or sign up with your work email.");
    }
  });

  it("needs a company website, and it has to match the email domain", async () => {
    const rec = await workRecruiter();
    const noSite = await send(rec);
    assert.equal(noSite.status, 400);
    assert.equal(noSite.json.error, "Add your company website in your company profile first, so we can match your email to it.");

    await setWebsite(rec, "https://www.somewhere-else.org");
    const mismatch = await send(rec);
    assert.equal(mismatch.status, 400);
    assert.equal(mismatch.json.error, `Your email (@${rec.domain}) does not match your website (somewhere-else.org).`);

    const none = await signup("recruiter", "No Company Yet", { domain: `nocompany${++counter}.dev` });
    assert.equal((await send(none)).status, 400, "no company row: add the website first");

    const cand = await signup("candidate", "Not A Recruiter");
    assert.equal((await send(cand)).status, 403);
  });

  it("emails a code, rejects a wrong one, and verifies with the right one", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://careers.${rec.domain}`); // a subdomain of the email domain matches

    const sent = await send(rec);
    assert.equal(sent.status, 200, JSON.stringify(sent.json));
    assert.equal(sent.json.sentTo, rec.email);
    assert.equal(sent.json.devCode, undefined, "no code in the response when email is configured");

    const code = emailedCode(rec.email);
    assert.match(code, /^\d{6}$/);
    const state = (await companyRow(rec)).verificationOtp;
    assert.equal(state.hash, crypto.createHash("sha256").update(code).digest("hex"));
    assert.ok(!JSON.stringify(state).includes(`"${code}"`), "plain code is not stored");

    const wrong = await confirm(rec, wrongCodeFor(code));
    assert.equal(wrong.status, 400);
    assert.equal(wrong.json.error, "Wrong code, please check and try again");

    const ok = await confirm(rec, code);
    assert.equal(ok.status, 200, JSON.stringify(ok.json));
    assert.equal(ok.json.verification.status, "verified");
    assert.equal(ok.json.verification.method, "email");
    assert.ok(ok.json.verification.verifiedAt);

    const status = await api("GET", "/company/verification", { token: rec.token });
    assert.deepEqual(status.json.verification, ok.json.verification);
    assert.equal(status.json.website, `https://careers.${rec.domain}`);
    assert.equal(status.json.email, rec.email);

    const me = (await api("GET", "/company/me", { token: rec.token })).json.company;
    assert.equal(me.verified, true);
    assert.equal(me.verificationStatus, "verified");
    assert.equal(me.verificationMethod, "email");

    const notes = await prisma.notification.findMany({ where: { userId: rec.uid, type: "verified" } });
    assert.equal(notes.length, 1);
    assert.equal(notes[0].link, "/company/verify");
    assert.equal(notes[0].title, "Your company is verified ✓");

    assert.equal((await send(rec)).status, 409, "already verified");
  });

  it("counts wrong attempts per code and locks a code after five", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://${rec.domain}`);
    await send(rec);
    const code = emailedCode(rec.email);

    for (let i = 0; i < 5; i++) assert.equal((await confirm(rec, wrongCodeFor(code))).status, 400);
    const locked = await confirm(rec, code);
    assert.equal(locked.status, 429);
    assert.equal(locked.json.error, "Too many wrong attempts, please request a new code");

    // A new code starts over.
    assert.equal((await send(rec)).status, 200);
    const fresh = emailedCode(rec.email);
    assert.equal((await confirm(rec, fresh)).status, 200);
  });

  it("handles expiry and a missing code", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://${rec.domain}`);
    const never = await confirm(rec, "123456");
    assert.equal(never.status, 400);
    assert.equal(never.json.error, "Code expired, please request a new one");

    await send(rec);
    const code = emailedCode(rec.email);
    const row = await companyRow(rec);
    await prisma.company.update({
      where: { id: row.id },
      data: { verificationOtp: { ...row.verificationOtp, expires: new Date(Date.now() - 1000).toISOString() } },
    });
    const late = await confirm(rec, code);
    assert.equal(late.status, 400);
    assert.equal(late.json.error, "Code expired, please request a new one");
  });

  it("limits sends and failed tries per day", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://${rec.domain}`);
    for (let i = 0; i < 5; i++) assert.equal((await send(rec)).status, 200, `send ${i + 1}`);
    const sixth = await send(rec);
    assert.equal(sixth.status, 429);
    assert.equal(sixth.json.error, "Too many codes requested today. Please try again tomorrow, or use GST verification.");

    // After the 24h window the counters start over.
    const row = await companyRow(rec);
    await prisma.company.update({
      where: { id: row.id },
      data: { verificationOtp: { ...row.verificationOtp, windowStart: new Date(Date.now() - day - 1000).toISOString() } },
    });
    assert.equal((await send(rec)).status, 200);

    // 15 failed tries in a window also block new codes.
    const failing = await workRecruiter();
    await setWebsite(failing, `https://${failing.domain}`);
    await send(failing);
    const frow = await companyRow(failing);
    await prisma.company.update({
      where: { id: frow.id },
      data: { verificationOtp: { ...frow.verificationOtp, fails: 15 } },
    });
    assert.equal((await send(failing)).status, 429);
  });

  it("returns the code when email is not configured outside production, and fails cleanly otherwise", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://${rec.domain}`);

    mailer.emailConfigured = () => false;
    const dev = await send(rec);
    assert.equal(dev.status, 200);
    assert.match(dev.json.devCode, /^\d{6}$/);
    mailer.emailConfigured = originalMailer.emailConfigured;

    // The test sender refusing a recipient falls back to showing the code (non-production).
    mailer.sendNotificationEmail = async () => {
      const err = new Error("only the account owner");
      err.response = { body: { statusCode: 403 } };
      throw err;
    };
    const refused = await send(rec);
    assert.equal(refused.status, 200);
    assert.match(refused.json.devCode, /^\d{6}$/);

    // Any other failure is a 502 and does not use up one of today's sends.
    mailer.sendNotificationEmail = async () => {
      throw new Error("provider down");
    };
    const before = (await companyRow(rec)).verificationOtp.sends;
    const down = await send(rec);
    assert.equal(down.status, 502);
    assert.equal((await companyRow(rec)).verificationOtp.sends, before);

    assert.equal((await confirm(rec, refused.json.devCode)).status, 200);
  });
});

describe("GST verification and the admin queue", () => {
  let admin;
  const savedAdminEmails = process.env.ADMIN_EMAILS;

  before(async () => {
    admin = await signup("recruiter", "Admin Person", { domain: `admins${Date.now() % 100000}.dev` });
    process.env.ADMIN_EMAILS = `${admin.email.toUpperCase()}, someone-else@example.com`;
  });
  after(() => {
    if (savedAdminEmails === undefined) delete process.env.ADMIN_EMAILS;
    else process.env.ADMIN_EMAILS = savedAdminEmails;
  });

  const submitGst = (rec, gstin = GSTIN) => api("POST", "/company/verification/gst", { token: rec.token, body: { gstin } });
  const decide = (companyId, approve) =>
    api("POST", `/admin/verifications/${companyId}`, { token: admin.token, body: { approve } });

  it("validates the GSTIN, goes pending, and shows in the admin list oldest first", async () => {
    const first = await workRecruiter({ website: "https://gst-one.example.org" });
    const second = await workRecruiter({ website: "https://gst-two.example.org" });

    const bad = await submitGst(first, "12345");
    assert.equal(bad.status, 400);
    assert.equal(bad.json.error, "Please enter a valid 15-character GSTIN");
    assert.equal(bad.json.field, "gstin");

    const ok = await submitGst(first, ` ${GSTIN.toLowerCase()} `);
    assert.equal(ok.status, 200, JSON.stringify(ok.json));
    assert.deepEqual(ok.json.verification, { status: "pending", method: "gst" });
    await submitGst(second);

    const status = await api("GET", "/company/verification", { token: first.token });
    assert.equal(status.json.verification.status, "pending");
    assert.equal(status.json.verification.method, "gst");
    assert.equal(status.json.gstin, GSTIN);
    const own = (await api("GET", "/company/me", { token: first.token })).json.company;
    assert.equal(own.verificationStatus, "pending");
    assert.equal(own.verified, false);
    assert.equal(own.gstin, GSTIN);
    assert.equal(own.verificationMethod, "gst");

    const list = await api("GET", "/admin/verifications", { token: admin.token });
    assert.equal(list.status, 200);
    const ids = list.json.companies.map((c) => c.id);
    assert.ok(ids.includes(first.uid) && ids.includes(second.uid));
    assert.ok(ids.indexOf(first.uid) < ids.indexOf(second.uid), "oldest first");
    const row = list.json.companies.find((c) => c.id === first.uid);
    assert.equal(row.companyName, first.company.name);
    assert.equal(row.website, "https://gst-one.example.org");
    assert.equal(row.location, "Pune");
    assert.equal(row.gstin, GSTIN);
    assert.deepEqual(row.contact, { name: "Work Rec", email: first.email });
    assert.ok(!Number.isNaN(Date.parse(row.requestedAt)));

    // Clean the queue so other runs see only their own.
    await decide(first.uid, false);
    await decide(second.uid, false);
  });

  it("is admin only", async () => {
    const rec = await workRecruiter();
    await submitGst(rec);
    const cand = await signup("candidate", "Curious Candidate");
    for (const who of [rec, cand]) {
      const list = await api("GET", "/admin/verifications", { token: who.token });
      assert.equal(list.status, 403);
      assert.equal(list.json.error, "Admins only");
      assert.equal((await api("POST", `/admin/verifications/${rec.uid}`, { token: who.token, body: { approve: true } })).status, 403);
    }
    assert.equal((await api("GET", "/admin/verifications")).status, 401);
    assert.equal((await companyRow(rec)).verificationStatus, "pending", "a non-admin cannot approve");
    await decide(rec.uid, false);
  });

  it("an admin's own email must be verified", async () => {
    await prisma.user.update({ where: { id: admin.uid }, data: { emailVerified: false } });
    assert.equal((await api("GET", "/admin/verifications", { token: admin.token })).status, 403);
    await prisma.user.update({ where: { id: admin.uid }, data: { emailVerified: true } });
    assert.equal((await api("GET", "/admin/verifications", { token: admin.token })).status, 200);
    assert.equal((await api("GET", "/users/me", { token: admin.token })).json.isAdmin, true);
  });

  it("approval verifies the company and tells the owner and every teammate", async () => {
    const rec = await workRecruiter();
    const member = await prisma.user.create({
      data: {
        name: "Team Mate",
        email: h.emailFor("recruiter"),
        passwordHash: "x",
        role: "recruiter",
        company: rec.company.name,
        companyOwnerId: rec.uid,
        profileComplete: true,
        emailVerified: true,
      },
    });
    await submitGst(rec);
    emails.length = 0;

    const done = await decide(rec.uid, true);
    assert.equal(done.status, 200);
    assert.deepEqual(done.json, { ok: true });

    const row = await companyRow(rec);
    assert.equal(row.verificationStatus, "verified");
    assert.equal(row.verificationMethod, "gst");
    assert.ok(row.verifiedAt);

    for (const id of [rec.uid, member.id]) {
      const notes = await prisma.notification.findMany({ where: { userId: id, type: "verified" } });
      assert.equal(notes.length, 1, `notification for ${id}`);
      assert.equal(notes[0].title, "Your company is verified ✓");
      assert.equal(notes[0].link, "/company/verify");
    }
    await h.idle();
    assert.ok(emails.some((e) => e.to === rec.email && e.subject === "Your company is verified ✓"));
    assert.ok(emails.some((e) => e.to === member.email));

    assert.equal((await decide(rec.uid, true)).status, 404, "already decided");
    assert.equal((await decide(rec.uid, true)).json.error, "No pending request for this company");
    const again = await submitGst(rec);
    assert.equal(again.status, 409);
    assert.equal(again.json.error, "Your company is already verified");
    const candidateView = await api("GET", `/company/${row.id}`, { token: admin.token });
    assert.equal(candidateView.json.company.verified, true);
    assert.equal("gstin" in candidateView.json.company, false, "gstin is the owner's view only");
  });

  it("rejection is shown as rejected, notifies, and can be retried", async () => {
    const rec = await workRecruiter();
    await submitGst(rec);
    assert.equal((await decide(rec.uid, false)).status, 200);

    const status = await api("GET", "/company/verification", { token: rec.token });
    assert.equal(status.json.verification.status, "rejected");
    const own = (await api("GET", "/company/me", { token: rec.token })).json.company;
    assert.equal(own.verificationStatus, "rejected");
    assert.equal(own.verified, false);

    const notes = await prisma.notification.findMany({ where: { userId: rec.uid, type: "verified" } });
    assert.equal(notes.length, 1);
    assert.equal(notes[0].title, "Verification was not approved");

    // Saving the profile again does not clear a rejection...
    const resave = await api("PUT", "/company/me", { token: rec.token, body: { name: rec.company.name, website: "", about: "More" } });
    assert.equal(resave.json.company.verificationStatus, "rejected");
    // ...but a new request goes back to pending.
    assert.equal((await submitGst(rec)).json.verification.status, "pending");
    assert.equal((await decide(rec.uid, "yes")).status, 200, "anything but true rejects");
    assert.equal((await companyRow(rec)).verificationStatus, "rejected");
  });

  it("keeps the older manual verification request working", async () => {
    const rec = await signup("recruiter", "Manual Rec", { domain: "gmail.com" });
    await api("PUT", "/company/me", { token: rec.token, body: { name: "Manual Co", website: "https://manual.example.org" } });
    const asked = await api("POST", "/company/me/verification-request", { token: rec.token, body: { note: "GST certificate available" } });
    assert.equal(asked.status, 200);
    assert.equal(asked.json.company.verificationStatus, "pending");
    const list = await api("GET", "/admin/verifications", { token: admin.token });
    assert.ok(list.json.companies.some((c) => c.id === rec.uid));
    assert.equal((await decide(rec.uid, true)).status, 200);
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.verified, true);
  });
});

describe("resetting verification", () => {
  async function verifiedCompany() {
    const rec = await workRecruiter({ website: "https://reset-site.example.org" });
    await prisma.company.update({
      where: { ownerId: rec.uid },
      data: { verificationStatus: "verified", verificationMethod: "gst", verifiedAt: new Date(), gstin: GSTIN },
    });
    return rec;
  }
  const put = (rec, body) => api("PUT", "/company/me", { token: rec.token, body });

  it("keeps the badge when the name and website are sent unchanged", async () => {
    const rec = await verifiedCompany();
    const res = await put(rec, { name: rec.company.name, website: "https://reset-site.example.org", about: "Now with an about" });
    assert.equal(res.json.company.verified, true);
    assert.equal(res.json.company.verificationMethod, "gst");
    // Fields left out of a partial update do not count as a change.
    assert.equal((await put(rec, { about: "Again" })).json.company.verified, true);
  });

  it("resets on a rename and on a new website", async () => {
    const renamed = await verifiedCompany();
    const a = await put(renamed, { name: `${renamed.company.name} Renamed`, website: "https://reset-site.example.org" });
    assert.equal(a.json.company.verified, false);
    assert.equal(a.json.company.verificationStatus, "unverified");
    assert.equal(a.json.company.verificationMethod, "");
    const status = await api("GET", "/company/verification", { token: renamed.token });
    assert.equal(status.json.verification.status, "none");
    assert.equal(status.json.verification.verifiedAt, null);

    const moved = await verifiedCompany();
    const b = await put(moved, { name: moved.company.name, website: "https://another-site.example.org" });
    assert.equal(b.json.company.verificationStatus, "unverified");

    const pending = await verifiedCompany();
    await prisma.company.update({ where: { ownerId: pending.uid }, data: { verificationStatus: "pending" } });
    const c = await put(pending, { name: "Brand New Name" });
    assert.equal(c.json.company.verificationStatus, "unverified");
  });

  it("a reset can be immediately re-verified by the domain check", async () => {
    const rec = await verifiedCompany();
    const res = await put(rec, { name: rec.company.name, website: `https://www.${rec.domain}` });
    assert.equal(res.json.company.verified, true);
    assert.equal(res.json.company.verificationMethod, "email");
  });

  it("invalidates an emailed code when the website changes", async () => {
    const rec = await workRecruiter();
    await setWebsite(rec, `https://${rec.domain}`);
    await send(rec);
    const code = emailedCode(rec.email);
    await put(rec, { name: rec.company.name, website: "https://elsewhere.example.org" });
    const res = await confirm(rec, code);
    assert.equal(res.status, 400);
    assert.equal(res.json.error, "Code expired, please request a new one");
  });

  it("only the owner may rename or re-point the company", async () => {
    const owner = await verifiedCompany();
    const member = await prisma.user.create({
      data: {
        name: "Team Mate",
        email: h.emailFor("recruiter"),
        passwordHash: "x",
        role: "recruiter",
        company: owner.company.name,
        companyOwnerId: owner.uid,
        profileComplete: true,
        emailVerified: true,
      },
    });
    const token = jwt.sign({ sub: member.id, role: "recruiter", v: 0 }, process.env.JWT_SECRET, { expiresIn: "1d" });
    const asMember = (body) => api("PUT", "/company/me", { token, body });

    const mine = await api("GET", "/company/me", { token });
    assert.equal(mine.json.company.id, owner.company.id, "a teammate sees the owner's company");

    const rename = await asMember({ name: "Hijacked" });
    assert.equal(rename.status, 403);
    assert.equal(rename.json.error, "Only the account owner can change the company name or website");
    assert.equal((await asMember({ website: "https://hijack.example.org" })).status, 403);

    // The full form with unchanged name and website is fine, and edits the shared profile.
    const edit = await asMember({ name: owner.company.name, website: "https://reset-site.example.org", about: "Team edit" });
    assert.equal(edit.status, 200, JSON.stringify(edit.json));
    assert.equal(edit.json.company.about, "Team edit");
    assert.equal(edit.json.company.verified, true, "a teammate's save never touches verification");
    assert.equal((await companyRow(owner)).name, owner.company.name);

    // A teammate can read the status and ask for GST review of the shared company.
    const status = await api("GET", "/company/verification", { token });
    assert.equal(status.json.verification.status, "verified");
    assert.equal(status.json.email, member.email);

    // PATCH /users/me cannot be used to rename the company either.
    await api("PATCH", "/users/me", { token, body: { company: "Sneaky Rename" } });
    assert.equal((await prisma.user.findUnique({ where: { id: member.id } })).company, owner.company.name);
  });
});
