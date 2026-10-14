# SwipeHire — Production Readiness Review & Roadmap

_Review date: 14 Oct 2026 (updated the same day after the Postgres migration). Codebase: Flutter app (~10k lines Dart, 40 screens/widgets), Node + Postgres backend (all app data), Firebase (Auth session + FCM only), Resend email, Cloudinary media._

---

## 1. Where the app stands today

### Working end-to-end

| Area | What exists |
|---|---|
| Accounts | Email + password signup with 6-digit OTP (emailed via Resend), login, forgot/reset password, password-confirmed account deletion (cascades in Postgres), "Export my data" (DPDP style). Backend: Express + Prisma + Postgres, JWT, rate limiting, helmet, Firebase custom-token bridge. |
| Candidate side | 5-tab shell (Dashboard, Jobs, Applications, Saved, Profile). Full profile: age, qualification, experience, desired role, location, skills, expected CTC, notice period, about, current company/CTC, photo, PDF resume, intro video (Cloudinary, size/type validated). Browse open jobs with text search, job detail, apply (duplicate-apply guard), save/unsave jobs, live application status, chat with recruiter. |
| Recruiter side | 5-tab shell (Discover, Wishlist, Shortlist, Pipeline, Profile). Paginated swipe deck of real candidates, in-deck search, resume viewer, intro-video player, Wishlist → Shortlist funnel, undo. Pipeline: status (Applied → Shortlisted → Interview → Offer → Hired/Rejected), interview slot (date, mode, details), offer (CTC, joining date, notes), find candidate by email. My Postings: create/edit/open/close job postings. |
| Hiring flow | Wishlist → Shortlist → **assign a task** (title, instructions, link, due date) → candidate submits an answer/link in their Applications tab → recruiter approves, asks for changes or rejects → **schedule interview**, which pushes the candidate and drops the date, mode and link into the chat. Every step also posts a labelled card into the chat. |
| Data | **Every record is in Postgres** behind the Node API: profiles, jobs, applications/pipeline, chat, saved jobs, recruiter wishlist/shortlist. Firebase is only the auth session and FCM push. Screens poll the API (every 2 to 15 s, plus instantly after any write) so lists and chat feel live. Push on status change, new applicant and new message is sent by the backend. |
| Security | Role and ownership checks on every backend route (recruiter vs candidate, owner-only edits, chat limited to its two parties), per-IP rate limits, helmet, Crashlytics (mobile) + Sentry hook (web), Firebase Analytics events. |
| Quality | `flutter analyze` clean, 65 Flutter tests and 48 backend tests passing, release web build verified, GitHub Actions CI (analyze + test + backend schema check), manual signed-Android release workflow, setup docs, Terms & Privacy screens. |

### Verdict

This is a solid **working MVP / strong prototype**, clearly beyond a college demo. It is **not yet production-ready**. The gaps fall in three groups: things that block any public release, features every real hiring product has that are missing, and engineering debt that will bite at scale.

---

## 2. Gaps — Group A: Release blockers (must fix before anyone outside the team uses it)

1. **Backend is localhost-only.** `api_client.dart` defaults to `http://10.0.2.2:4000` / `localhost:4000`. A release build throws unless `--dart-define=API_BASE_URL` is set. The Node backend is not deployed anywhere, has no Dockerfile, no process manager, no hosted Postgres.
2. **Nothing is committed.** 72 files are modified/untracked, including the entire `backend/` folder, `.github/` CI, and the job-board + theme work. If the laptop dies, the backend is gone.
3. **Config placeholders.** Resend API key not set yet (OTP emails show on screen in dev mode; see docs/signup-otp-setup.md), Sentry DSN empty, web push (VAPID key) not set up, Android release keystore not generated, app id still `com.hiringapp.hiring_app`, Terms/Privacy contain `[FILL IN BEFORE LAUNCH]` placeholders.
4. **No iOS project.** The `ios/` folder does not exist; the app cannot be built for iPhone at all.
5. ~~Recruiter Wishlist / Shortlist device-local~~ **Done 14 Oct:** now stored in the `swipes` table, loaded on sign-in, identical on every device.
6. ~~Candidate privacy leak via Firestore rules~~ **Done 14 Oct:** recruiters only receive the candidate card shape from the API (no phone, email or push token); the email lookup route returns a profile only for an exact-match email the recruiter already knows.
7. ~~Two OTP systems~~ **Done 14 Oct:** Cloud Functions and Firestore removed entirely; one OTP flow in the backend, emailed through Resend.
8. ~~N+1 reads in candidate deck~~ **Done 14 Oct:** one SQL query with a join per page.
9. **Email delivery still in dev mode** until a Resend key and sender are configured.

