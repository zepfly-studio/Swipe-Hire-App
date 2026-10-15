// Phase 4 teams: invites, one shared company for owner + members (jobs,
// swipes, credits, chat, interviews, tasks, searches, payments), member
// removal, what candidates see, and notification fan-out. Real app, real dev
// database, real HTTP (same harness as the other suites).

const assert = require("node:assert/strict");
const { describe, it, before, after } = require("node:test");
const t = require("./team-helpers");

const { h, invite, joinTeam, ownerWithJob, notificationsFor, sha256 } = t;
const { api, prisma } = h;

before(() => h.start());
after(() => h.stop());

const inDays = (n) => new Date(Date.now() + n * 24 * 60 * 60 * 1000).toISOString();

// ------------------------------------------------------------- invites --

describe("team invites", () => {
  it("lets the owner invite, shows the invite, and lets the invitee join with a full session", async () => {
    const { owner } = await ownerWithJob("Olivia Owner");
    const email = h.emailFor("recruiter");

    const bad = await api("POST", "/team/invite", { token: owner.token, body: { email: "nope" } });
    assert.equal(bad.status, 400);
    assert.equal(bad.json.field, "email");

    const sent = await api("POST", "/team/invite", { token: owner.token, body: { email } });
    assert.equal(sent.status, 201, JSON.stringify(sent.json));
    assert.equal(sent.json.ok, true);
    assert.ok(sent.json.inviteCode && sent.json.inviteCode.length >= 30);
    const code = sent.json.inviteCode;

    // The code is also in the email; only its hash is stored.
    const mail = h.emails.filter((m) => m.to === email).pop();
    assert.ok(mail && mail.body.includes(code), "the email carries the code");
    const stored = await prisma.teamInvite.findFirst({ where: { email } });
    assert.equal(stored.tokenHash, sha256(code));
    assert.notEqual(stored.tokenHash, code);
    assert.ok(Math.abs(stored.expiresAt.getTime() - (Date.now() + 7 * 24 * 3600 * 1000)) < 60 * 1000);

    const listed = await api("GET", "/team", { token: owner.token });
    assert.equal(listed.status, 200);
    assert.equal(listed.json.isOwner, true);
    assert.deepEqual(
      listed.json.members.map((m) => ({ role: m.role, you: m.you, id: m.id })),
      [{ role: "owner", you: true, id: owner.uid }],
    );
    assert.equal(listed.json.invites.length, 1);
    assert.equal(listed.json.invites[0].email, email);
    assert.ok(listed.json.invites[0].id && listed.json.invites[0].expires);

    const preview = await api("GET", `/auth/invite/${code}`);
    assert.equal(preview.status, 200);
    assert.equal(preview.json.email, email);
    assert.equal(preview.json.companyName, "FlowCorp");

    const short = await api("POST", "/auth/accept-invite", { body: { token: code, name: "Mia Member", password: "short" } });
    assert.equal(short.status, 400);
    assert.equal(short.json.field, "password");
    const noName = await api("POST", "/auth/accept-invite", { body: { token: code, name: " ", password: "password123" } });
    assert.equal(noName.status, 400);
    assert.equal(noName.json.field, "name");

    const joined = await api("POST", "/auth/accept-invite", { body: { token: code, name: "Mia Member", password: "password123" } });
    assert.equal(joined.status, 201, JSON.stringify(joined.json));
    assert.ok(joined.json.token);
    assert.equal(joined.json.firebaseToken, `firebase-token-${joined.json.user.uid}`);
    const user = joined.json.user;
    assert.equal(user.email, email);
    assert.equal(user.role, "recruiter");
    assert.equal(user.isOwner, false);
    assert.equal(user.companyId, owner.uid);
    assert.equal(user.company, "FlowCorp");
    assert.equal(user.profileComplete, true);
    assert.equal(user.emailVerified, true);

    const row = await prisma.user.findUnique({ where: { id: user.uid } });
    assert.equal(row.companyOwnerId, owner.uid);

    // The new login works with the password, and the member sees the same team.
    const login = await api("POST", "/auth/login", { body: { email, password: "password123" } });
    assert.equal(login.status, 200);
    const team = await api("GET", "/team", { token: joined.json.token });
    assert.equal(team.json.isOwner, false);
    assert.equal(team.json.members.length, 2);
    assert.equal(team.json.members[0].role, "owner");
    assert.equal(team.json.members[1].role, "recruiter");
    assert.equal(team.json.members[1].you, true);
    assert.equal(team.json.invites.length, 0, "the accepted invite is gone from the pending list");
  });

  it("replaces an older pending invite for the same email", async () => {
    const { owner } = await ownerWithJob();
    const first = await invite(owner);
    const second = await invite(owner, first.email);
    assert.notEqual(first.code, second.code);

    assert.equal((await api("GET", `/auth/invite/${first.code}`)).status, 404);
    assert.equal((await api("GET", `/auth/invite/${second.code}`)).status, 200);
    const listed = await api("GET", "/team", { token: owner.token });
    assert.equal(listed.json.invites.length, 1);
  });

  it("refuses an email that already has an account, and a team over 10 people", async () => {
    const { owner } = await ownerWithJob();
    const other = await h.signup("candidate", "Existing Person");
    const taken = await api("POST", "/team/invite", { token: owner.token, body: { email: other.email } });
    assert.equal(taken.status, 409);
    assert.equal(taken.json.error, "This email already has a Swipe Hire account");

    // Owner + 9 pending invites = 10 people.
    const emails = [];
    for (let i = 0; i < 9; i++) {
      const sent = await invite(owner);
      emails.push(sent.email);
    }
    const tooMany = await api("POST", "/team/invite", { token: owner.token, body: { email: h.emailFor("recruiter") } });
    assert.equal(tooMany.status, 400);
    assert.equal(tooMany.json.error, "Your team can have up to 10 people.");
    // Re-inviting somebody who is already pending replaces, so it still fits.
    const replace = await api("POST", "/team/invite", { token: owner.token, body: { email: emails[0] } });
    assert.equal(replace.status, 201);
  });

  it("rejects expired, used and unknown invites, and an email that registered in the meantime", async () => {
    const { owner } = await ownerWithJob();

    const expired = await invite(owner);
    await prisma.teamInvite.updateMany({ where: { tokenHash: sha256(expired.code) }, data: { expiresAt: new Date(Date.now() - 1000) } });
    const gone = await api("GET", `/auth/invite/${expired.code}`);
    assert.equal(gone.status, 404);
    assert.equal(gone.json.error, "This invite link is invalid or has expired. Ask your team for a new one.");
    const acceptExpired = await api("POST", "/auth/accept-invite", { body: { token: expired.code, name: "Late Larry", password: "password123" } });
    assert.equal(acceptExpired.status, 404);

    assert.equal((await api("GET", "/auth/invite/not-a-real-code")).status, 404);
    assert.equal((await api("POST", "/auth/accept-invite", { body: { token: "nope", name: "X", password: "password123" } })).status, 404);

    const used = await invite(owner);
    const body = { token: used.code, name: "Once Only", password: "password123" };
    assert.equal((await api("POST", "/auth/accept-invite", { body })).status, 201);
    const twice = await api("POST", "/auth/accept-invite", { body });
    assert.equal(twice.status, 409);
    assert.equal(twice.json.error, "This invite was already used");
    assert.equal((await api("GET", `/auth/invite/${used.code}`)).status, 404);

    // The address signs up on its own before using the invite.
    const racing = await invite(owner);
    await prisma.user.create({
      data: { name: "Taken", email: racing.email, passwordHash: "x", role: "candidate", emailVerified: true },
    });
    const conflict = await api("POST", "/auth/accept-invite", { body: { token: racing.code, name: "Racer", password: "password123" } });
    assert.equal(conflict.status, 409);
    assert.equal(conflict.json.error, "An account with this email already exists");
  });

  it("is owner-only: members and candidates cannot invite or remove people", async () => {
    const { owner } = await ownerWithJob();
    const member = await joinTeam(owner);
    const pending = await invite(owner);
    const pendingRow = await prisma.teamInvite.findFirst({ where: { tokenHash: sha256(pending.code) } });

    const invited = await api("POST", "/team/invite", { token: member.token, body: { email: h.emailFor("recruiter") } });
    assert.equal(invited.status, 403);
    assert.equal((await api("DELETE", `/team/invites/${pendingRow.id}`, { token: member.token })).status, 403);
    assert.equal((await api("DELETE", `/team/members/${owner.uid}`, { token: member.token })).status, 403);

    const candidate = await h.signup("candidate", "Not A Recruiter");
    assert.equal((await api("GET", "/team", { token: candidate.token })).status, 403);

    // The owner can cancel a pending invite, but not remove themselves or strangers.
    assert.equal((await api("DELETE", `/team/members/${owner.uid}`, { token: owner.token })).json.error, "You cannot remove yourself");
    assert.equal((await api("DELETE", `/team/members/${candidate.uid}`, { token: owner.token })).status, 404);
    assert.equal((await api("DELETE", `/team/invites/${pendingRow.id}`, { token: owner.token })).status, 200);
    assert.equal((await api("GET", `/auth/invite/${pending.code}`)).status, 404);
    assert.equal((await api("DELETE", `/team/invites/${pendingRow.id}`, { token: owner.token })).status, 404);
  });
});

