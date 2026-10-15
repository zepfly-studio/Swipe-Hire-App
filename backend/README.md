# Backend

Express + Prisma + PostgreSQL. This is the app's only database: accounts
(signup with OTP email verification, login, password reset), candidate
profiles, job postings, applications / hiring pipeline, chat messages,
saved jobs and the recruiter's wishlist / shortlist all live here.

Firebase is used for two things only:

- **Auth session** -- on signup/login the backend mints a Firebase custom
  token for the same user id (Admin SDK) and the app signs into Firebase
  with it, so the app's `AuthGate` has a session to listen to.
- **Push notifications** -- the backend sends FCM pushes (new applicant,
  status change, chat message) to the device token the app registers.

OTP emails go out through [Resend](https://resend.com).

## Setup

1. Copy `.env.example` to `.env`; set `DATABASE_URL` (your local Postgres
   password) and a random `JWT_SECRET`.
2. Download a Firebase Admin SDK key for the project in
   `lib/firebase_options.dart` (Firebase Console > Project settings > Service
   accounts > Generate new private key) and save it as
   `backend/firebase-service-account.json` (git-ignored).
3. `npm install`
4. `npx prisma migrate dev` (creates every table; production uses `npx prisma migrate deploy`)
5. `npm run dev`

Server runs on `http://localhost:4000`. The Android emulator reaches it via
`http://10.0.2.2:4000` (see `lib/services/api_client.dart`); a physical device
needs the dev machine's LAN IP there.

### Dev-mode OTPs

Until `RESEND_API_KEY` / `RESEND_FROM_EMAIL` are set, every OTP is returned
in the API response (and logged to the console) and the app shows it on the
verify screen. See `docs/signup-otp-setup.md`.

## Endpoints

All routes except `/auth/*` and `/health` need `Authorization: Bearer <jwt>`.
Dates are ISO-8601 strings. Lists come back wrapped in an object.

### Auth

- `POST /auth/otp/send` `{ email }` -> `{ sent, otp? }`
- `POST /auth/otp/verify` `{ email, otp }`
- `POST /auth/signup` `{ name, email, password, role, company }` -- role is
  `"candidate"` or `"recruiter"`; needs a verified OTP for that email ->
  `{ token, firebaseToken, user }`
- `POST /auth/login` `{ email, password }` -> `{ token, firebaseToken, user }`
- `POST /auth/google` `{ idToken, role? }` -- `idToken` is a Firebase ID token
  from a Google sign-in. Finds the account by verified email, or creates one;
  a new account without `role` gets `409 { needsRole: true }`. Returns the same
  session as login. Needs the Google provider enabled in Firebase.
- `POST /auth/reauth` `{ password }` -> `{ firebaseToken }`
- `POST /auth/password/forgot` `{ email }` -> `{ sent, otp? }`
- `POST /auth/password/reset` `{ email, otp, newPassword }`

### Account

- `GET /users/me`
- `PATCH /users/me` `{ name, company, designation, phone, profileComplete, emailNotifications }`
- `PUT /users/me/fcm-token` `{ token }`
- `GET /users/me/export` -- everything the account owns (for "Export my data")
- `GET /users/candidates/lookup?email=` (recruiter) -> candidate's profile
- `DELETE /users/me` -- cascades to everything the account owns, then
  deletes the Firebase Auth record

### Candidates

- `GET /candidates?cursor=&limit=` (recruiter) -> `{ candidates, nextCursor, hasMore }`
  -- the swipe deck; excludes candidates this recruiter already swiped on and
  anyone with `openToWork` off. Order: profiles active in the last 15 days
  first, then best match (+10 for sign-ups under 7 days old), then newest.
  Filters, all optional: `q`, `skills` (comma separated, any match), `location`,
  `expMin`, `expMax` (years), `ctcMin`, `ctcMax` (LPA), `noticeMax` (days),
  `jobId` (score against that posting), `sort=newest` (plain newest first).
  Each candidate carries `matchScore`, `matchJobTitle` and `matchReasons`.
  Cards never include age, gender, phone or email.
- `GET /candidates/:id` (recruiter)
- `GET /candidates/me/profile` / `PUT /candidates/me/profile` (candidate) --
  the PUT validates and answers `400 { error, field }`; required: `desiredRole`,
  `phone`, `age` (16-75), `gender`, `location`, `qualification`, `degree`,
  `skills` (1-30), `experience`, `expectedSalaryLpa` (values >= 1000 are
  rupees and divided by 100000). Optional: `college`, `graduationYear`,
  `currentPost`, `currentCompany`, `currentSalaryLpa`, `expectedSalaryMaxLpa`,
  `salaryNegotiable`, `workModes`, `jobTypes`, `noticePeriod`, `about`, media urls.
- `POST /candidates/me/resume/autofill` (candidate; multipart `resume`, PDF
  up to 5 MB) -> `{ fields }` with only what was found (`phone`, `skills`,
  `degree`, `qualification`, `graduationYear`, `college`, `desiredRole`,
  `location`, `experienceYears`, `currentCompany`, `currentPost`). Nothing is
  stored; a scanned PDF gives `{ fields: {} }`.
- `POST /candidates/me/active` (candidate) -- "I'm still looking": `activeAt = now` -> profile
- `PUT /candidates/me/preferences` (candidate)
  `{ openToWork?, workModes?, jobTypes?, preferredLocations? }` -> profile
- `GET /candidates/me/stats` (candidate) -> `{ viewedCount, wishlistedCount,
  shortlistedCount, hiddenCount, shortlistedBy: [...] }`; a recruiter who only
  shortlisted counts in `hiddenCount` and is named in `shortlistedBy` only once
  they have an opportunity (contact) with the candidate.

### Taxonomy

- `GET /taxonomy` (any signed-in user) -> `{ roles, skills, degrees, cities,
  states, locations }`; source: `src/lib/taxonomy.js`.

### Jobs

- `GET /jobs?limit=` -> `{ jobs }` (open postings, newest first). Filters, all
  optional: `q`, `location`, `type`, `salaryMin`, `skills`, `remote=1`,
  `experience` (the candidate's years; hides roles that ask for more),
  `sort=match`. A candidate gets `matchScore` and `matchReasons` on each job.
- `GET /jobs/recommended` (candidate) -> `{ jobs }` -- best fits, 40+ score,
  excluding roles already applied to
- `GET /jobs/mine` (recruiter) -> `{ jobs }`, each with `applicantsCount`
- `GET /jobs/:id/applicants` (recruiter, owner) -> `{ job, applicants }` -- each
  `{ opportunity, candidate }`, best match first
- `POST /jobs` (recruiter), `PUT /jobs/:id`, `PATCH /jobs/:id` `{ isOpen }`
- `GET /jobs/:id`
- `GET /jobs/:id/application` (candidate) -> `{ applied }`
- `POST /jobs/:id/apply` (candidate) -> the new opportunity; pushes the recruiter
- `GET /jobs/saved` (candidate) -> `{ ids, jobs }`; `PUT` / `DELETE /jobs/saved/:id`

### Opportunities (pipeline / applications)

- `GET /opportunities` -> `{ opportunities }` -- the recruiter's pipeline or
  the candidate's hiring activity, depending on who's asking
- `GET /opportunities/with/:candidateId` (recruiter) -> `{ opportunity | null }`
- `POST /opportunities` (recruiter) `{ candidateUid, role, status, interview*, offer* }`
- `PUT /opportunities/:id` (recruiter) -- status change pushes the candidate;
  scheduling or rescheduling an interview also posts an `interview` message
  (date in IST, mode, link) into the chat thread
- `POST /opportunities/:id/withdraw` (candidate) `{ reason? }` -- status becomes
  `withdrawn`; tells the recruiter
- `POST /opportunities/:id/offer-response` (candidate) `{ decision: "accepted" | "declined" }`
- `POST /opportunities/:id/interview-response` (candidate)
  `{ decision: "confirm" | "reschedule", note }` (note needed to reschedule)
- `GET /opportunities/:id/messages?after=` -> `{ messages }` (both parties);
  marks the other side's messages read
- `POST /opportunities/:id/messages` `{ text }` -- pushes the other party

### Assessment tasks (shortlist -> task -> review -> interview)

Statuses run `shortlisted -> taskAssigned -> taskSubmitted -> interviewScheduled`.
`taskAssigned` / `taskSubmitted` are set only by the task routes below. Every
step also posts a `task` message into the chat thread and pushes the other side.

- `GET /opportunities/:id/tasks` -> `{ tasks }` (both parties)
- `POST /opportunities/:id/tasks` (recruiter)
  `{ title, description, link, dueDate, saveAsTemplate }` -- up to 5 open
  tasks per candidate; only before the interview stage
- A background job (`src/jobs/taskReminders.js`, every 10 minutes) sends, once
  each: a due-within-24-hours reminder to the candidate, a "waiting for review"
  reminder to the recruiter after 24 hours, and interview reminders 24 hours
  and 1 hour before to both sides (`DISABLE_TASK_REMINDERS=true` turns it off)
- `POST /opportunities/:id/tasks/:taskId/submit` (candidate)
  `{ answer, link, fileUrl, fileName }` -- at least one of them; can be re-sent
  until reviewed; link must be http(s); `fileUrl` must be a Cloudinary URL
- `POST /opportunities/:id/tasks/:taskId/review` (recruiter)
  `{ decision: "approved" | "changes" | "rejected", feedback }` -- `changes`
  needs feedback and returns the task to the candidate; `rejected` marks the
  candidate not selected; `approved` unlocks scheduling the interview

### Notifications and templates

Every notification is an inbox row, a push and (unless the user turned email
off) an email. Chat messages are push-only.

- `GET /notifications` -> `{ notifications }` (newest first)
- `GET /notifications/summary` -> `{ unreadNotifications, unreadMessages }`
- `POST /notifications/read` `{ ids? }` -- all unread when `ids` is omitted
- `GET /templates`, `POST /templates` `{ title, description, link }`,
  `DELETE /templates/:id` (recruiter) -- reusable task templates

### Company (recruiter)

- `GET /company/me`, `PUT /company/me` `{ name, website, about, size, industry, location, logoUrl }`
  -- the page is **verified automatically** when the website domain matches the
  recruiter's work email domain (free mail domains never count)
- `POST /company/me/verification-request` -- asks for a manual review
- `GET /company/:id` -> the public company page with its open roles

### Swipes (recruiter wishlist / shortlist)

- `GET /swipes` -> `{ wishlist: [candidate], shortlist: [candidate], rejectedIds }`
- `PUT /swipes/:candidateId` `{ state: "wishlist" | "shortlist" | "rejected" }`
- `DELETE /swipes/:candidateId` -- undo

## Data model

See `prisma/schema.prisma`: `users`, `otp_codes`, `candidate_profiles`,
`job_postings`, `opportunities`, `tasks`, `task_templates`, `messages`,
`notifications`, `companies`, `saved_jobs`, `swipes`. Every
child table cascades on user delete. Browse it with `npm run prisma:studio`.
