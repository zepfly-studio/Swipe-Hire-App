# Going to production

What has to be true before real users sign up, and the commands to get there.

## 1. Backend

Runs anywhere Node 20+ and PostgreSQL run (Railway, Render, Fly, a VM).

```bash
cd backend
npm ci
npx prisma migrate deploy      # applies the migrations; never `migrate dev` in production
NODE_ENV=production npm start
```

In production the server **refuses to start** unless every one of these is
set (and `JWT_SECRET` is at least 32 characters):

| Variable | What it is |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | long random string, e.g. `node -e "console.log(require('crypto').randomBytes(48).toString('hex'))"` |
| `FIREBASE_SERVICE_ACCOUNT_PATH` | path to the Firebase Admin key (session tokens and push) |
| `RESEND_API_KEY`, `RESEND_FROM_EMAIL` | OTP email; the sender must be on a domain verified in Resend |
| `CORS_ORIGIN` | comma-separated web origins allowed to call the API |

Optional: `PORT`, `AUTH_RATE_LIMIT`, `API_RATE_LIMIT`, `DISABLE_TASK_REMINDERS`.

Email (status changes, interview reminders, OTP) goes out through Resend. The
free test sender `onboarding@resend.dev` only delivers to the Resend account
owner, so verify a sending domain in Resend before real users sign up.

- Put it behind HTTPS (the host usually does this). `trust proxy` is already
  on, so rate limits see the real client address.
- Point an uptime monitor at `GET /health`; it returns 503 when the database
  is unreachable.
- The process shuts down cleanly on `SIGTERM`, so rolling deploys are safe.
- Run **one** instance until reminders are moved to a scheduler; two would
  each send task and interview reminders (set `DISABLE_TASK_REMINDERS=true`
  on the extra one).
- Back up the PostgreSQL database; it is the only copy of every account.

## 2. App

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://api.yourdomain.com
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.yourdomain.com
flutter build web --release --dart-define=API_BASE_URL=https://api.yourdomain.com
```

A release build refuses to start if `API_BASE_URL` is missing or not
`https://`. Optional overrides: `CLOUDINARY_CLOUD_NAME`,
`CLOUDINARY_UPLOAD_PRESET`.

Before the first store upload:

1. Create the release keystore (`docs/android-release-signing.md`). Without
   `android/key.properties` the build is debug-signed and Play will reject it.
2. Fill the legal text (`docs/legal-placeholders.md`).
3. Set `ErrorReporter.sentryWebDsn` for the web build (`docs/sentry-setup.md`).
4. Lock down the Cloudinary preset (`docs/cloudinary-setup.md`).
5. Add the Firebase web VAPID key if web push is wanted.
5a. Turn on **Google** under Firebase Console > Authentication > Sign-in
   method, add your web domain under Authentication > Settings > Authorized
   domains, and add the Android SHA-1 / SHA-256 to the Firebase Android app.
   Until then "Continue with Google" shows a "not turned on" message.
5b. Task submissions can be files (pdf, doc, docx, zip, png, jpg, txt). The
   Cloudinary unsigned preset must allow those formats and a size cap
   (`docs/cloudinary-setup.md`).
6. Decide the final Android application id **before** publishing: it is tied
   to `google-services.json`, so changing it later means registering a new
   Firebase app.

## 3. Known and accepted

- `npm audit` reports issues that need major-version upgrades (Prisma 7,
  firebase-admin 14). The high-severity ones sit in the Prisma command-line
  toolchain, not in request handling; the rest are transitive dependencies of
  firebase-admin on paths this app does not use. Schedule the upgrades; test
  them against `npm test` first.
- Sessions are 30-day JWTs with no revocation list: changing a password does
  not end sessions that already exist.
- Lists refresh by polling every few seconds, which is fine for a pilot and
  should move to server push (WebSocket/SSE) as usage grows.
- There is no iOS project yet.