// ------------------------------------------------------- shared company --

describe("one company for owner and members", () => {
  it("shares jobs, and a member's posting belongs to the company", async () => {
    const { owner, job } = await ownerWithJob("Jobs Owner");
    const member = await joinTeam(owner, "Jay Member");

    const seen = await api("GET", "/jobs/mine", { token: member.token });
    assert.equal(seen.status, 200);
    assert.deepEqual(seen.json.jobs.map((j) => j.id), [job.id]);

    const created = await h.postJob(member, { title: "Backend Engineer" });
    const row = await prisma.jobPosting.findUnique({ where: { id: created.id } });
    assert.equal(row.recruiterId, owner.uid, "the posting hangs off the owner id");

    const ownerView = await api("GET", "/jobs/mine", { token: owner.token });
    assert.equal(ownerView.json.jobs.length, 2);

    // Either teammate can edit and pause any of the company's jobs.
    const paused = await api("PATCH", `/jobs/${created.id}/status`, { token: owner.token, body: { status: "paused" } });
    assert.equal(paused.status, 200);
    const edited = await api("PUT", `/jobs/${job.id}`, {
      token: member.token,
      body: { title: "Senior Flutter Developer", skills: ["Flutter"], salaryMaxLpa: 30 },
    });
    assert.equal(edited.status, 200, JSON.stringify(edited.json));
    assert.equal(edited.json.title, "Senior Flutter Developer");

    // Somebody else's company stays out of reach.
    const stranger = await h.signup("recruiter", "Stranger");
    const denied = await api("PATCH", `/jobs/${job.id}/status`, { token: stranger.token, body: { status: "closed" } });
    assert.equal(denied.status, 403);
  });

  it("shares swipes, wishlist, the shortlist pipeline and credits (decremented once)", async () => {
    const { owner, job } = await ownerWithJob("Swipe Owner", { swipes: 10 });
    const member = await joinTeam(owner, "Sam Member");
    const [c1, c2, c3] = [
      await h.candidateWithProfile("Cand One"),
      await h.candidateWithProfile("Cand Two"),
      await h.candidateWithProfile("Cand Three"),
    ];

    const deck = await api("GET", `/candidates?jobId=${job.id}&limit=5`, { token: member.token });
    assert.equal(deck.status, 200, JSON.stringify(deck.json));
    assert.equal(deck.json.swipesLeft, 10, "the member sees the owner's balance");
    assert.equal(deck.json.job.id, job.id);

    const first = await t.swipe(member, c1.uid, "right", job.id);
    assert.equal(first.status, 200, JSON.stringify(first.json));
    assert.equal(first.json.swipesLeft, 9);
    assert.ok(first.json.contact.email);

    const second = await t.swipe(owner, c2.uid, "right", job.id);
    assert.equal(second.json.swipesLeft, 8, "one shared balance");
    assert.equal(await prisma.company.findUnique({ where: { ownerId: owner.uid } }).then((c) => c.swipesLeft), 8);

    // The pair was already swiped by the teammate, so the owner cannot swipe again.
    const dup = await t.swipe(owner, c1.uid, "left", job.id);
    assert.equal(dup.status, 409);
    assert.equal((await api("GET", `/candidates?jobId=${job.id}&limit=30`, { token: owner.token })).json.swipesLeft, 8, "no credit lost on a duplicate");

    const rows = await prisma.candidateSwipe.findMany({ where: { candidateId: { in: [c1.uid, c2.uid] } } });
    assert.equal(rows.length, 2);
    assert.ok(rows.every((r) => r.recruiterId === owner.uid), "swipes are keyed by the company id");

    // Wishlist is shared.
    const wish = await api("PUT", `/company/wishlist/${c3.uid}`, { token: member.token, body: { wishlisted: true } });
    assert.equal(wish.json.wishlisted, true);
    const ownerWish = await api("GET", "/company/wishlist", { token: owner.token });
    assert.deepEqual(ownerWish.json.candidates.map((c) => c.id), [c3.uid]);

    // Shortlist and pipeline: each sees (and can move) the other's candidates.
    const shortlist = await api("GET", "/company/shortlisted", { token: member.token });
    assert.deepEqual(new Set(shortlist.json.candidates.map((c) => c.id)), new Set([c1.uid, c2.uid]));
    const mine = shortlist.json.candidates.find((c) => c.id === c2.uid);
    const moved = await api("PATCH", `/company/pipeline/${mine.swipeId}`, { token: member.token, body: { stage: "contacted", notes: "shared" } });
    assert.equal(moved.status, 200);
    const ownerShort = await api("GET", "/company/shortlisted", { token: owner.token });
    assert.equal(ownerShort.json.candidates.find((c) => c.id === c2.uid).stage, "contacted");

    // Undo works on the company's latest swipe (and refunds a left swipe once).
    const left = await t.swipe(member, c3.uid, "left", job.id);
    assert.equal(left.json.swipesLeft, 7);
    const undone = await api("POST", "/company/swipe/undo", { token: owner.token });
    assert.equal(undone.status, 200, JSON.stringify(undone.json));
    assert.equal(undone.json.swipesLeft, 8);

    // Saved searches are shared.
    const saved = await api("POST", "/company/searches", { token: member.token, body: { name: "Pune devs", filters: { location: "Pune" } } });
    assert.equal(saved.status, 201, JSON.stringify(saved.json));
    const ownerSearches = await api("GET", "/company/searches", { token: owner.token });
    assert.deepEqual(ownerSearches.json.searches.map((s) => s.id), [saved.json.search.id]);
  });

  it("credits a member's purchase to the company balance", async () => {
    const { owner } = await ownerWithJob("Pay Owner", { swipes: 3 });
    const member = await joinTeam(owner, "Pat Member");

    const order = await api("POST", "/payment/order", { token: member.token, body: { planId: "starter" } });
    assert.equal(order.status, 200, JSON.stringify(order.json));
    const row = await prisma.payment.findUnique({ where: { orderId: order.json.orderId } });
    assert.equal(row.recruiterId, owner.uid);

    // The owner can finish the purchase a teammate started, and it only counts once.
    const verify = await api("POST", "/payment/verify", { token: owner.token, body: { orderId: order.json.orderId } });
    assert.equal(verify.status, 200, JSON.stringify(verify.json));
    assert.equal(verify.json.added, 150);
    assert.equal(verify.json.swipesLeft, 153);
    const again = await api("POST", "/payment/verify", { token: member.token, body: { orderId: order.json.orderId } });
    assert.equal(again.json.added, 0);
    assert.equal(again.json.swipesLeft, 153);
  });
});