---

## 3. Gaps — Group B: Missing product features (what makes it a "real" hiring app)

### For recruiters
- **Applicants per job.** There is no "View applicants" on a posting and no applicant count. Pipeline is one flat list with a status filter. Recruiters need: Posting → applicants list → candidate profile → action.
- **Server-side search & filters.** Current search only filters the ~20 cards already loaded. Need filters on skills, location, experience range, expected CTC, notice period, qualification. Postgres `ILIKE` / array-overlap queries cover the first version; Postgres full-text or Typesense later.
- **Match score.** No ranking. A simple skills-overlap + location + CTC fit score (0–100) on each card and each applicant changes the product from "swipe randomly" to "swipe smart".
- **Company profile & verification.** Anyone can sign up as a recruiter and post jobs. Need company page (logo, about, website, size), email-domain or document verification, and a "Verified" badge.
- **Interview tooling.** Interview slot is just text. Need calendar invite (.ics / Google Calendar), reminders (push + email 24h / 1h before), and a video-call link field (Google Meet).
- **Notes & tags on candidates**, bulk actions, pipeline analytics (time-to-hire, funnel conversion).

### For candidates
- **No control over their own application.** Cannot withdraw an application, accept/decline an offer, or confirm/reschedule an interview. Status is recruiter-only.
- **Job filters.** Only text search over 100 newest postings. Need location, employment type, salary range, remote, experience level, plus pagination.
- **Recommended jobs** based on profile (same match score as above).
- **Structured profile.** Experience and education are free-text strings; skills are comma-separated. Need structured entries (company, title, from/to), education list, multiple resumes, profile-completeness meter, resume parsing (AI auto-fill from PDF).
- **Profile visibility control** (open to work / hide from current employer).

### For both
- **In-app notification center.** Push exists on Android only; there is no inbox screen, no unread badge on Chat, no read receipts, no web push. Lists refresh by polling; a WebSocket/SSE channel would make chat truly instant.
- **Email notifications** for status changes and new applicants (Resend is already wired for OTP).
- **Google sign-in / phone OTP** (expected by Indian users; reduces signup drop-off).
- **Report / block user** and a **moderation queue**.
- **Admin panel** (web): user list, verify companies, remove postings, view metrics. Today moderation means editing rows in Prisma Studio by hand.
- **Onboarding screens, dark mode, Hindi localisation, accessibility pass.**

---

## 4. Gaps — Group C: Engineering & operations debt

| Area | Current | Needed |
|---|---|---|
| Tests | 65 Flutter tests (services, models, utils, toasts, profile and task screens) and 48 backend tests (`npm test`). No device-level integration tests. | Flutter integration test for apply → pipeline → chat; run the backend suite in CI against a service container. |
| State management | Singletons + `setState` + `FutureBuilder` everywhere. | Riverpod (or Bloc) with repository layer; makes testing and offline caching possible. |
| Auth tokens | 30-day JWT with no refresh or revocation; 8-char minimum password; OTPs from a secure generator; login and reset don't reveal which emails exist; per-IP rate limits. | Short access + refresh token, logout-all, per-account lockout. |
| Backend ops | `console.log`, no Docker, no health alerts, no migrations in CI. | Structured logging (pino), Dockerfile, deploy on Railway/Render/Fly, Neon/Supabase Postgres, uptime monitor, Prisma migrate in CI. |
| Abuse controls | Per-IP rate limit on `/auth` (30 per 15 min) and the data routes (300 per min). No per-user caps. | Per-user caps: postings/day per recruiter, applications/day per candidate, chat message rate. |
| Monitoring | Crashlytics wired; Sentry DSN empty; no uptime check on the backend. | Fill DSN, uptime monitor on `/health`, host budget alert. |
| Data model | Clean relational schema with cascades (`prisma/schema.prisma`). | Add `applicantsCount` on postings, structured experience/education tables. |
| Docs | Good setup docs, but README is template. | Real README with architecture diagram, run instructions, env matrix. |

