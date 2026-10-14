# SwipeHire

A two-sided hiring app. Recruiters swipe through real candidate profiles,
build a wishlist and shortlist, post jobs and run a hiring pipeline
(shortlist → interview → offer → hired) with in-app chat. Candidates build a
profile (photo, PDF resume, intro video), browse and apply to jobs, save
roles, and track every application live.

Highlights: match score and "Recommended for you", server-side filters,
applicants per job, multi-task assessments with file submissions and
templates, offer and interview responses, notification inbox with email,
calendar links and reminders, verified company pages, Google sign-in.

## Architecture

| Layer | Tech | Notes |
|---|---|---|
| App | Flutter (Android, web) | `lib/` -- screens, models, services |
| API + database | Node (Express) + Prisma + **PostgreSQL** | `backend/` -- every piece of app data lives here |
| Auth session | Firebase Auth (custom token) | the backend owns accounts and passwords; Firebase only holds the session the app listens to |
| Push | Firebase Cloud Messaging | sent by the backend on new applicant, status change, chat message |
| Email | Resend | signup OTP, password reset, and notification emails (status changes, interview reminders) |
| Media | Cloudinary (unsigned preset) | photos, resumes, intro videos |
| In-app notifications | `sonner_toast` via `lib/widgets/app_toast.dart` | every message, error and live update is a toast; call `AppToast.success/error/info/warning/action/notification` from anywhere |
| Crash / analytics | Crashlytics (mobile), Sentry (web), Firebase Analytics | |

The app talks to the backend only through `lib/services/api_client.dart`.
Lists and chat refresh by polling the API (and immediately after any write),
so the UI feels live without a realtime database.

## Run it locally

1. **Backend** -- follow `backend/README.md` (Postgres, `.env`, Firebase
   Admin key, `npx prisma migrate dev`, `npm run dev`). It listens on
   `http://localhost:4000`.
2. **App** -- `flutter pub get`, then `flutter run`. Debug builds reach the
   local backend automatically (Android emulator via `10.0.2.2`). A physical
   device or a release build needs
   `--dart-define=API_BASE_URL=http://<your-ip-or-host>:4000`.
3. Without a Resend key the OTP is shown on screen (dev mode).

## Tests

```bash
flutter test               # Flutter unit and widget tests
cd backend && npm test     # API tests against a development database
```

See `docs/testing.md`. CI (`.github/workflows/ci.yml`) runs analyze + tests
and checks the backend on every push.

## Docs

- `docs/DEPLOYMENT.md` -- going live: environment, release builds, checklist
- `docs/PRODUCTION_ROADMAP.md` -- current status, gaps, 12-week plan
- `docs/signup-otp-setup.md` -- Resend email setup
- `docs/android-release-signing.md` -- release keystore
- `docs/cloudinary-setup.md`, `docs/sentry-setup.md`, `docs/app-check-setup.md`
- `docs/admin-moderation.md`, `docs/cost-controls.md`, `docs/legal-placeholders.md`
