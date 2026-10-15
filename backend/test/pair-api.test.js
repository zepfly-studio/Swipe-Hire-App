// Phase 3 pair features: chat, interviews, tasks and their reminders.
// Accounts, jobs and swipes are created straight through Prisma
// (test/pair-helpers.js); everything else goes through the real HTTP API.

const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const h = require("./pair-helpers");
const { api, prisma, MINUTE, HOUR, DAY, inFuture } = h;
const {
  runHiringTaskReminders,
  runPairInterviewReminders,
} = require("../src/jobs/taskReminders");

before(() => h.start());
after(() => h.stop());

const notificationsFor = (userId, type) =>
  prisma.notification.findMany({ where: { userId, ...(type ? { type } : {}) }, orderBy: { createdAt: "asc" } });

const stageOf = async (swipeId) => (await prisma.candidateSwipe.findUnique({ where: { id: swipeId } })).stage;

const send = (token, otherId, text) => api("POST", `/chats/${otherId}`, { token, body: { text } });

// ------------------------------------------------------------------ chat --

describe("chat", () => {
  it("lets a company message a candidate it right-swiped, moves the stage once, and notifies once while unread", async () => {
    const { recruiter, candidate, swipe } = await h.shortlistedPair();
    assert.equal(await stageOf(swipe.id), "shortlisted");

    const first = await send(recruiter.token, candidate.id, "  Hello there  ");
    assert.equal(first.status, 201, JSON.stringify(first.json));
    assert.equal(first.json.message.text, "Hello there");
    assert.equal(first.json.message.mine, true);
    assert.equal(first.json.message.read, false);
    assert.ok(first.json.message.id && first.json.message.at);
    assert.equal(await stageOf(swipe.id), "contacted");

    const second = await send(recruiter.token, candidate.id, "Are you free this week?");
    assert.equal(second.status, 201);
    await h.idle();

    const bell = await notificationsFor(candidate.id, "message");
    assert.equal(bell.length, 1, "only the first unread message fills the bell");
    assert.equal(bell[0].link, `/messages?with=${recruiter.id}`);
    assert.equal(bell[0].title, "New message from PairCorp");
    assert.equal(bell[0].body, "Hello there");

    const mails = h.emails.filter((m) => m.to === candidate.user.email && m.subject?.includes("PairCorp"));
    assert.equal(mails.length, 1, "one email, not one per message");
    // push still goes for every message
    assert.ok(h.pushes.length >= 2);
  });

  it("raises a fresh notification after the thread was read", async () => {
    const { recruiter, candidate } = await h.shortlistedPair();
    await send(recruiter.token, candidate.id, "one");
    await h.idle();
    const thread = await api("GET", `/chats/${recruiter.id}`, { token: candidate.token });
    assert.equal(thread.status, 200);
    // the bell entry for that conversation is handled by opening it
    assert.ok((await notificationsFor(candidate.id, "message")).every((n) => n.readAt));
    await send(recruiter.token, candidate.id, "two");
    await h.idle();
    assert.equal((await notificationsFor(candidate.id, "message")).length, 2);
  });

  it("refuses companies that have not right-swiped the candidate", async () => {
    const recruiter = await h.createRecruiter();
    const candidate = await h.createCandidate();
    const none = await send(recruiter.token, candidate.id, "hi");
    assert.equal(none.status, 403);

    const job = await h.createJob(recruiter);
    await h.createSwipe(recruiter, candidate, job, { action: "left" });
    const left = await send(recruiter.token, candidate.id, "hi");
    assert.equal(left.status, 403, "a left swipe is a pass");

    const stranger = await h.createRecruiter("Stranger");
    const { candidate: c2 } = await h.shortlistedPair();
    assert.equal((await send(stranger.token, c2.id, "hi")).status, 403, "someone else's shortlist");
  });

  it("lets a candidate reply only after the company contacted them", async () => {
    const { recruiter, candidate } = await h.shortlistedPair();

    const early = await send(candidate.token, recruiter.id, "Hi, I saw your shortlist");
    assert.equal(early.status, 403);
    assert.equal(early.json.error, "This company has not contacted you yet");
    const emptyThread = await api("GET", `/chats/${recruiter.id}`, { token: candidate.token });
    assert.equal(emptyThread.status, 403);

    await send(recruiter.token, candidate.id, "Hello!");
    const reply = await send(candidate.token, recruiter.id, "Hi, thanks for reaching out");
    assert.equal(reply.status, 201, JSON.stringify(reply.json));
    await h.idle();
    const bell = await notificationsFor(recruiter.id, "message");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].title, `New message from ${candidate.name}`);
    assert.equal(bell[0].link, `/messages?with=${candidate.id}`);
  });

  it("treats an interview or a task as contact too", async () => {
    const a = await h.shortlistedPair();
    await prisma.interview.create({
      data: { companyId: a.recruiter.id, candidateId: a.candidate.id, slots: [new Date(Date.now() + DAY)] },
    });
    assert.equal((await send(a.candidate.token, a.recruiter.id, "Thanks for the invite")).status, 201);

    const b = await h.shortlistedPair();
    await prisma.hiringTask.create({
      data: { companyId: b.recruiter.id, candidateId: b.candidate.id, title: "T", dueAt: new Date(Date.now() + DAY) },
    });
    assert.equal((await send(b.candidate.token, b.recruiter.id, "Got the task")).status, 201);
  });

  it("validates the text and the other party", async () => {
    const { recruiter, candidate } = await h.shortlistedPair();
    const empty = await send(recruiter.token, candidate.id, "   ");
    assert.equal(empty.status, 400);
    assert.equal(empty.json.error, "Message cannot be empty");
    const long = await send(recruiter.token, candidate.id, "x".repeat(2001));
    assert.equal(long.status, 400);
    assert.equal(long.json.error, "Message is too long (max 2000 characters)");
    assert.equal((await send(recruiter.token, candidate.id, "x".repeat(2000))).status, 201);

    assert.equal((await send(recruiter.token, "nobody", "hi")).status, 404);
    const other = await h.createRecruiter("Other Recruiter");
    assert.equal((await send(recruiter.token, other.id, "hi")).status, 404, "company to company is not a chat");
    assert.equal((await api("GET", "/chats")).status, 401);
  });

  it("returns the thread with `with`, marks read, and counts unread", async () => {
    const { recruiter, candidate, job } = await h.shortlistedPair({ jobTitle: "Mobile Engineer" });
    await prisma.company.update({ where: { ownerId: recruiter.id }, data: { verificationStatus: "verified", logoUrl: "https://x.test/logo.png" } });
    await prisma.candidateProfile.update({ where: { userId: candidate.id }, data: { photoUrl: "https://x.test/me.png" } });

    await send(recruiter.token, candidate.id, "m1");
    await send(recruiter.token, candidate.id, "m2");

    const count = await api("GET", "/chats/unread-count", { token: candidate.token });
    assert.equal(count.json.count, 2);
    assert.equal((await api("GET", "/chats/unread-count", { token: recruiter.token })).json.count, 0);

    const list = await api("GET", "/chats", { token: candidate.token });
    assert.equal(list.status, 200);
    const row = list.json.conversations.find((c) => c.id === recruiter.id);
    assert.ok(row);
    assert.equal(row.name, "PairCorp");
    assert.equal(row.subtitle, "Mobile Engineer");
    assert.equal(row.verified, true);
    assert.equal(row.avatarUrl, "https://x.test/logo.png");
    assert.equal(row.stage, "contacted");
    assert.equal(row.unread, 2);
    assert.deepEqual({ text: row.lastMessage.text, mine: row.lastMessage.mine }, { text: "m2", mine: false });
    assert.ok(row.updatedAt);

    const thread = await api("GET", `/chats/${recruiter.id}`, { token: candidate.token });
    assert.equal(thread.status, 200);
    assert.deepEqual(thread.json.with, {
      id: recruiter.id,
      name: "PairCorp",
      subtitle: "Mobile Engineer",
      verified: true,
      avatarUrl: "https://x.test/logo.png",
    });
    assert.deepEqual(thread.json.messages.map((m) => [m.text, m.mine]), [["m1", false], ["m2", false]]);
    assert.equal((await api("GET", "/chats/unread-count", { token: candidate.token })).json.count, 0);

    // the company now sees its own messages as read
    const company = await api("GET", `/chats/${candidate.id}`, { token: recruiter.token });
    assert.deepEqual(company.json.with, {
      id: candidate.id,
      name: candidate.name,
      subtitle: "Flutter Developer",
      avatarUrl: "https://x.test/me.png",
    });
    assert.deepEqual(company.json.messages.map((m) => [m.mine, m.read]), [[true, true], [true, true]]);

    // subtitle falls back to the industry when there is no swipe job to name
    await prisma.candidateSwipe.update({ where: { recruiterId_candidateId_jobPostingId: { recruiterId: recruiter.id, candidateId: candidate.id, jobPostingId: job.id } }, data: { action: "left" } });
    const fallback = await api("GET", `/chats/${recruiter.id}`, { token: candidate.token });
    assert.equal(fallback.json.with.subtitle, "Software");
  });

  it("only lists conversations with messages, newest first, for the company", async () => {
    const recruiter = await h.createRecruiter();
    const job = await h.createJob(recruiter);
    const a = await h.createCandidate("Aaa Candidate");
    const b = await h.createCandidate("Bbb Candidate");
    const c = await h.createCandidate("Ccc Candidate");
    for (const cand of [a, b, c]) await h.createSwipe(recruiter, cand, job);

    await send(recruiter.token, a.id, "to a");
    await send(recruiter.token, b.id, "to b");
    await send(b.token, recruiter.id, "from b");

    const list = await api("GET", "/chats", { token: recruiter.token });
    assert.deepEqual(list.json.conversations.map((x) => x.id), [b.id, a.id]);
    assert.equal(list.json.conversations[0].unread, 1);
    assert.equal(list.json.conversations[0].lastMessage.mine, false);
    assert.equal(list.json.conversations[1].unread, 0);
    assert.equal(list.json.conversations[1].lastMessage.mine, true);
    assert.equal(list.json.conversations[0].subtitle, "Flutter Developer");
  });

  it("lists contacts per side", async () => {
    const recruiter = await h.createRecruiter();
    const job = await h.createJob(recruiter);
    const chatted = await h.createCandidate("Chatted Candidate");
    const silent = await h.createCandidate("Silent Candidate");
    const passed = await h.createCandidate("Passed Candidate");
    await h.createSwipe(recruiter, chatted, job);
    await h.createSwipe(recruiter, silent, job);
    await h.createSwipe(recruiter, passed, job, { action: "left" });
    await send(recruiter.token, chatted.id, "hi");

    const company = await api("GET", "/chats/contacts", { token: recruiter.token });
    assert.equal(company.status, 200);
    const byId = Object.fromEntries(company.json.contacts.map((c) => [c.id, c]));
    assert.deepEqual(Object.keys(byId).sort(), [chatted.id, silent.id].sort());
    assert.equal(byId[chatted.id].hasChat, true);
    assert.equal(byId[silent.id].hasChat, false);
    assert.equal(byId[chatted.id].stage, "contacted");
    assert.equal(byId[silent.id].stage, "shortlisted");
    assert.equal(byId[silent.id].subtitle, "Flutter Developer");

    const asCandidate = await api("GET", "/chats/contacts", { token: chatted.token });
    assert.deepEqual(asCandidate.json.contacts.map((c) => c.id), [recruiter.id]);
    assert.equal(asCandidate.json.contacts[0].hasChat, true);
    assert.equal(asCandidate.json.contacts[0].verified, false);
    // shortlisted but never contacted: the candidate cannot see the company
    const hidden = await api("GET", "/chats/contacts", { token: silent.token });
    assert.deepEqual(hidden.json.contacts, []);
  });

  it("sends bulk messages to shortlisted candidates and skips the rest", async () => {
    const recruiter = await h.createRecruiter();
    const job = await h.createJob(recruiter);
    const a = await h.createCandidate("Bulk A");
    const b = await h.createCandidate("Bulk B");
    const stranger = await h.createCandidate("Bulk Stranger");
    const swipeA = await h.createSwipe(recruiter, a, job);
    await h.createSwipe(recruiter, b, job);

    const res = await api("POST", "/chats/bulk", {
      token: recruiter.token,
      body: { text: "Hi all", candidateIds: [a.id, b.id, stranger.id, a.id, "ghost"] },
    });
    assert.equal(res.status, 201, JSON.stringify(res.json));
    assert.equal(res.json.sent, 2);
    assert.deepEqual([...res.json.skipped].sort(), [stranger.id, "ghost"].sort());
    assert.equal(await stageOf(swipeA.id), "contacted");
    assert.equal((await api("GET", `/chats/${recruiter.id}`, { token: a.token })).json.messages[0].text, "Hi all");
    assert.equal((await api("GET", "/chats/unread-count", { token: b.token })).json.count, 1);
    await h.idle();
    assert.equal((await notificationsFor(a.id, "message")).length, 1);

    const forbidden = await api("POST", "/chats/bulk", { token: a.token, body: { text: "x", candidateIds: [recruiter.id] } });
    assert.equal(forbidden.status, 403);
    assert.equal(forbidden.json.error, "Only companies can message several candidates at once");

    const noText = await api("POST", "/chats/bulk", { token: recruiter.token, body: { text: " ", candidateIds: [a.id] } });
    assert.equal(noText.status, 400);
    const none = await api("POST", "/chats/bulk", { token: recruiter.token, body: { text: "x", candidateIds: [] } });
    assert.equal(none.status, 400);
    const tooMany = await api("POST", "/chats/bulk", {
      token: recruiter.token,
      body: { text: "x", candidateIds: Array.from({ length: 51 }, (_, i) => `id-${i}`) },
    });
    assert.equal(tooMany.status, 400);
  });

  it("rate-limits sends (30/min) and bulk sends (20/hour) per user", async () => {
    const { recruiter, candidate } = await h.shortlistedPair();
    for (let i = 0; i < 30; i++) {
      const ok = await send(recruiter.token, candidate.id, `msg ${i}`);
      assert.equal(ok.status, 201, `message ${i}: ${JSON.stringify(ok.json)}`);
    }
    const limited = await send(recruiter.token, candidate.id, "one too many");
    assert.equal(limited.status, 429);
    assert.equal(limited.json.error, "You are sending messages too fast, please slow down");
    // the candidate has their own bucket
    assert.equal((await send(candidate.token, recruiter.id, "still fine")).status, 201);

    const bulker = await h.createRecruiter("Bulker");
    for (let i = 0; i < 20; i++) {
      const ok = await api("POST", "/chats/bulk", { token: bulker.token, body: { text: "hi", candidateIds: [candidate.id] } });
      assert.equal(ok.status, 201);
    }
    const bulkLimited = await api("POST", "/chats/bulk", { token: bulker.token, body: { text: "hi", candidateIds: [candidate.id] } });
    assert.equal(bulkLimited.status, 429);
    assert.equal(bulkLimited.json.error, "You have sent a lot of group messages, please try again in an hour");
  });
});

