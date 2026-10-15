// Phase 4: account security -- "log out of all devices", password change and
// password reset all invalidate older tokens through User.tokenVersion.

const assert = require("node:assert/strict");
const jwt = require("jsonwebtoken");
const { describe, it, before, after } = require("node:test");
const h = require("./helpers");

const { api, prisma, signup, latestOtp } = h;

before(() => h.start());
after(() => h.stop());

async function login(user, password = user.password) {
  const res = await api("POST", "/auth/login", { body: { email: user.email, password } });
  assert.equal(res.status, 200, JSON.stringify(res.json));
  return res.json.token;
}

const me = (token) => api("GET", "/users/me", { token });

describe("tokens carry the account's tokenVersion", () => {
  it("signup, login and Google sign-in issue tokens with the current version", async () => {
    const user = await signup("candidate", "Version Vera");
    assert.equal(jwt.decode(user.token).v, 0);

    await prisma.user.update({ where: { id: user.uid }, data: { tokenVersion: 4 } });
    assert.equal((await me(user.token)).status, 401, "a token with an older version is refused");
    const fresh = await login(user);
    assert.equal(jwt.decode(fresh).v, 4);
    assert.equal((await me(fresh)).status, 200);

    h.googleClaims.next = { uid: "tmp-uid", email: user.email, name: user.name, email_verified: true };
    const google = await api("POST", "/auth/google", { body: { idToken: "x" } });
    assert.equal(google.status, 200);
    assert.equal(jwt.decode(google.json.token).v, 4);
    assert.equal((await me(google.json.token)).status, 200);
    h.googleClaims.next = null;
  });
});

describe("logout", () => {
  it("POST /auth/logout is an acknowledged no-op", async () => {
    const user = await signup("candidate", "Plain Logout");
    const res = await api("POST", "/auth/logout", { token: user.token });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, { ok: true });
    assert.equal((await me(user.token)).status, 200, "the token keeps working");
    assert.equal((await api("POST", "/auth/logout")).status, 200, "also fine without a token");
  });

  it("POST /auth/logout-all kills every token, including the calling one", async () => {
    const user = await signup("recruiter", "Everywhere Eve");
    const second = await login(user);
    assert.equal((await me(second)).status, 200);

    const res = await api("POST", "/auth/logout-all", { token: user.token });
    assert.equal(res.status, 200);
    assert.deepEqual(res.json, { ok: true });

    for (const token of [user.token, second]) {
      const dead = await me(token);
      assert.equal(dead.status, 401);
      assert.equal(dead.json.error, "Your session has expired, please log in again.");
    }

    const again = await login(user);
    assert.equal((await me(again)).status, 200);
    assert.equal((await prisma.user.findUnique({ where: { id: user.uid } })).tokenVersion, 1);
  });

  it("needs a token", async () => {
    assert.equal((await api("POST", "/auth/logout-all")).status, 401);
  });
});

describe("PUT /users/me/password", () => {
  it("changes the password, returns a working token and kills the old ones", async () => {
    const user = await signup("candidate", "Change Charlie");
    const otherDevice = await login(user);

    const res = await api("PUT", "/users/me/password", {
      token: user.token,
      body: { current: user.password, next: "a-brand-new-pass" },
    });
    assert.equal(res.status, 200, JSON.stringify(res.json));
    assert.equal(res.json.ok, true);
    assert.ok(res.json.token);

    assert.equal((await me(res.json.token)).status, 200, "new token works");
    assert.equal((await me(user.token)).status, 401, "the token used for the change is dead");
    assert.equal((await me(otherDevice)).status, 401, "other devices are signed out");

    const old = await api("POST", "/auth/login", { body: { email: user.email, password: user.password } });
    assert.equal(old.status, 401);
    assert.equal(await login(user, "a-brand-new-pass").then((t) => (jwt.decode(t).v)), 1);
  });

  it("rejects a wrong current password and a short new one, with the field", async () => {
    const user = await signup("recruiter", "Wrong Walt");

    const wrong = await api("PUT", "/users/me/password", {
      token: user.token,
      body: { current: "not-my-password", next: "another-long-one" },
    });
    assert.equal(wrong.status, 400);
    assert.equal(wrong.json.error, "Your current password is not correct");
    assert.equal(wrong.json.field, "current");

    const short = await api("PUT", "/users/me/password", { token: user.token, body: { current: user.password, next: "short" } });
    assert.equal(short.status, 400);
    assert.equal(short.json.error, "New password must be at least 8 characters");
    assert.equal(short.json.field, "next");

    const missing = await api("PUT", "/users/me/password", { token: user.token, body: {} });
    assert.equal(missing.status, 400);

    // Nothing changed: the original password and token still work.
    assert.equal((await me(user.token)).status, 200);
    await login(user);
    assert.equal((await api("PUT", "/users/me/password", { body: { current: "a", next: "bbbbbbbb" } })).status, 401);
  });
});

describe("password reset", () => {
  it("signs the account out everywhere", async () => {
    const user = await signup("candidate", "Reset Rita");
    const device = await login(user);

    const asked = await api("POST", "/auth/password/forgot", { body: { email: user.email } });
    assert.equal(asked.status, 200);
    const otp = await latestOtp(user.email, "reset");
    const done = await api("POST", "/auth/password/reset", {
      body: { email: user.email, otp, newPassword: "reset-password-1" },
    });
    assert.equal(done.status, 200, JSON.stringify(done.json));

    assert.equal((await me(user.token)).status, 401);
    assert.equal((await me(device)).status, 401);
    const token = await login(user, "reset-password-1");
    assert.equal((await me(token)).status, 200);
  });
});
