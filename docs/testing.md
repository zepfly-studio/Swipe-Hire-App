# Running the test suite

## Flutter unit/widget tests

```bash
flutter test
```

Covers:
- `test/services/auth_service_test.dart` — signup, sign-in, recruiter
  profile completion and `deleteAccount()`, against a fake backend
  (`test/helpers/fake_api.dart`) and a mocked Firebase Auth
  (`firebase_auth_mocks`) so no real backend or Firebase project is touched.
- `test/services/job_posting_service_test.dart` — create/list postings,
  apply/hasApplied, save/unsave jobs, open-postings filtering.
- `test/screens/signup_screen_test.dart` — the Terms & Privacy consent
  checkbox gate, and that both legal links navigate correctly.

`AuthService.test(...)` / `JobPostingService.test(...)` are
`@visibleForTesting` factories that accept an injected `ApiClient`.
`FakeApi` is a tiny in-memory router over the same paths and JSON shapes
`backend/src/routes/*.js` use — when you add a route the service calls, add
the matching case there.

## Backend

```bash
cd backend
npm test
```

`backend/test/api.test.js` drives the real Express app over HTTP against the
database in `DATABASE_URL` (use a **development** database). Firebase and
Resend are replaced with in-memory fakes, so nothing leaves the machine, and
every account it creates is named `e2e.*` and removed afterwards. It covers
signup and OTP, login and password reset, profile validation, the recruiter
deck and swipe funnel, jobs and applications, the task flow (assign, submit,
review, interview message), chat permissions, the reminder and cleanup
jobs, and account deletion.

CI also syntax-checks every backend file and validates the Prisma schema on
each push.