// ------------------------------------------------------------ interviews --

describe("interviews", () => {
  const slot = (ms) => inFuture(ms);
  const create = (pair, extra = {}) =>
    api("POST", "/interviews", {
      token: pair.recruiter.token,
      body: { candidateId: pair.candidate.id, slots: [slot(DAY)], ...extra },
    });

  it("validates the invite", async () => {
    const pair = await h.shortlistedPair();
    const bad = async (body, message, status = 400) => {
      const res = await api("POST", "/interviews", { token: pair.recruiter.token, body: { candidateId: pair.candidate.id, slots: [slot(DAY)], ...body } });
      assert.equal(res.status, status, JSON.stringify(res.json));
      if (message) assert.equal(res.json.error, message);
    };
    await bad({ slots: [] }, "Please offer between 1 and 3 times");
    await bad({ slots: [slot(DAY), slot(2 * DAY), slot(3 * DAY), slot(4 * DAY)] }, "Please offer between 1 and 3 times");
    await bad({ slots: [slot(10 * MINUTE)] }, "Every proposed time must be at least 15 minutes from now");
    await bad({ slots: ["not a date"] }, "One of the proposed times is not a valid date");
    await bad({ durationMins: 20 }, "Duration must be 15, 30, 45 or 60 minutes");
    await bad({ mode: "carrier-pigeon" }, "Choose video, phone or in-person");
    await bad({ mode: "in-person" }, "Please add the location for an in-person interview");
    await bad({ mode: "in-person", location: "x".repeat(201) }, "Location is too long (max 200 characters)");
    await bad({ meetingLink: "http://insecure.test/x" }, "Meeting link must start with https://");
    await bad({ meetingLink: `https://x.test/${"a".repeat(300)}` }, "Meeting link is too long (max 300 characters)");
    await bad({ note: "n".repeat(501) }, "Note is too long (max 500 characters)");

    const other = await h.createCandidate("Not Shortlisted");
    const res = await api("POST", "/interviews", { token: pair.recruiter.token, body: { candidateId: other.id, slots: [slot(DAY)] } });
    assert.equal(res.status, 403);
    const otherJob = await h.createJob(pair.recruiter, "Other job");
    const wrongJob = await api("POST", "/interviews", {
      token: pair.recruiter.token,
      body: { candidateId: pair.candidate.id, jobId: otherJob.id, slots: [slot(DAY)] },
    });
    assert.equal(wrongJob.status, 403);
    assert.equal(wrongJob.json.error, "This candidate is not shortlisted for that job");

    const asCandidate = await api("POST", "/interviews", { token: pair.candidate.token, body: { candidateId: pair.recruiter.id, slots: [slot(DAY)] } });
    assert.equal(asCandidate.status, 403);
  });

  it("creates an invite with a Jitsi link, moves the stage, notifies and hides the link until confirmed", async () => {
    const pair = await h.shortlistedPair({ jobTitle: "Backend Engineer" });
    const { recruiter, candidate, swipe } = pair;
    const slots = [slot(2 * DAY), slot(DAY), slot(3 * DAY)];

    const created = await api("POST", "/interviews", {
      token: recruiter.token,
      body: { candidateId: candidate.id, jobId: pair.job.id, slots, durationMins: 45, note: "Bring your laptop" },
    });
    assert.equal(created.status, 201, JSON.stringify(created.json));
    assert.ok(created.json.id);
    assert.equal(await stageOf(swipe.id), "interview");

    const stored = await prisma.interview.findUnique({ where: { id: created.json.id } });
    assert.match(stored.meetingLink, /^https:\/\/meet\.jit\.si\/GlideRecruit-[0-9a-f]{12}$/);
    assert.equal(stored.durationMins, 45);
    assert.equal(stored.mode, "video");
    assert.equal(stored.status, "proposed");

    await h.idle();
    const bell = await notificationsFor(candidate.id, "interview");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].link, "/interviews");
    const mail = h.emails.find((m) => m.to === candidate.user.email && m.subject === "Interview invitation from PairCorp");
    assert.ok(mail, "invite email sent");
    assert.match(mail.body, /IST/);
    assert.match(mail.body, /Backend Engineer/);

    const asCandidate = await api("GET", "/interviews", { token: candidate.token });
    assert.equal(asCandidate.status, 200);
    const item = asCandidate.json.interviews.find((i) => i.id === created.json.id);
    assert.ok(item);
    assert.equal(item.meetingLink, "", "no link while proposed");
    assert.equal(item.status, "proposed");
    assert.equal(item.jobTitle, "Backend Engineer");
    assert.equal(item.chosenSlot, null);
    assert.equal(item.durationMins, 45);
    assert.deepEqual(item.slots, [...slots].map((s) => new Date(s).toISOString()).sort());
    assert.equal(item.with.id, recruiter.id);
    assert.equal(item.with.name, "PairCorp");
    assert.equal(item.with.verified, false);

    const asCompany = await api("GET", "/interviews", { token: recruiter.token });
    const mine = asCompany.json.interviews.find((i) => i.id === created.json.id);
    assert.equal(mine.with.id, candidate.id);
    assert.equal(mine.with.name, candidate.name);
    assert.equal(mine.meetingLink, "", "the company does not see it either until confirmed");

    const dup = await create(pair);
    assert.equal(dup.status, 409);
    assert.equal(dup.json.error, "An interview with this candidate is already scheduled");
  });

  it("does not pull a hired or rejected candidate back to the interview stage", async () => {
    const pair = await h.shortlistedPair({ stage: "hired" });
    assert.equal((await create(pair)).status, 201);
    assert.equal(await stageOf(pair.swipe.id), "hired");
  });

  it("keeps the phone / in-person fields and accepts an own https link", async () => {
    const pair = await h.shortlistedPair();
    const res = await create(pair, { mode: "in-person", location: "HQ, Pune", meetingLink: "https://example.com/room" });
    assert.equal(res.status, 201);
    const row = await prisma.interview.findUnique({ where: { id: res.json.id } });
    assert.equal(row.location, "HQ, Pune");
    assert.equal(row.meetingLink, "https://example.com/room");
    await api("POST", `/interviews/${res.json.id}/cancel`, { token: pair.recruiter.token });

    const phone = await create(pair, { mode: "phone" });
    assert.equal(phone.status, 201);
    assert.equal((await prisma.interview.findUnique({ where: { id: phone.json.id } })).meetingLink, "");
  });

  it("lets only the candidate accept an offered, future slot, then shows the link and mails an .ics", async () => {
    const pair = await h.shortlistedPair();
    const { recruiter, candidate } = pair;
    const slots = [slot(DAY), slot(2 * DAY)];
    const created = await create(pair, { slots, durationMins: 60 });
    const id = created.json.id;
    const offered = (await prisma.interview.findUnique({ where: { id } })).slots.map((s) => s.toISOString());

    const byCompany = await api("POST", `/interviews/${id}/accept`, { token: recruiter.token, body: { slot: offered[0] } });
    assert.equal(byCompany.status, 403);

    const stranger = await h.createCandidate("Stranger");
    const byStranger = await api("POST", `/interviews/${id}/accept`, { token: stranger.token, body: { slot: offered[0] } });
    assert.equal(byStranger.status, 404);

    const wrong = await api("POST", `/interviews/${id}/accept`, { token: candidate.token, body: { slot: slot(5 * DAY) } });
    assert.equal(wrong.status, 400);
    assert.equal(wrong.json.error, "Please choose one of the offered times");
    const missing = await api("POST", `/interviews/${id}/accept`, { token: candidate.token, body: {} });
    assert.equal(missing.status, 400);

    const ok = await api("POST", `/interviews/${id}/accept`, { token: candidate.token, body: { slot: offered[1] } });
    assert.equal(ok.status, 200, JSON.stringify(ok.json));
    assert.deepEqual(ok.json, { ok: true });

    const again = await api("POST", `/interviews/${id}/accept`, { token: candidate.token, body: { slot: offered[0] } });
    assert.equal(again.status, 409);
    assert.equal(again.json.error, "This interview is no longer open");

    for (const token of [candidate.token, recruiter.token]) {
      const list = await api("GET", "/interviews", { token });
      const item = list.json.interviews.find((i) => i.id === id);
      assert.equal(item.status, "confirmed");
      assert.equal(item.chosenSlot, offered[1]);
      assert.match(item.meetingLink, /^https:\/\/meet\.jit\.si\/GlideRecruit-/);
    }

    await h.idle();
    const mail = h.emails.find((m) => m.to === recruiter.user.email && m.subject === `Interview confirmed with ${candidate.name}`);
    assert.ok(mail, "company emailed");
    assert.equal(mail.attachments.length, 1);
    assert.equal(mail.attachments[0].filename, "interview.ics");
    const ics = mail.attachments[0].content.toString("utf8");
    assert.match(ics, /BEGIN:VEVENT/);
    const start = new Date(offered[1]);
    const stamp = (d) => d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
    assert.ok(ics.includes(`DTSTART:${stamp(start)}`));
    assert.ok(ics.includes(`DTEND:${stamp(new Date(start.getTime() + 60 * MINUTE))}`));
    const bell = await notificationsFor(recruiter.id, "interview");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].link, "/interviews");
  });

  it("rejects accepting a slot that has already passed", async () => {
    const pair = await h.shortlistedPair();
    const past = new Date(Date.now() - HOUR);
    const row = await prisma.interview.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, slots: [past, new Date(Date.now() + DAY)] },
    });
    const res = await api("POST", `/interviews/${row.id}/accept`, { token: pair.candidate.token, body: { slot: past.toISOString() } });
    assert.equal(res.status, 400);
    assert.match(res.json.error, /already passed/);
    assert.equal((await prisma.interview.findUnique({ where: { id: row.id } })).status, "proposed");
  });

  it("cancels from either side, idempotently, notifies the other side and frees the pair", async () => {
    const pair = await h.shortlistedPair();
    const { recruiter, candidate } = pair;
    const created = await create(pair);
    const id = created.json.id;

    const stranger = await h.createRecruiter("Other Co");
    assert.equal((await api("POST", `/interviews/${id}/cancel`, { token: stranger.token })).status, 404);
    const long = await api("POST", `/interviews/${id}/cancel`, { token: candidate.token, body: { reason: "r".repeat(301) } });
    assert.equal(long.status, 400);

    const res = await api("POST", `/interviews/${id}/cancel`, { token: candidate.token, body: { reason: "Clash with exams" } });
    assert.deepEqual(res.json, { ok: true });
    const row = await prisma.interview.findUnique({ where: { id } });
    assert.equal(row.status, "cancelled");
    assert.equal(row.cancelledById, candidate.id);
    assert.equal(row.cancelReason, "Clash with exams");

    await h.idle();
    const bell = await notificationsFor(recruiter.id, "interview");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].body, "Clash with exams");

    const again = await api("POST", `/interviews/${id}/cancel`, { token: candidate.token });
    assert.deepEqual(again.json, { ok: true });
    await h.idle();
    assert.equal((await notificationsFor(recruiter.id, "interview")).length, 1, "no second notification");

    const list = await api("GET", "/interviews", { token: candidate.token });
    assert.equal(list.json.interviews.find((i) => i.id === id).status, "cancelled");
    assert.equal(list.json.interviews.find((i) => i.id === id).meetingLink, "");

    const accept = await api("POST", `/interviews/${id}/accept`, { token: candidate.token, body: { slot: row.slots[0].toISOString() } });
    assert.equal(accept.status, 409);

    // a fresh invite is allowed once the old one is cancelled; the company can cancel it with the default text
    const fresh = await create(pair);
    assert.equal(fresh.status, 201);
    await api("POST", `/interviews/${fresh.json.id}/cancel`, { token: recruiter.token });
    await h.idle();
    const cancelNote = (await notificationsFor(candidate.id, "interview")).at(-1);
    assert.equal(cancelNote.body, "You can agree on a new time in chat.");
  });

  it("only blocks a duplicate while a confirmed interview is still upcoming", async () => {
    const pair = await h.shortlistedPair();
    await prisma.interview.create({
      data: {
        companyId: pair.recruiter.id,
        candidateId: pair.candidate.id,
        slots: [new Date(Date.now() - DAY)],
        chosenSlot: new Date(Date.now() - DAY),
        status: "confirmed",
      },
    });
    assert.equal((await create(pair)).status, 201, "a past confirmed interview does not block");
  });
});