// ------------------------------------------------- chat, interviews, tasks --

describe("pair features inside a team", () => {
  async function setup() {
    const { owner, job } = await ownerWithJob("Olivia Owner", { swipes: 50 });
    const member = await joinTeam(owner, "Mia Member");
    const candidate = await h.candidateWithProfile("Cara Candidate");
    const swiped = await t.swipe(owner, candidate.uid, "right", job.id);
    assert.equal(swiped.status, 200);
    return { owner, member, candidate, job };
  }

  it("shows teammates' messages as mine with `by`, and the candidate sees one company", async () => {
    const { owner, member, candidate } = await setup();

    const fromMember = await api("POST", `/chats/${candidate.uid}`, { token: member.token, body: { text: "Hi from Mia" } });
    assert.equal(fromMember.status, 201, JSON.stringify(fromMember.json));
    assert.equal(fromMember.json.message.mine, true);
    assert.equal(fromMember.json.message.by, undefined, "own messages carry no `by`");
    const fromOwner = await api("POST", `/chats/${candidate.uid}`, { token: owner.token, body: { text: "And from Olivia" } });
    assert.equal(fromOwner.status, 201);

    const ownerThread = await api("GET", `/chats/${candidate.uid}`, { token: owner.token });
    assert.equal(ownerThread.status, 200);
    assert.deepEqual(
      ownerThread.json.messages.map((m) => ({ text: m.text, mine: m.mine, by: m.by })),
      [
        { text: "Hi from Mia", mine: true, by: "Mia" },
        { text: "And from Olivia", mine: true, by: undefined },
      ],
    );
    const memberThread = await api("GET", `/chats/${candidate.uid}`, { token: member.token });
    assert.deepEqual(
      memberThread.json.messages.map((m) => ({ mine: m.mine, by: m.by })),
      [
        { mine: true, by: undefined },
        { mine: true, by: "Olivia" },
      ],
    );

    // The conversation list and last message are shared too.
    const convos = await api("GET", "/chats", { token: member.token });
    assert.equal(convos.json.conversations.length, 1);
    assert.equal(convos.json.conversations[0].id, candidate.uid);
    assert.equal(convos.json.conversations[0].lastMessage.mine, true);

    // The candidate only knows the company by the owner's id.
    const candThread = await api("GET", `/chats/${owner.uid}`, { token: candidate.token });
    assert.equal(candThread.status, 200);
    assert.equal(candThread.json.with.id, owner.uid);
    assert.deepEqual(candThread.json.messages.map((m) => m.mine), [false, false]);
    assert.equal(candThread.json.messages[0].by, undefined);
    // Only the company (owner id) is a conversation partner; a teammate's own id is not.
    assert.equal((await api("GET", `/chats/${member.uid}`, { token: candidate.token })).status, 403);

    const contacts = await api("GET", "/chats/contacts", { token: candidate.token });
    assert.deepEqual(contacts.json.contacts.map((c) => c.id), [owner.uid]);

    // A teammate's first message counts as contact: the candidate may reply.
    const reply = await api("POST", `/chats/${owner.uid}`, { token: candidate.token, body: { text: "Hello!" } });
    assert.equal(reply.status, 201);
  });

  it("lets a candidate reply to a company only one teammate had contacted, and shares unread state", async () => {
    const { owner, member, candidate } = await setup();
    await api("POST", `/chats/${candidate.uid}`, { token: member.token, body: { text: "Hello" } });

    const reply = await api("POST", `/chats/${owner.uid}`, { token: candidate.token, body: { text: "Hi, interested" } });
    assert.equal(reply.status, 201, JSON.stringify(reply.json));
    await h.idle();

    // Owner and member are both notified, once each.
    for (const person of [owner, member]) {
      const bell = await notificationsFor(person.uid, "message");
      assert.equal(bell.length, 1, `${person.name} gets the message notification`);
      assert.equal(bell[0].link, `/messages?with=${candidate.uid}`);
      assert.equal(bell[0].title, "New message from Cara Candidate");
      assert.equal((await api("GET", "/chats/unread-count", { token: person.token })).json.count, 1);
    }
    assert.ok(h.emails.some((m) => m.to === owner.email), "the owner is emailed");
    assert.ok(h.emails.some((m) => m.to === member.email), "the member is emailed");

    // A second message while unread only pushes.
    await api("POST", `/chats/${owner.uid}`, { token: candidate.token, body: { text: "Any update?" } });
    await h.idle();
    assert.equal((await notificationsFor(member.uid, "message")).length, 1);
    assert.equal((await api("GET", "/chats/unread-count", { token: member.token })).json.count, 2);

    // One teammate reading the thread clears it for the company.
    await api("GET", `/chats/${candidate.uid}`, { token: member.token });
    assert.equal((await api("GET", "/chats/unread-count", { token: owner.token })).json.count, 0);
    const candThread = await api("GET", `/chats/${owner.uid}`, { token: candidate.token });
    assert.deepEqual(candThread.json.messages.map((m) => m.mine), [false, true, true]);
    assert.equal(candThread.json.messages[0].read, true, "the candidate read the company's message");
  });

  it("shares interviews and tells the whole team when the candidate accepts or cancels", async () => {
    const { owner, member, candidate, job } = await setup();
    const slot = new Date(Date.now() + 2 * 24 * 3600 * 1000).toISOString();

    const created = await api("POST", "/interviews", {
      token: member.token,
      body: { candidateId: candidate.uid, jobId: job.id, slots: [slot], durationMins: 30, mode: "video" },
    });
    assert.equal(created.status, 201, JSON.stringify(created.json));
    const row = await prisma.interview.findUnique({ where: { id: created.json.id } });
    assert.equal(row.companyId, owner.uid);

    const ownerList = await api("GET", "/interviews", { token: owner.token });
    assert.deepEqual(ownerList.json.interviews.map((i) => i.id), [created.json.id]);
    const candList = await api("GET", "/interviews", { token: candidate.token });
    assert.equal(candList.json.interviews[0].with.id, owner.uid);

    // Duplicate guard is per company, not per teammate.
    const dup = await api("POST", "/interviews", {
      token: owner.token,
      body: { candidateId: candidate.uid, slots: [slot], durationMins: 30, mode: "phone" },
    });
    assert.equal(dup.status, 409);

    const accepted = await api("POST", `/interviews/${created.json.id}/accept`, { token: candidate.token, body: { slot } });
    assert.equal(accepted.status, 200, JSON.stringify(accepted.json));
    await h.idle();
    for (const person of [owner, member]) {
      const bell = await notificationsFor(person.uid, "interview");
      assert.equal(bell.length, 1, `${person.name} hears about the confirmation`);
      assert.match(bell[0].title, /confirmed the interview/);
      assert.ok(h.emails.some((m) => m.to === person.email && /Interview confirmed/.test(m.subject)));
    }

    // The owner can cancel one a teammate scheduled; the candidate cancelling tells the team.
    const second = await api("POST", "/interviews", {
      token: owner.token,
      body: { candidateId: candidate.uid, slots: [new Date(Date.now() + 5 * 24 * 3600 * 1000).toISOString()], mode: "phone" },
    });
    assert.equal(second.status, 409, "the confirmed one is still upcoming");
    const cancelled = await api("POST", `/interviews/${created.json.id}/cancel`, { token: candidate.token, body: { reason: "Cannot make it" } });
    assert.equal(cancelled.status, 200);
    await h.idle();
    for (const person of [owner, member]) {
      const bell = await notificationsFor(person.uid, "interview");
      assert.equal(bell.length, 2);
      assert.match(bell[1].title, /cancelled the interview/);
    }
    const cancelledRow = await prisma.interview.findUnique({ where: { id: created.json.id } });
    assert.equal(cancelledRow.cancelledById, candidate.uid);
  });

  it("shares tasks (creator stays the person) and tells the whole team about a submission", async () => {
    const { owner, member, candidate, job } = await setup();

    const created = await api("POST", "/tasks", {
      token: member.token,
      body: {
        candidateId: candidate.uid,
        jobId: job.id,
        title: "Build a todo app",
        description: "Flutter, with tests.",
        dueAt: new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString(),
      },
    });
    assert.equal(created.status, 201, JSON.stringify(created.json));
    const row = await prisma.hiringTask.findUnique({ where: { id: created.json.id } });
    assert.equal(row.companyId, owner.uid);
    assert.equal(row.createdById, member.uid, "the creator is the teammate, not the company");

    const ownerTasks = await api("GET", `/tasks?candidateId=${candidate.uid}`, { token: owner.token });
    assert.deepEqual(ownerTasks.json.tasks.map((x) => x.id), [created.json.id]);
    const candTasks = await api("GET", "/tasks", { token: candidate.token });
    assert.equal(candTasks.json.tasks[0].with.id, owner.uid);

    const moved = await api("PATCH", `/tasks/${created.json.id}`, {
      token: owner.token,
      body: { dueAt: new Date(Date.now() + 4 * 24 * 3600 * 1000).toISOString() },
    });
    assert.equal(moved.status, 200, "any teammate can change the deadline");

    const submitted = await api("POST", `/tasks/${created.json.id}/submit`, {
      token: candidate.token,
      body: { repoUrl: "https://github.com/cara/todo", note: "done" },
    });
    assert.equal(submitted.status, 200, JSON.stringify(submitted.json));
    await h.idle();
    for (const person of [owner, member]) {
      const bell = await notificationsFor(person.uid, "task");
      assert.equal(bell.length, 1, `${person.name} hears about the submission`);
      assert.match(bell[0].title, /submitted a task/);
      assert.ok(h.emails.some((m) => m.to === person.email && /submitted/.test(m.subject)));
    }

    assert.equal((await api("POST", `/tasks/${created.json.id}/cancel`, { token: member.token })).status, 200);
  });

  it("fans saved-search alerts out to the owner and every member", async () => {
    const { owner } = await ownerWithJob("Alert Owner");
    const member = await joinTeam(owner, "Alex Member");
    const place = `Zz${Date.now() % 100000}`;
    const saved = await api("POST", "/company/searches", { token: member.token, body: { name: "Team watch", filters: { location: place } } });
    assert.equal(saved.status, 201, JSON.stringify(saved.json));

    await h.candidateWithProfile("Alert Candidate", { location: place });
    await h.idle();

    for (const person of [owner, member]) {
      const alerts = await notificationsFor(person.uid, "alert");
      assert.equal(alerts.length, 1, `${person.name} gets the alert once`);
      assert.equal(alerts[0].title, 'New match for "Team watch"');
      assert.equal(alerts[0].link, `/company/swipe?search=${saved.json.search.id}`);
    }
  });

  it("tells the candidate who hired them with the owner's id, and stats name the company once", async () => {
    const { owner, member, candidate, job } = await setup();
    await api("POST", `/chats/${candidate.uid}`, { token: member.token, body: { text: "Welcome" } });

    const shortlisted = await api("GET", "/company/shortlisted", { token: member.token });
    const swipe = shortlisted.json.candidates.find((c) => c.id === candidate.uid);
    const hired = await api("PATCH", `/company/pipeline/${swipe.swipeId}`, { token: member.token, body: { stage: "hired" } });
    assert.equal(hired.status, 200);

    const hiredNote = (await notificationsFor(candidate.uid, "hired"))[0];
    assert.equal(hiredNote.link, `/messages?with=${owner.uid}`);
    assert.match(hiredNote.title, /FlowCorp selected you/);

    const stats = await api("GET", "/candidates/me/stats", { token: candidate.token });
    assert.equal(stats.json.shortlistedBy.length, 1);
    assert.equal(stats.json.shortlistedBy[0].recruiterId, owner.uid);
    assert.equal(stats.json.shortlistedBy[0].companyId, owner.uid);
    assert.equal(stats.json.shortlistedBy[0].hiringFor, job.title);
    assert.equal(stats.json.hiddenCount, 0);
  });
});