---

## 5. Roadmap

### Done so far

- All data moved to PostgreSQL behind the Node API; Firebase is only the auth session and push; OTP email through Resend.
- Recruiter wishlist and shortlist stored on the server (same on every device).
- Hiring flow with assessment tasks: assign, submit, review (approve / ask for changes / reject), then schedule the interview, with chat cards and push at every step, a due-soon reminder, and a "tasks to do" list on the candidate dashboard.
- Toast notifications everywhere (including live updates on web), clear feedback on every save.
- Production hardening: secure OTPs, no account enumeration, 8-char passwords, request timeouts, offline no longer logs users out, expired sessions sign out cleanly, graceful shutdown, DB-aware `/health`, expired-OTP cleanup.
- Phase 1 and 2 shipped: applicants per job, withdraw / accept or decline offer / confirm or
  reschedule interview, multi-task with file submissions and templates, notification inbox with
  unread badges and email, interview calendar links and reminders, server-side filters, match
  score and recommendations, company profiles with verification, Google sign-in.
- 65 Flutter tests, 48 backend tests, release web build verified, `docs/DEPLOYMENT.md`.

### Phase 0 — Go live (next, a few days)
Goal: real people can install it and it keeps working without your laptop.
- Commit everything (80+ files are still uncommitted, including all of `backend/`).
- Deploy the backend (Railway/Render + Neon Postgres) with the variables in `docs/DEPLOYMENT.md`; set an uptime monitor on `/health`.
- Verify a sending domain in Resend so OTPs reach everyone, not only the account owner.
- Release keystore, final Android application id (changing it later means a new Firebase app), build the signed bundle, Play Console internal testing.
- Fill the legal placeholders, set the Sentry DSN, lock down the Cloudinary preset.

### Phase 1 — Close the hiring loop (done 14 Oct 2026)
- "Applicants" per job posting with a count badge.
- Candidate actions: withdraw an application, accept or decline an offer, confirm or request a new interview time.
- Task v2: file upload as a submission, several tasks per candidate, reusable task templates, a reminder to the recruiter about submissions waiting for review.
- Notification inbox with unread chat badge and read receipts; email for status changes (Resend is wired).
- Interview calendar invite (.ics / Google Calendar) and a reminder before the interview.

### Phase 2 — Discovery and matching (done 14 Oct 2026, except where noted)
- Server-side search and filters for candidates and jobs (skills, location, experience, CTC, notice period).
- Match score on cards, applicants and the job list; "Recommended for you".
- Company profile page, verification and a Verified badge.
- Google sign-in, optional phone OTP.
- Still open from this phase: phone OTP, job list pagination, saved-search alerts.
- Needs setup outside the code: the Google provider in Firebase, a verified
  Resend domain, and Cloudinary formats for task files.

### Phase 3 — Safety, admin, scale (weeks 7–9)
- Report and block, moderation queue, per-user write caps.
- Admin web panel (users, companies, postings, reports, metrics).
- Refresh tokens, per-account lockout, session revocation on password change.
- WebSocket/SSE instead of polling; move reminders to a scheduler so more than one server instance is safe.
- Structured logging, Docker image, backend tests running in CI.
- Prisma 7 and firebase-admin 14 upgrades (clears the remaining `npm audit` findings).

### Phase 4 — Polish and launch (weeks 10–12)
- iOS project and TestFlight.
- Structured experience and education, multiple resumes, resume parsing, profile completeness.
- Dark mode, Hindi, onboarding, accessibility pass.
- Play Store production release, App Store submission.

---

## 6. Suggested demo flow for today

1. Sign up as a recruiter → post a job.
2. Sign up as a candidate (second device/browser) → complete profile with photo + resume → browse jobs → apply.
3. Recruiter: see the application in Pipeline → shortlist → schedule interview → chat.
4. Candidate: watch status and chat update live; show push notification on the phone.
5. Show Discover swipe deck, Wishlist → Shortlist, and the Export/Delete account options.
6. Then walk through Sections 2–5 of this document as the plan.