// ----------------------------------------------------------------- tasks --

describe("tasks", () => {
  const due = (ms = 2 * DAY) => inFuture(ms);
  const base = (pair, extra = {}) => ({
    candidateId: pair.candidate.id,
    title: "Build a todo app",
    description: "Flutter, with persistence",
    dueAt: due(),
    ...extra,
  });
  const create = (pair, extra = {}) => api("POST", "/tasks", { token: pair.recruiter.token, body: base(pair, extra) });

  it("validates the task with the website's messages", async () => {
    const pair = await h.shortlistedPair();
    const bad = async (extra, message) => {
      const res = await create(pair, extra);
      assert.equal(res.status, 400, JSON.stringify(res.json));
      assert.equal(res.json.error, message);
    };
    await bad({ title: "  " }, "Please give the task a title");
    await bad({ title: "t".repeat(121) }, "Title is too long (max 120 characters)");
    await bad({ description: "" }, "Please describe what the candidate should build");
    await bad({ description: "d".repeat(5001) }, "Description is too long (max 5000 characters)");
    await bad({ dueAt: undefined }, "Please choose a deadline");
    await bad({ dueAt: "garbage" }, "Please choose a deadline");
    await bad({ dueAt: due(30 * MINUTE) }, "The deadline must be at least 1 hour from now");
    await bad({ dueAt: due(31 * DAY) }, "The deadline can be at most 30 days away");
    await bad({ briefUrl: "javascript:alert(1)" }, "Please enter a valid reference link");

    const stranger = await h.createCandidate("Not Shortlisted");
    assert.equal((await create(pair, { candidateId: stranger.id })).status, 403);
    const otherJob = await h.createJob(pair.recruiter, "Other");
    const wrongJob = await create(pair, { jobId: otherJob.id });
    assert.equal(wrongJob.status, 403);
    assert.equal(wrongJob.json.error, "This candidate is not shortlisted for that job");
    assert.equal((await api("POST", "/tasks", { token: pair.candidate.token, body: base(pair) })).status, 403);
  });

  it("creates a task, moves shortlisted/contacted to task, notifies and lists it", async () => {
    const pair = await h.shortlistedPair({ jobTitle: "Mobile Engineer" });
    const { recruiter, candidate, swipe } = pair;

    const res = await create(pair, { briefUrl: "docs.example.com/brief", dueAt: due(3 * DAY) });
    assert.equal(res.status, 201, JSON.stringify(res.json));
    assert.equal(await stageOf(swipe.id), "task");

    await h.idle();
    const bell = await notificationsFor(candidate.id, "task");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].link, "/tasks");
    assert.ok(h.emails.find((m) => m.to === candidate.user.email && m.subject === "New task from PairCorp"));

    const asCandidate = await api("GET", "/tasks", { token: candidate.token });
    assert.equal(asCandidate.status, 200);
    const item = asCandidate.json.tasks.find((t) => t.id === res.json.id);
    assert.equal(item.status, "assigned");
    assert.equal(item.title, "Build a todo app");
    assert.equal(item.jobTitle, "Mobile Engineer");
    assert.equal(item.briefUrl, "https://docs.example.com/brief");
    assert.equal(item.with.id, recruiter.id);
    assert.equal(item.with.name, "PairCorp");
    assert.equal(item.submission, undefined);
    assert.ok(item.dueAt && item.createdAt);

    const asCompany = await api("GET", `/tasks?candidateId=${candidate.id}`, { token: recruiter.token });
    assert.equal(asCompany.json.tasks.length, 1);
    assert.equal(asCompany.json.tasks[0].with.id, candidate.id);
    assert.equal((await api("GET", `/tasks?candidateId=nobody`, { token: recruiter.token })).json.tasks.length, 0);
  });

  it("does not move later stages back to task", async () => {
    const pair = await h.shortlistedPair({ stage: "interview" });
    assert.equal((await create(pair)).status, 201);
    assert.equal(await stageOf(pair.swipe.id), "interview");
  });

  it("validates and records a submission, then lets it be updated until the deadline", async () => {
    const pair = await h.shortlistedPair();
    const { recruiter, candidate } = pair;
    const id = (await create(pair)).json.id;
    const submit = (body, token = candidate.token) => api("POST", `/tasks/${id}/submit`, { token, body });

    const none = await submit({});
    assert.equal(none.status, 400);
    assert.equal(none.json.error, "Add your live link or GitHub repo link");
    assert.equal((await submit({ liveUrl: "ftp://files.example.com/x" })).json.error, "Please enter a valid live link");
    assert.equal((await submit({ liveUrl: "notalink" })).json.error, "Please enter a valid live link");
    assert.equal((await submit({ repoUrl: "https://gitlab.com/me/app" })).json.error, "The repo link must be a github.com link");
    assert.equal((await submit({ repoUrl: "https://notgithub.com/me/app" })).status, 400);
    assert.equal((await submit({ liveUrl: `https://x.test/${"a".repeat(300)}` })).status, 400);
    assert.equal((await submit({ liveUrl: "my-app.vercel.app", note: "n".repeat(1001) })).status, 400);
    assert.equal((await submit({ liveUrl: "my-app.vercel.app" }, recruiter.token)).status, 403);
    const stranger = await h.createCandidate("Stranger");
    assert.equal((await submit({ liveUrl: "my-app.vercel.app" }, stranger.token)).status, 404);

    const ok = await submit({ liveUrl: "my-app.vercel.app", repoUrl: "github.com/me/app", note: " login: demo " });
    assert.equal(ok.status, 200, JSON.stringify(ok.json));
    const row = await prisma.hiringTask.findUnique({ where: { id } });
    assert.equal(row.status, "submitted");
    assert.equal(row.liveUrl, "https://my-app.vercel.app");
    assert.equal(row.repoUrl, "https://github.com/me/app");
    assert.equal(row.submissionNote, "login: demo");
    assert.ok(row.submittedAt);

    // a gist-style subdomain of github.com is fine; repeat submissions overwrite
    const second = await submit({ repoUrl: "https://gist.github.com/me/abc" });
    assert.equal(second.status, 200);

    await h.idle();
    const bell = await notificationsFor(recruiter.id, "task");
    assert.equal(bell.length, 2);
    assert.match(bell[0].title, /submitted a task/);
    assert.match(bell[1].title, /updated their submission/);
    assert.equal(bell[0].link, "/tasks");

    const list = await api("GET", "/tasks", { token: recruiter.token });
    const item = list.json.tasks.find((t) => t.id === id);
    assert.equal(item.status, "submitted");
    assert.equal(item.submission.repoUrl, "https://gist.github.com/me/abc");
    assert.equal(item.submission.liveUrl, "", "an update replaces the earlier submission");
    assert.ok(item.submission.at);
  });

  it("computes overdue and blocks late submissions", async () => {
    const pair = await h.shortlistedPair();
    const id = (await create(pair)).json.id;
    await prisma.hiringTask.update({ where: { id }, data: { dueAt: new Date(Date.now() - HOUR) } });

    const list = await api("GET", "/tasks", { token: pair.candidate.token });
    assert.equal(list.json.tasks.find((t) => t.id === id).status, "overdue");
    assert.equal((await prisma.hiringTask.findUnique({ where: { id } })).status, "assigned", "not stored");

    const late = await api("POST", `/tasks/${id}/submit`, { token: pair.candidate.token, body: { liveUrl: "late.example.com" } });
    assert.equal(late.status, 409);
    assert.equal(late.json.error, "The deadline for this task has passed");

    // a company that extends the deadline brings it back to assigned
    const extend = await api("PATCH", `/tasks/${id}`, { token: pair.recruiter.token, body: { dueAt: due(DAY) } });
    assert.equal(extend.status, 200);
    const after = await api("GET", "/tasks", { token: pair.candidate.token });
    assert.equal(after.json.tasks.find((t) => t.id === id).status, "assigned");
  });

  it("changes the deadline within the window and tells the candidate", async () => {
    const pair = await h.shortlistedPair();
    const id = (await create(pair)).json.id;
    const patch = (dueAt, token = pair.recruiter.token) => api("PATCH", `/tasks/${id}`, { token, body: { dueAt } });

    assert.equal((await patch(undefined)).json.error, "Please choose a deadline");
    assert.equal((await patch(due(10 * MINUTE))).json.error, "The deadline must be at least 1 hour from now");
    assert.equal((await patch(due(40 * DAY))).json.error, "The deadline can be at most 30 days away");
    assert.equal((await patch(due(DAY), pair.candidate.token)).status, 403);
    const other = await h.createRecruiter("Other");
    assert.equal((await patch(due(DAY), other.token)).status, 404);

    const target = due(5 * DAY);
    const ok = await patch(target);
    assert.deepEqual(ok.json, { ok: true });
    assert.equal((await prisma.hiringTask.findUnique({ where: { id } })).dueAt.toISOString(), new Date(target).toISOString());
    await h.idle();
    const bell = await notificationsFor(pair.candidate.id, "task");
    assert.equal(bell.length, 2, "assigned + deadline changed");
    assert.match(bell[1].title, /changed a task deadline/);
  });

  it("cancels idempotently, tells the candidate without an email and hides it from them", async () => {
    const pair = await h.shortlistedPair();
    const { recruiter, candidate } = pair;
    const id = (await create(pair)).json.id;
    await h.idle();
    const mailsBefore = h.emails.filter((m) => m.to === candidate.user.email).length;

    assert.equal((await api("POST", `/tasks/${id}/cancel`, { token: candidate.token })).status, 403);
    const res = await api("POST", `/tasks/${id}/cancel`, { token: recruiter.token });
    assert.deepEqual(res.json, { ok: true });
    const again = await api("POST", `/tasks/${id}/cancel`, { token: recruiter.token });
    assert.deepEqual(again.json, { ok: true });

    await h.idle();
    const bell = await notificationsFor(candidate.id, "task");
    assert.equal(bell.length, 2, "one cancel notification, not two");
    assert.match(bell[1].title, /cancelled a task/);
    assert.equal(h.emails.filter((m) => m.to === candidate.user.email).length, mailsBefore, "no email on cancel");

    const company = await api("GET", "/tasks", { token: recruiter.token });
    assert.equal(company.json.tasks.find((t) => t.id === id).status, "cancelled");
    const cand = await api("GET", "/tasks", { token: candidate.token });
    assert.equal(cand.json.tasks.find((t) => t.id === id), undefined);

    const submit = await api("POST", `/tasks/${id}/submit`, { token: candidate.token, body: { liveUrl: "x.example.com" } });
    assert.equal(submit.status, 409);
    const patch = await api("PATCH", `/tasks/${id}`, { token: recruiter.token, body: { dueAt: due(DAY) } });
    assert.equal(patch.status, 409);
  });
});