// -------------------------------------------------------------- removal --

describe("removing a member", () => {
  it("deletes the login so its token dies, keeps the company's data, and frees the seat", async () => {
    const { owner, job } = await ownerWithJob("Remove Owner", { swipes: 20 });
    const member = await joinTeam(owner, "Gone Member");
    const candidate = await h.candidateWithProfile("Stay Candidate");

    assert.equal((await t.swipe(member, candidate.uid, "right", job.id)).status, 200);
    assert.equal((await api("POST", `/chats/${candidate.uid}`, { token: member.token, body: { text: "From the member" } })).status, 201);
    assert.equal((await api("GET", "/jobs/mine", { token: member.token })).status, 200);

    const removed = await api("DELETE", `/team/members/${member.uid}`, { token: owner.token });
    assert.equal(removed.status, 200, JSON.stringify(removed.json));

    const dead = await api("GET", "/jobs/mine", { token: member.token });
    assert.equal(dead.status, 401);
    assert.equal(await prisma.user.findUnique({ where: { id: member.uid } }), null);
    assert.ok(h.deletedFirebaseUsers.includes(member.uid));
    assert.equal((await api("POST", "/auth/login", { body: { email: member.email, password: member.password } })).status, 401);

    // What the teammate did stays with the company.
    const shortlist = await api("GET", "/company/shortlisted", { token: owner.token });
    assert.deepEqual(shortlist.json.candidates.map((c) => c.id), [candidate.uid]);
    const thread = await api("GET", `/chats/${candidate.uid}`, { token: owner.token });
    assert.deepEqual(thread.json.messages.map((m) => m.text), ["From the member"]);
    assert.equal(thread.json.messages[0].mine, true);

    const team = await api("GET", "/team", { token: owner.token });
    assert.equal(team.json.members.length, 1);

    // The removed address can be invited again.
    const again = await api("POST", "/team/invite", { token: owner.token, body: { email: member.email } });
    assert.equal(again.status, 201);
  });
});
