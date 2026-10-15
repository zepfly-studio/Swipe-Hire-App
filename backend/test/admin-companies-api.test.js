// Admin company management: list every company and verify one by hand,
// with no GSTIN involved; the default admin; admin-only access.

const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const h = require("./helpers");
const { isAdminUser, adminEmails, DEFAULT_ADMIN_EMAILS } = require("../src/lib/admin");

const { api, signup } = h;

before(() => h.start());
after(() => h.stop());

describe("who is an admin", () => {
  const saved = process.env.ADMIN_EMAILS;
  after(() => {
    if (saved === undefined) delete process.env.ADMIN_EMAILS;
    else process.env.ADMIN_EMAILS = saved;
  });

  it("the product owner is an admin by default; ADMIN_EMAILS replaces the default", () => {
    delete process.env.ADMIN_EMAILS;
    assert.deepEqual(adminEmails(), DEFAULT_ADMIN_EMAILS);
    assert.equal(isAdminUser({ email: "Content.Zepfly@gmail.com", emailVerified: true }), true);
    assert.equal(isAdminUser({ email: "someone@else.com", emailVerified: true }), false);
    assert.equal(isAdminUser({ email: "content.zepfly@gmail.com", emailVerified: false }), false);

    process.env.ADMIN_EMAILS = "boss@example.com , Second@Example.com";
    assert.equal(isAdminUser({ email: "second@example.com", emailVerified: true }), true);
    assert.equal(isAdminUser({ email: "content.zepfly@gmail.com", emailVerified: true }), false, "the env list replaces the default");

    process.env.ADMIN_EMAILS = "   ";
    assert.deepEqual(adminEmails(), DEFAULT_ADMIN_EMAILS, "a blank value falls back to the default");
  });
});

describe("admin manages companies without a GSTIN", () => {
  let admin;
  const saved = process.env.ADMIN_EMAILS;

  before(async () => {
    admin = await signup("recruiter", "Company Admin");
    process.env.ADMIN_EMAILS = admin.email;
  });
  after(() => {
    if (saved === undefined) delete process.env.ADMIN_EMAILS;
    else process.env.ADMIN_EMAILS = saved;
  });

  async function companyOwner(name) {
    const rec = await signup("recruiter", `${name} Owner`);
    const saved = await api("PUT", "/company/me", { token: rec.token, body: { name, location: "Pune", website: `https://${name.replace(/\W/g, "").toLowerCase()}.example` } });
    assert.equal(saved.status, 200, JSON.stringify(saved.json));
    return rec;
  }
  const list = (query = "") => api("GET", `/admin/companies${query}`, { token: admin.token });
  const setVerified = (companyId, verified) =>
    api("POST", `/admin/companies/${companyId}/verify`, { token: admin.token, body: { verified } });

  it("is admin only", async () => {
    const rec = await companyOwner(`NoAccess ${Date.now() % 100000}`);
    const cand = await signup("candidate", "Curious Candidate");
    for (const who of [rec, cand]) {
      assert.equal((await api("GET", "/admin/companies", { token: who.token })).status, 403);
      const verify = await api("POST", `/admin/companies/${rec.uid}/verify`, { token: who.token, body: { verified: true } });
      assert.equal(verify.status, 403);
    }
    assert.equal((await api("GET", "/admin/companies")).status, 401);
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.verified, false);
  });

  it("lists companies with filters and search, GSTIN or not", async () => {
    const tag = `Zlist${Date.now() % 100000}`;
    const a = await companyOwner(`${tag} Alpha`);
    const b = await companyOwner(`${tag} Beta`);
    await setVerified(b.uid, true);

    const all = await list(`?q=${tag}`);
    assert.equal(all.status, 200, JSON.stringify(all.json));
    const names = all.json.companies.map((c) => c.companyName).sort();
    assert.deepEqual(names, [`${tag} Alpha`, `${tag} Beta`]);
    const alpha = all.json.companies.find((c) => c.id === a.uid);
    assert.equal(alpha.verified, false);
    assert.equal(alpha.gstin, "");
    assert.equal(alpha.contact.email, a.email);
    assert.equal(alpha.location, "Pune");

    const verified = await list(`?q=${tag}&status=verified`);
    assert.deepEqual(verified.json.companies.map((c) => c.id), [b.uid]);
    assert.equal(verified.json.companies[0].method, "admin");
    const unverified = await list(`?q=${tag}&status=unverified`);
    assert.deepEqual(unverified.json.companies.map((c) => c.id), [a.uid]);
    const byEmail = await list(`?q=${encodeURIComponent(a.email)}`);
    assert.deepEqual(byEmail.json.companies.map((c) => c.id), [a.uid]);
  });

  it("verifies and un-verifies by hand, tells the team once, and needs no GSTIN", async () => {
    const rec = await companyOwner(`Hand ${Date.now() % 100000}`);

    const before = await api("GET", "/company/verification", { token: rec.token });
    assert.equal(before.json.gstin, "", "no GSTIN was ever submitted");

    const on = await setVerified(rec.uid, true);
    assert.equal(on.status, 200, JSON.stringify(on.json));
    assert.deepEqual(on.json, { ok: true, status: "verified", verified: true });
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.verified, true);
    const after = await api("GET", "/company/verification", { token: rec.token });
    assert.equal(after.json.verification.status, "verified");
    assert.equal(after.json.verification.method, "admin");

    await h.idle();
    const notifications = await api("GET", "/notifications?limit=50", { token: rec.token });
    const verifiedNotes = notifications.json.notifications.filter((n) => n.type === "verified");
    assert.equal(verifiedNotes.length, 1);
    assert.equal(verifiedNotes[0].link, "/company/verify");

    await setVerified(rec.uid, true);
    await h.idle();
    const again = await api("GET", "/notifications?limit=50", { token: rec.token });
    assert.equal(again.json.notifications.filter((n) => n.type === "verified").length, 1, "no second notification");

    const off = await setVerified(rec.uid, false);
    assert.deepEqual(off.json, { ok: true, status: "unverified", verified: false });
    assert.equal((await api("GET", "/company/me", { token: rec.token })).json.company.verified, false);
  });

  it("rejects a bad body and an unknown company", async () => {
    const rec = await companyOwner(`Bad ${Date.now() % 100000}`);
    const bad = await api("POST", `/admin/companies/${rec.uid}/verify`, { token: admin.token, body: { verified: "yes" } });
    assert.equal(bad.status, 400);
    assert.equal(bad.json.field, "verified");
    const missing = await setVerified("00000000-0000-4000-8000-000000000000", true);
    assert.equal(missing.status, 404);
  });
});
