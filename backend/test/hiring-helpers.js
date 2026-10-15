// Helpers for tests that drive the company side (jobs, swipes, credits).

const assert = require("node:assert/strict");
const h = require("./helpers");

const { api, prisma } = h;

/** Makes sure the recruiter has a Company row and sets its swipe balance. */
async function giveSwipes(recruiter, count) {
  await api("GET", "/company/me", { token: recruiter.token });
  let company = await prisma.company.findUnique({ where: { ownerId: recruiter.uid } });
  if (!company) {
    const me = await api("GET", "/users/me", { token: recruiter.token });
    const name = me.json.company && me.json.company.length >= 2 ? me.json.company : `${recruiter.name} Co`;
    const res = await api("PUT", "/company/me", { token: recruiter.token, body: { name } });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    company = await prisma.company.findUnique({ where: { ownerId: recruiter.uid } });
  }
  await prisma.company.update({ where: { ownerId: recruiter.uid }, data: { swipesLeft: count } });
}

/** A recruiter with a posting and plenty of swipes. Returns { rec, job }. */
async function recruiterWithJob(name, { swipes = 1000, job = {}, signupOptions } = {}) {
  const rec = await h.signup("recruiter", name, signupOptions);
  const posted = await h.postJob(rec, { salaryMaxLpa: 1000, salaryMinLpa: 0, ...job });
  await giveSwipes(rec, swipes);
  return { rec, job: posted };
}

async function swipe(recruiter, candidateId, action, jobId) {
  return api("POST", "/company/swipe", {
    token: recruiter.token,
    body: { candidateId, action, ...(jobId ? { jobId } : {}) },
  });
}

async function swipesLeft(recruiter) {
  const res = await api("GET", "/company/me", { token: recruiter.token });
  return res.json.company.swipesLeft;
}

/** Every deck card for a query, following the cursor. */
async function deckAll(recruiter, query = "") {
  const out = [];
  let cursor = "";
  for (let i = 0; i < 40; i++) {
    const page = await api("GET", `/candidates?limit=30${query}${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ""}`, {
      token: recruiter.token,
    });
    assert.equal(page.status, 200, JSON.stringify(page.json));
    out.push(...page.json.candidates);
    if (!page.json.hasMore) break;
    cursor = page.json.nextCursor;
  }
  return out;
}

module.exports = { giveSwipes, recruiterWithJob, swipe, swipesLeft, deckAll };