// ------------------------------------------------------------- reminders --

describe("reminders", () => {
  it("reminds the candidate once about a task due within 24h", async () => {
    const pair = await h.shortlistedPair();
    const old = new Date(Date.now() - HOUR);
    const soon = await prisma.hiringTask.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, title: "Soon", dueAt: new Date(Date.now() + 5 * HOUR), createdAt: old },
    });
    const later = await prisma.hiringTask.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, title: "Later", dueAt: new Date(Date.now() + 3 * DAY), createdAt: old },
    });
    const submitted = await prisma.hiringTask.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, title: "Done", status: "submitted", dueAt: new Date(Date.now() + 5 * HOUR), createdAt: old },
    });
    const fresh = await prisma.hiringTask.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, title: "Brand new", dueAt: new Date(Date.now() + 5 * HOUR) },
    });

    const first = await runHiringTaskReminders(new Date());
    assert.ok(first.includes(soon.id));
    for (const row of [later, submitted, fresh]) assert.ok(!first.includes(row.id), `${row.title} is not due for a reminder`);
    assert.ok(!(await runHiringTaskReminders(new Date())).includes(soon.id), "never twice");

    const bell = await notificationsFor(pair.candidate.id, "task");
    assert.equal(bell.length, 1);
    assert.equal(bell[0].title, "Task due soon");
    assert.equal(bell[0].link, "/tasks");
    assert.equal((await prisma.hiringTask.findUnique({ where: { id: soon.id } })).reminderSentAt != null, true);
  });

  it("claims a task reminder only once across concurrent runs", async () => {
    const pair = await h.shortlistedPair();
    const row = await prisma.hiringTask.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, title: "Race", dueAt: new Date(Date.now() + 2 * HOUR), createdAt: new Date(Date.now() - DAY) },
    });
    const runs = await Promise.all([runHiringTaskReminders(new Date()), runHiringTaskReminders(new Date())]);
    assert.equal(runs.filter((ids) => ids.includes(row.id)).length, 1);
    assert.equal((await notificationsFor(pair.candidate.id, "task")).length, 1);
  });

  it("reminds both sides of a confirmed interview 24h and 1h before, once each", async () => {
    const pair = await h.shortlistedPair();
    const slotAt = new Date(Date.now() + 20 * HOUR);
    const row = await prisma.interview.create({
      data: {
        companyId: pair.recruiter.id,
        candidateId: pair.candidate.id,
        slots: [slotAt],
        chosenSlot: slotAt,
        status: "confirmed",
        jobPostingId: pair.job.id,
      },
    });
    const proposed = await prisma.interview.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, slots: [slotAt], status: "proposed" },
    });
    const far = await prisma.interview.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, slots: [new Date(Date.now() + 3 * DAY)], chosenSlot: new Date(Date.now() + 3 * DAY), status: "confirmed" },
    });

    const now = new Date();
    const first = await runPairInterviewReminders(now);
    assert.ok(first.includes(row.id));
    assert.ok(!first.includes(proposed.id), "unconfirmed interviews are not reminded");
    assert.ok(!first.includes(far.id), "too far away");
    assert.equal((await prisma.interview.findUnique({ where: { id: row.id } })).remindersSent, 1);
    assert.ok(!(await runPairInterviewReminders(now)).includes(row.id), "the day-before one goes once");

    for (const user of [pair.candidate, pair.recruiter]) {
      const bell = await notificationsFor(user.id, "interview");
      assert.equal(bell.length, 1);
      assert.equal(bell[0].link, "/interviews");
      assert.match(bell[0].body, /tomorrow/);
      assert.match(bell[0].body, /IST/);
    }

    // 30 minutes before the slot: the second one
    const later = new Date(slotAt.getTime() - 30 * MINUTE);
    assert.ok((await runPairInterviewReminders(later)).includes(row.id));
    assert.equal((await prisma.interview.findUnique({ where: { id: row.id } })).remindersSent, 2);
    assert.ok(!(await runPairInterviewReminders(later)).includes(row.id), "and that one goes once too");
    assert.equal((await notificationsFor(pair.candidate.id, "interview")).length, 2);
    assert.equal((await notificationsFor(pair.recruiter.id, "interview")).length, 2);
  });

  it("claims an interview reminder only once across concurrent runs", async () => {
    const pair = await h.shortlistedPair();
    const slotAt = new Date(Date.now() + 10 * HOUR);
    const row = await prisma.interview.create({
      data: { companyId: pair.recruiter.id, candidateId: pair.candidate.id, slots: [slotAt], chosenSlot: slotAt, status: "confirmed" },
    });
    const now = new Date();
    const runs = await Promise.all([runPairInterviewReminders(now), runPairInterviewReminders(now)]);
    assert.equal(runs.filter((ids) => ids.includes(row.id)).length, 1);
    assert.equal((await notificationsFor(pair.candidate.id, "interview")).length, 1);
  });
});
