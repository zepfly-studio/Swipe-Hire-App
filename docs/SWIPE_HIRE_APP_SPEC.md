# Swipe Hire: complete product spec for the Android app

This document describes everything the Swipe Hire **website** does today, so the **Android app** can offer the same product. It was written from the website's source code (React client + Express/MongoDB backend), not from memory, and it quotes exact field names, limits, API paths and on-screen texts.

**Goal:** the website and the Android app both work, side by side, on the **same backend and the same database**. A user who signs up in the app can log in on the website and see the same data, and the other way round.

## How to use this document (instructions for the implementing agent)

1. **Do not build a new backend.** The app talks to the existing API described in Part A. Every endpoint, request field and response field is listed there.
2. **Keep the website working.** If the app needs a backend change (for example a new endpoint or push notifications), make it **additive** (new endpoints or optional fields) so the website keeps working, and note it for the web team.
3. **Match the business rules exactly**: validation limits, error messages, credit rules, who can see what. The server enforces them anyway, but the app must show the same messages under the same fields (the API returns `{message, field?}` on errors).
4. **Screens**: Part B (candidate + shared screens) and Part C (company + admin screens) describe every web page section by section. Rebuild them as native screens with the same content and flow. Desktop-only details (hover, keyboard shortcuts, 2-column layouts) can be adapted to touch.
5. **Option lists** (job roles, skills, degrees, cities, states) come from `shared/taxonomy.js` in the website repo. Copy them into the app (or serve them from an endpoint) so suggestions match the website.
6. **Design**: the colours quoted in Parts B and C are the website's current theme. The client has asked for a **more professional look: deep green `#1F4D42` with white / off-white `#F0F0EE`** (like LinkedIn, Naukri, Indeed) and **no cartoon illustrations**. That redesign is pending on the website too. Keep all colours in one central theme file in the app so they can be changed in one place, and prefer clean UI, line icons and real product visuals over cartoon art.

## Production addresses

| What | URL |
|---|---|
| Website (Vercel) | `https://swipe-hire-sand.vercel.app` |
| Backend API (Render) | `https://swipe-hire-z1th.onrender.com/api` |
| Uploaded files | `https://swipe-hire-z1th.onrender.com/uploads/...` (signed links, not under `/api`) |
| Health check | `GET https://swipe-hire-z1th.onrender.com/api/health` → `{ok:true}` |

**Which base URL the app should use:** call the API **through the website's address**, exactly like the website does: `https://swipe-hire-sand.vercel.app/api/...` and `https://swipe-hire-sand.vercel.app/uploads/...` (Vercel forwards both to Render). Reason: the live server is configured with `TRUST_PROXY=2` for the Vercel proxy, so requests that skip Vercel and hit Render directly would make the per-IP rate limiting unreliable. Keep the base URL in one config value so it can be switched to a custom domain later.

The Render free plan sleeps when idle, so the first request after a while can take 30–60 seconds: show a loading state and use generous timeouts (60 s).

---

## 1. Summary

### 1.1 Who uses Swipe Hire

| User type | What they do |
|---|---|
| **Candidate** (job seeker) | Creates a profile (details, skills, salary, resume PDF, 15-second intro video). Companies discover them. Gets shortlisted, chats with companies, does take-home tasks, picks interview times. Free. |
| **Company owner** (recruiter account that created the company) | Sets up the company and the jobs it is hiring for, swipes through candidate cards (right = shortlist, left = pass), manages the shortlisted pipeline, chats, sends tasks, schedules interviews, buys swipe credits, verifies the company, invites team members. |
| **Recruiter** (team member invited by the owner) | Same as the owner inside the same company (shares jobs, swipes, pipeline and chats), but cannot invite or remove people. |
| **Admin** (Swipe Hire staff, by email list on the server) | Reviews companies' GSTIN verification requests. |

### 1.2 All screens

**Public / shared**

| Web route | Screen | Who |
|---|---|---|
| `/` | Landing page (marketing, pricing, FAQ) | Visitors (signed-in users are sent to their home) |
| `/auth` (`?mode=login`, `?role=company`) | Sign up / Log in | Guests |
| `/verify-email` | Enter the 6-digit email code | Signed-in users whose email is not verified |
| `/join?token=` | Accept a team invite (recruiter sign-up) | Guests |
| `/messages` (`?with=<userId>`) | Conversations and chat | Candidates and companies |
| `/interviews` | Interview invites and schedule | Candidates and companies |
| `/tasks` | Take-home tasks | Candidates and companies |
| `/settings` | Account settings (photo, name, password, log out everywhere) | Everyone |
| `*` | Not found | Everyone |
| (overlay) | Offline screen: "Can't reach Swipe Hire" | Everyone |
| (overlay) | Notifications panel (bell) | Everyone signed in |

**Candidate**

| Web route | Screen |
|---|---|
| `/candidate/onboarding` (and `?edit`) | 4-step profile setup / edit: 1 Details, 2 Work & skills, 3 Resume, 4 Intro video, then "You're live!" |
| `/candidate` | Candidate home: stats, 15-day "I'm active" ring, profile strength, companies that shortlisted me, open-to-work switch, job preferences, my profile card |
| (modal) | Company details (for companies that contacted the candidate) |
| (modal) | Resume viewer |

**Company**

| Web route | Screen |
|---|---|
| `/company/onboarding` (and `?edit`) | 2-step setup: About your company, Who are you hiring (first job), then "You're all set!" |
| `/company/swipe` | Main swipe screen: job selector, filters, saved searches, candidate card stack, undo, wishlist, swipe counter, paywall |
| `/company/wishlist` | Saved (wishlisted) candidates |
| `/company/shortlisted` | Shortlisted pipeline: stages, notes, select many, group message, schedule interview, send task |
| `/company/jobs` | Jobs the company is hiring for (create, edit, close) |
| `/company/plans` | Buy swipe credits (Razorpay, or demo mode) |
| `/company/profile` | Company profile (logo, details, contact & links) |
| `/company/team` | Team members and invites |
| `/company/verify` | Company verification (work email code, or GSTIN review) |
| `/admin` | Admin: GSTIN verification queue (admins only) |

### 1.3 What we ask the candidate

| Step | Details collected | Required |
|---|---|---|
| Sign up | Full name, email, password (min 6) | All |
| Email check | 6-digit code sent to the email | Yes |
| 1. Details | Phone number, age (16–75), gender (Male / Female / Other), current city, highest qualification (10th, 12th, Diploma, Graduate, Post Graduate, PhD), degree / course | Yes |
| | College / university, passing year | Optional |
| 2. Work & skills | Role looking for (job title), skills (at least 1, max 30), experience in years (0 = fresher), minimum expected salary (LPA) | Yes |
| | Maximum expected salary, "salary is negotiable" switch, notice period (Immediate / 15 / 30 / 60 / 90 days), current or last company, current or last post, current salary, preferred work mode (On-site / Hybrid / Remote), job type (Full-time / Part-time / Internship / Contract), about me (max 600 chars) | Optional |
| 3. Resume | One PDF, max 5 MB (can also be uploaded first to auto-fill steps 1–2) | Yes |
| 4. Intro video | 5–15 seconds, recorded in the app (front camera) or uploaded; MP4 / WebM / MOV, max 40 MB | Yes |
| Later (home screen) | Open to work on/off, preferred cities (max 10), work modes, job types | Optional |
| Settings | Profile photo (JPG / PNG / WebP, max 3 MB), name | Optional |

Privacy rules: **age and gender are never shown to companies**. **Phone and email are shared only with companies that shortlist the candidate.**

### 1.4 What we ask the company

| Where | Details collected | Required |
|---|---|---|
| Sign up | Your name, work email, password (min 6) | All |
| Email check | 6-digit code | Yes |
| Onboarding step 1 "About your company" | Company name, location (city) | Yes |
| | Industry (IT / Software, E-commerce, Finance, Healthcare, Education, Manufacturing, Marketing / Media, Retail, Real Estate, Other), company size (1–10, 11–50, 51–200, 201–1000, 1000+), website, about the company (max 600) | Optional |
| Onboarding step 2 "Who are you hiring?" (creates the first job) | Role you are hiring for, skills you need (at least 1), max salary you can offer (LPA) | Yes |
| | Min / max experience (years), min salary, job location (defaults to company city), work mode (On-site / Hybrid / Remote) | Optional |
| Company profile page (later) | Logo (max 3 MB), founded year, description (max 1500), LinkedIn page, contact number, contact email, office address (used for in-person interviews) | Optional |
| Each extra job | Title, skills, experience range, salary range, job location, work mode, job type, description | See Part C, Jobs |
| Verification | Either a 6-digit code sent to a work email on the company website's domain, or a 15-character GSTIN reviewed by the Swipe Hire team | Optional (gives a verified badge) |
| Team | Email of each recruiter to invite (team of up to 10) | Optional |

### 1.5 Feature list

**Accounts and security**
- Email + password sign-up and login; 6-digit email verification code (expires in 15 minutes, 60-second resend cooldown, daily limits).
- Session token for the app (`Authorization: Bearer`, see Part A); "Log out of all devices"; change password (logs out other devices).
- Team accounts: owner invites recruiters by email (7-day invite link), removes them.
- Light / dark theme on the website (the app should follow the system theme or offer a switch).

**Candidate features**
- 4-step onboarding with **resume auto-fill** (the server reads the PDF and fills phone, skills, degree, qualification, college, passing year, headline, city, experience, current company and post).
- **15-second intro video** recorder with 3-2-1 countdown, 5-second minimum, auto-stop at 15 seconds, retake; or upload.
- Home dashboard: profile views, times wishlisted, times shortlisted.
- **15-day "I'm active" ring**: candidates who have not confirmed they are still looking for 15 days drop lower in company feeds; tapping "I'm active" puts them back on top.
- **Profile strength** score (0–100) with a checklist of what to add next.
- **Open to work** switch (hides the profile from companies when off).
- Job preferences: preferred cities, work modes, job types.
- See companies that shortlisted me (a company stays anonymous until it messages, sends a task or sends an interview invite), with company details.
- Chat with companies that contacted me; submit take-home tasks (live link + GitHub repo + note) before the deadline; pick one of up to 3 interview times, join video call (Jitsi link), add to calendar, cancel.

**Company features**
- Jobs ("Hiring for") with required skills, experience and salary range; candidates are ranked by **match score** for the selected job.
- **Swipe feed**: candidate card with name, photo, headline, match %, location, experience, expected salary, skills, resume (PDF) and intro video; right = shortlist, left = pass; undo the last swipe; wishlist (free, does not use a credit).
- **Filters**: city (also matches preferred cities), min / max experience, budget (max LPA; also includes candidates open to negotiation), notice period, must-have skills. **Saved searches with alerts** when new matching candidates join.
- **Swipe credits**: each swipe (left or right) uses one credit; free credits on sign-up (5 by default); paid pack Starter ₹399 for 150 swipes via Razorpay (demo mode when Razorpay keys are missing). Out of swipes → paywall.
- **Shortlisted pipeline**: stages Shortlisted → Contacted → Task sent → Interview → Hired / Rejected; private notes; candidate contact details (phone, email) revealed after shortlisting; select many candidates and send a **group message**.
- **Tasks**: send a take-home task with brief, reference link and deadline (1 hour to 30 days); see submissions; change the deadline; cancel.
- **Interviews**: offer 1–3 time slots (video / phone / in person, 15–60 minutes); video calls get an automatic Jitsi link; cancel with a reason.
- **Chat** with shortlisted candidates (text only, max 2000 characters, read ticks).
- **Company verification** (blue badge): instant work-email code, or GSTIN reviewed by admin.
- Company profile visible to candidates the company has contacted.
- Team of up to 10 people sharing everything.

**Shared**
- Notifications (shortlisted, new message, interview, task, hired, verified, saved-search alert) in a bell panel; most are also emailed.
- Polling instead of websockets: unread messages every 15 s, notifications every 30 s, conversation list every 10 s, open chat every 4 s, interviews and tasks every 30 s.

**Not in the product today** (the app does not need them unless the client asks): deleting an account, chat attachments, typing indicators, websockets, push notifications, in-app video calling (calls open the Jitsi link), job applications by candidates (candidates do not browse or apply to jobs; companies find candidates).

---

## 2. Android implementation notes

- **Authentication**: send the header `X-Auth-Mode: token` on `POST /auth/register`, `POST /auth/login`, `POST /auth/accept-invite` and `PUT /account/password`. The JSON response then includes `token` (a JWT valid for 30 days). Store it securely (EncryptedSharedPreferences / Keystore) and send `Authorization: Bearer <token>` on every request. With a Bearer token the CSRF header check does not apply. On app start call `GET /auth/me`: 401 means logged out; network or 5xx errors mean offline (show the offline screen with "Try again"). After a password change, replace the stored token with the new one from the response. "Log out of all devices" invalidates every token.
- **Email codes in testing**: while the server has `SHOW_EMAIL_CODE=true` (testing only), `POST /auth/email/send` also returns `devCode`; show it on the verify screen like the website does ("Testing mode: your code is 123456"). Hide this when `devCode` is absent.
- **Errors**: show `message` from the error body; if `field` is present, show it under that input (and jump to the onboarding step that has that field).
- **File links** (resume, video, photos, logos) are signed and expire after a few hours. Do not cache the URLs for long; reload the profile / list to get fresh ones. Relative `/uploads/...` paths must be prefixed with the backend origin.
- **Uploads** are `multipart/form-data`. Field names: `resume` (PDF, 5 MB), `video` (MP4 / WebM / MOV, 40 MB), `image` (avatar / logo, JPG / PNG / WebP, 3 MB). The server checks the real file type (magic bytes), not just the extension. Show upload progress.
- **Video**: record with the front camera (CameraX), 5–15 seconds, MP4 (H.264 + AAC) at about 720×960; keep it under 40 MB.
- **Resume**: render PDFs natively (PdfRenderer after downloading) for the resume viewer and thumbnails.
- **Polling**: use the same intervals as the website while a screen is visible; stop when the app is in the background. (Push notifications would need a new backend feature: device-token registration and sending through Firebase. Add it only as an additive change.)
- **Payments**: use the Razorpay Android SDK with the same flow: `POST /payment/order {planId}` → open checkout with `orderId`, `amount`, `keyId` → `POST /payment/verify {orderId, paymentId, signature}`. When the order response has `mode: 'demo'`, skip checkout and call verify with just `{orderId}` (testing only).
- **Interviews**: open `meetingLink` (Jitsi) in the browser or Jitsi app; "Add to calendar" can use an Android calendar insert intent.
- **Deep links**: support `https://swipe-hire-sand.vercel.app/join?token=...` (team invite) and notification links such as `/messages?with=<id>`, `/interviews`, `/tasks`, `/candidate`, `/company/shortlisted`; map each web route to the matching app screen.
- **Swipe gestures**: drag the card right to shortlist and left to pass, with buttons for the same actions plus undo and wishlist. Double-tap the card to open the resume.
- **Lists for suggestions**: copy `ROLES`, `SKILLS`, `DEGREES`, `CITIES`, `STATES` and `LOCATIONS` from `shared/taxonomy.js`, and reproduce the ranking described in Part B ("Shared input components").

---

## Contents

- **Part A. Backend API and data reference**: conventions, authentication, every endpoint, database models, business rules (credits, match score, feed ranking, filters, contact visibility, verification, pipeline, chat, resume parsing, uploads, notifications), option lists, config.
- **Part B. Candidate and shared screens**: global behaviour, landing, auth, verify email, join, candidate onboarding, candidate home, messages, interviews, tasks, settings.
- **Part C. Company and admin screens**: company onboarding, swipe, wishlist, shortlisted pipeline, jobs, plans and payment, company profile, team, verification, company view of messages / interviews / tasks, admin.


---

# Part A. Backend API and data reference

Source: every file in `server/src` (index, config, middleware, models, routes, utils) and `shared/taxonomy.js`. Secret values are never included; only variable names.

---

## 0. Global conventions

**Base URLs**
- Direct to the backend: `https://swipe-hire-z1th.onrender.com/api`. Uploaded files are at `https://swipe-hire-z1th.onrender.com/uploads/...`. They are **not** under `/api`.
- Through Vercel: `https://swipe-hire-sand.vercel.app/api/*` and `/uploads/*`. `client/vercel.json` rewrites both to the Render backend.
- The web client uses `baseURL: VITE_API_URL || '/api'`, `withCredentials: true` and the header `X-Requested-With: XMLHttpRequest`.

**Global middleware order** (`index.js`):
1. `trust proxy` = `Number(TRUST_PROXY) || 1`. The comment says use 1 for Render alone and 2 when the Vercel proxy is in front.
2. `x-powered-by` is disabled.
3. Security headers on every response: `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: strict-origin-when-cross-origin`, `Cross-Origin-Opener-Policy: same-origin`. In production it also sends HSTS `max-age=31536000; includeSubDomains`.
4. CORS: `cors({ origin: CLIENT_URL list, credentials: true })`. This does not matter for a native app; it only matters for a WebView.
5. Global rate limit on `/api`: **600 requests/min per IP**, with `draft-7` RateLimit headers. When exceeded: 429 `{message:"Too many requests, please slow down and try again in a minute"}`.
6. `POST /api/payment/webhook` takes the raw body (1 MB). It is registered before the JSON parser.
7. `express.json({limit:'1mb'})`. All request bodies are JSON except multipart uploads.
8. `/uploads`: signed-URL check, then local static files, then a Cloudinary stream.
9. `GET /api/health` returns `{ok:true}`. This route needs no auth.
10. Unknown routes return 404 `{message:"Not found"}`.

**Error format.** Every error is JSON: `{ message: string, ...extra }`. `extra` can include:
- `field`: the form field to highlight, e.g. `"phone"`, `"code"`, `"dueAt"`.
- `code`: a machine-readable code. The codes are `EMAIL_NOT_VERIFIED`, `NO_JOB`, `NO_SWIPES`, `SALARY_MISMATCH`.

The error handler maps errors like this:
- `HttpError` uses its own status.
- Multer `LIMIT_FILE_SIZE` returns 400 "File is too large". Other multer errors return 400 with multer's message.
- Mongoose validation/cast errors return 400 "Some details are invalid, please check and try again".
- A duplicate key (11000) returns 409 "This already exists".
- A bad JSON body returns 400 "Invalid request body".
- Anything else returns 500 "Something went wrong, please try again".

**Units and IDs**
- Salaries are in **LPA** (lakh per annum). The `salary()` parser treats any value ≥ 1000 as a full rupee amount and divides it by 100000. It rounds to 2 decimals, and an LPA above 1000 is rejected.
- IDs are Mongo ObjectId strings.
- A "company id" is always the **owner user's `_id`**. Team members' data hangs off the owner's id.

---

## 1. Auth, session and security

### 1.1 Tokens and cookies (`middleware/auth.js`)
- The JWT is HS256, signed with `JWT_SECRET`. Payload: `{ sub: userId, role, v: tokenVersion }`. Expiry: **30d**.
- Cookie name: **`sh_session`**. It is `httpOnly`, has `path=/api`, and `maxAge` 30 days. `sameSite` is `COOKIE_SAMESITE` (`strict|lax|none`, default `lax`). It is `secure` in production or whenever SameSite is `none`.
- `startSession` always sets the cookie. If the request carries **`X-Auth-Mode: token`**, the JSON response also includes `token`.
- `auth` middleware:
  - It reads `Authorization: Bearer <token>` first, then the `sh_session` cookie.
  - No token: 401 "Please log in to continue".
  - **CSRF guard:** cookie-authenticated, non-GET/HEAD/OPTIONS requests must send `X-Requested-With: XMLHttpRequest`, or they get 403 "Request blocked, please refresh the page and try again". **Bearer requests skip this check.**
  - Invalid or expired JWT: 401 "Your session has expired, please log in again".
  - It loads the user on every request. A deleted user gets 401 "Your account no longer exists, please log in again". A `tokenVersion` mismatch gets 401 "Your session has expired...".
  - It sets `req.user = { id, role, companyId (company only: owner id), isOwner (company && no companyId), emailVerified }`.
- `requireVerified`: 403 `{message:"Please verify your email first", code:"EMAIL_NOT_VERIFIED"}`.
- `requireRole(role)`: 403 "You do not have access to this".
- `requireOwner`: 403 "Only the account owner can do this".

**How the Android app should authenticate**
1. Send `X-Auth-Mode: token` on `POST /api/auth/register`, `/login` and `/accept-invite`. That header also satisfies the `fromApp` login-CSRF check, so `X-Requested-With` is not needed there. Read `token` from the response and store it securely.
2. Send `Authorization: Bearer <token>` on every request after that. Ignore the `Set-Cookie`.
3. `PUT /api/account/password` returns a fresh token only if `X-Auth-Mode: token` is sent on that request too. The old token stops working because `tokenVersion` is bumped. **Send that header on the password change.**
4. `POST /api/auth/logout` only clears the cookie. A Bearer token stays valid until it expires. Mobile logout means dropping the token locally. `POST /api/auth/logout-all` bumps `tokenVersion`, which invalidates every session on every device, including web.
5. A 401 from anywhere means re-login.
6. Rate-limit caveat: if `TRUST_PROXY=2` is set on Render (for the Vercel proxy), direct hits from the app make rate limiting trust one more client-supplied `X-Forwarded-For` hop. The simplest consistent choice is to call through the same path the web uses, or keep `TRUST_PROXY` matched to the path the app uses.

### 1.2 Rate limits
| Scope | Limit | Key |
|---|---|---|
| All `/api` | 600 / 60 s | IP |
| `/auth/register`, `/auth/login`, `/auth/accept-invite` | 30 **failed** (status ≥ 400) per 15 min (`skipSuccessfulRequests`); message "Too many attempts, please try again in a few minutes" | IP |
| `POST /chats/:otherId` | 30 / 60 s; "You are sending messages too fast, please slow down" | user id |
| `POST /chats/bulk` | 20 / hour; "You have sent a lot of group messages, please try again in an hour" | user id |

### 1.3 Password rules
- Minimum 6 characters, string type. There is no maximum or complexity rule.
- Hashed with bcryptjs, cost 10.
- The same rule applies to register, accept-invite and change password.

### 1.4 Account email verification (`routes/auth.js`)
- New registrations have `emailVerified: false`. Accounts created by accepting an invite are verified automatically. A migration marks pre-existing users as verified.
- The code is **6 digits**: `crypto.randomInt(100000, 1000000)`. It is stored as a sha256 hash.
- TTL: **15 min**.
- Cooldown: **60 s**. A send within the cooldown, while the code is still valid, reuses the existing code and returns the remaining `retryIn`.
- Daily window (24 h from `windowStart`): **max 8 sends** and **max 15 failed attempts**. Exceeding either returns 429 "Too many codes requested today. Please try again tomorrow."
- Per code: **5 wrong tries**. After that, 429 "Too many wrong attempts. Tap \"Send a new code\"." with `field:'code'`.
- `devCode` / showing the code on screen happens when `showCodeOnScreen() = (!mailEnabled && !isProd) || SHOW_EMAIL_CODE === 'true'`. In that case the plain code is stored in `emailOtp.dev` and returned as `devCode`. The cooldown reuse path returns `prev.dev`. If sending the email fails in this mode, the response still returns 200 with `devCode`.
- If the email fails outside this mode: `sentAt` is unset, so the next tap retries immediately, and the response is 502 "We couldn't send the email right now. Please try again in a minute."
- Email subject: "`<code>` is your Swipe Hire code".

### 1.5 Response shape for `session(user)`
Used by login, register, `/me`, email verify, accept-invite and the account routes:
```
{ token?: string,               // only with X-Auth-Mode: token (login/register/accept-invite)
  user: { id, name, email, role: 'candidate'|'company', emailVerified: bool,
          isAdmin: bool,        // email in ADMIN_EMAILS and verified
          avatarUrl?: signed url, phone?,
          // company only:
          companyId: ownerId, isOwner: bool },
  profile: CandidateProfile | CompanyProfile document (lean, file URLs signed; for team members, the OWNER's CompanyProfile) }
```
`profile` is the raw Mongo document: `_id`, `user`, `createdAt`, `updatedAt`, `__v`, plus all non-hidden fields. CompanyProfile `emailOtp` and `creditedOrders` are never included. A brand-new candidate profile is `{user, step:0, openToWork:true, activeAt, skills:[], preferredLocations:[], workModes:[], jobTypes:[], salaryNegotiable:false, ...}`. A new company profile is `{completed:false, swipesLeft:FREE_SWIPES, swipesPurchased:0, workMode:'onsite', verification:{status:'none'}, requiredSkills:[]...}`.

### 1.6 Team invites and join flow
- The owner sends an invite with `POST /api/team/invite {email}`. The emailed link is `${CLIENT_URL[0]}/join?token=<24-byte base64url token>`. It is valid for **7 days**. Only the sha256 hash is stored.
- The team limit is **10**, counting members plus pending invites.
- A new invite to the same email replaces the old one.
- Invites fail with 409 if the email already has an account.
- In dev without mail the response includes `devLink`.
- Joining:
  1. `GET /api/auth/invite/:token` → `{email, companyName}`. Invalid or expired: 404 "This invite link is invalid or has expired. Ask your team for a new one."
  2. `POST /api/auth/accept-invite {token, name, password}`. This creates a `role:'company'` user with `companyId = owner`, `emailVerified:true`. It returns 201 with the session.
- Recruiters share everything with the owner: profile, jobs, swipes, credits, chats, interviews, tasks, notifications. Only the owner can invite or remove people. Removing a member deletes their User record, and they are logged out immediately because the user lookup fails.

### 1.7 Admin
- A user is admin if their email is in `ADMIN_EMAILS` (comma separated, case-insensitive) **and** their email is verified.
- All `/api/admin/*` routes need `auth` plus this check, otherwise 403 "Admins only". Admin routes do not check role.

---

## 2. Endpoints

Legend:
- **A**: `auth`
- **V**: `requireVerified`
- **Cand**: candidate role
- **Co**: company role (owner or recruiter)
- **Owner**: `requireOwner`

### 2.1 `/api/auth`
| Method & path | Guard | Body / params | Response | Notes |
|---|---|---|---|---|
| GET `/api/auth/invite/:token` | none | | `{email, companyName}` (`'your team'` fallback) | 404 if invalid or expired |
| POST `/api/auth/accept-invite` | fromApp, limiter | `{token, name (non-empty), password (≥6)}` | 201 session (+token) | Errors: 400 "Please enter your name", 400 "Password must be at least 6 characters", 404 invalid invite, 409 "An account with this email already exists", 409 "This invite was already used" |
| POST `/api/auth/register` | fromApp, limiter | `{name, email (regex `^[^\s@]+@[^\s@]+\.[^\s@]+$`), password ≥6, role: 'candidate'\|'company'}` | 201 session (+token) | Email is lowercased and trimmed; name max 80 (schema). Creates an empty profile. Errors: 400 "Please enter your name" / "Please enter a valid email address" / "Password must be at least 6 characters" / "Please choose an account type"; 409 "An account with this email already exists" |
| POST `/api/auth/login` | fromApp, limiter | `{email, password}` | 200 session (+token) | 401 "Incorrect email or password". Login works when unverified; check `user.emailVerified` |
| POST `/api/auth/email/send` | A | none | `{verified:true}` if already verified, else `{sentTo, retryIn (s), devCode?}` | 429, 502 (see 1.4) |
| POST `/api/auth/email/verify` | A | `{code}` | session (no token) | 400 "This code has expired. Tap \"Send a new code\"." (`field:code`), 429 daily fails / 5 tries, 400 "Wrong code, please check and try again" (`field:code`) |
| POST `/api/auth/logout` | none | | `{ok:true}` | Clears the cookie only |
| POST `/api/auth/logout-all` | A | | `{ok:true}` | `tokenVersion++`: all tokens invalidated |
| GET `/api/auth/me` | A | | session | Does not need verification |

`fromApp` requires `X-Requested-With: XMLHttpRequest` **or** `X-Auth-Mode: token`, otherwise 403.

### 2.2 `/api/account` (A only; verification **not** required)
| Method & path | Body | Response | Notes |
|---|---|---|---|
| PUT `/api/account` | `{name?, phone?}` | session | name trimmed, max 80, non-empty (400 `field:name`). phone max 20, regex `^\+?[\d\s-]{10,16}$` (400 `field:phone`); empty clears it. `User.phone` is the recruiter's own number; candidates keep their phone on the profile |
| POST `/api/account/avatar` | multipart field **`image`** (JPG/PNG/WebP, ≤3 MB) | session | 400 "Please choose a photo"; magic-byte check; the old file is deleted |
| DELETE `/api/account/avatar` | | session | |
| PUT `/api/account/password` | `{current, next}` | `{ok:true, token?}` | 400 "New password must be at least 6 characters" (`field:next`); 400 "Your current password is not correct" (`field:current`). Bumps `tokenVersion` (logs out everywhere) and issues a new cookie/token |

**There is no delete-account endpoint** anywhere in the backend.

### 2.3 `/api/candidate` (A + V + Cand)
| Method & path | Body / params | Response | Notes / side effects |
|---|---|---|---|
| PUT `/api/candidate/profile` | See the field table below. **All required fields must be sent on every call.** | `{profile}` | Step becomes `max(step, resumeUrl ? 2 : 1)`. If `step ≥ 3`, triggers saved-search alerts |
| POST `/api/candidate/resume/autofill` | multipart **`resume`** (PDF ≤5 MB) | `{fields, profile}` | No step requirement. Parses the PDF (section 4.12), saves `resumeUrl`, bumps step to 2 if step ≥ 1. Scanned PDFs give `fields:{}`. Old resume deleted. 400 "Please choose your resume (PDF)" |
| POST `/api/candidate/resume` | multipart **`resume`** | `{profile}` | Requires `step ≥ 1`, else 400 "Please complete the previous step first". Sets step to at least 2 |
| POST `/api/candidate/video` | multipart **`video`** (MP4/WebM/MOV ≤40 MB) | `{profile}` | Requires `step ≥ 2`. Sets step 3, which makes the profile **live**, and triggers saved-search alerts |
| GET `/api/candidate/stats` | | `{shortlistedBy[], hiddenCount, viewedCount, wishlistedCount}` | `viewedCount` = total swipes on the candidate (left + right, all jobs). `hiddenCount` = distinct companies that shortlisted but have not contacted. `shortlistedBy[]` only includes companies that contacted the candidate (see `shortlistedBy` item below) |
| POST `/api/candidate/active` | | `{profile}` | "I'm still looking": `activeAt = now`. 404 "Profile not found" |
| PUT `/api/candidate/preferences` | `{openToWork?: bool (===true), workModes?: [onsite\|remote\|hybrid], jobTypes?: [full-time\|part-time\|internship\|contract], preferredLocations?: string[] (max 10, each ≤40 chars, deduped)}` | `{profile}` | Alerts fire if `step ≥ 3`. `openToWork:false` hides the candidate from feeds, swipes and new wishlist adds |
| GET `/api/candidate/companies/:companyId` | | `{company}` (see below) | Needs a shortlisted pair **and** that the company contacted the candidate. 403 "You can only contact shortlisted candidates" / "This company has not contacted you yet"; 400 "Invalid user"; 404 "Company not found" |

Each item in `shortlistedBy[]` has:
- `id` (swipe id), `companyId`
- `companyName`, `industry`, `hiringFor` (job title), `location` (job location or company location), `workMode`, `website`
- `verified` (bool), `logoUrl` (signed)
- `stage`: `'rejected'` is shown to the candidate as `'closed'`
- `date`

There is one entry per right-swipe, so a candidate shortlisted for several jobs at one company gets several entries.

The `company` object from `GET /companies/:companyId` has:
- `id`, `name`, `logoUrl`, `verified`, `industry`, `companySize`, `location`, `address`, `about`, `website`, `linkedin`, `foundedYear`
- **`contactEmail`, `phone`**
- `roles[]`: the jobs they were shortlisted for, each `{id, title, jobLocation, workMode, jobType, salaryMin, salaryMax, description}`

**PUT `/api/candidate/profile` fields** (strings are trimmed and truncated; `*` = required):

| Field | Rule |
|---|---|
| `headline*` | string ≤80. Label "Job title / role" |
| `phone*` | ≤20 chars, regex `^\+?[\d\s-]{10,16}$` |
| `age*` | number 16–75 |
| `gender*` | string ≤30 |
| `location*` | string ≤80 |
| `qualification*` | string ≤40 |
| `degree*` | string ≤80 |
| `college` | string ≤120 |
| `graduationYear` | number 1960–2040 |
| `skills*` | array, ≥1 item, max 30 items, each ≤40 chars, case-insensitive dedupe |
| `experienceYears*` | number 0–50 |
| `currentCompany`, `currentPost` | string ≤80 |
| `currentSalary` | salary (LPA) |
| `expectedSalary*` | salary (LPA) |
| `expectedSalaryMax` | salary (LPA); must be ≥ `expectedSalary` (400 `field:expectedSalaryMax`) |
| `salaryNegotiable` | bool (`===true`) |
| `noticePeriod` | string ≤30 |
| `about` | string ≤600 |
| `workModes`, `jobTypes` | arrays filtered to the allowed enums |

Missing required fields return 400 "`<Label>` is required" with `field`. Bad numbers return 400 "Please enter a valid `<label>`" with `field`. `preferredLocations` and `openToWork` can only be set via `/preferences`.

### 2.4 `/api/company/jobs` (A + V + Co)
| Method & path | Body | Response | Notes |
|---|---|---|---|
| GET `/api/company/jobs` | | `{jobs: [publicJob + stats:{swiped, shortlisted, interviewing, hired}]}` | Sorted open, then paused, then closed; newest first within each group |
| POST `/api/company/jobs` | job fields | 201 `{job}` | Max **25** non-closed jobs: 400 "You can have up to 25 active jobs. Close an old one first." |
| PUT `/api/company/jobs/:id` | job fields (full; title, requiredSkills and salaryMax are required again) | `{job}` | 400 "Invalid job", 404 "Job not found" |
| PATCH `/api/company/jobs/:id/status` | `{status: open\|paused\|closed}` | `{job}` | Reopening is blocked when 25 are already active |

**Job fields** (`utils/jobs.js jobFields`):

| Field | Rule |
|---|---|
| `title*` (or legacy `hiringFor`) | ≤80. Label "Role you are hiring for" |
| `requiredSkills*` | array, ≥1, max 30, each ≤40 |
| `minExperience`, `maxExperience` | 0–50; min ≤ max |
| `salaryMin` | LPA; must be ≤ `salaryMax` |
| `salaryMax*` | LPA |
| `jobLocation` | ≤80 |
| `workMode` | onsite\|remote\|hybrid |
| `jobType` | full-time\|part-time\|internship\|contract |
| `openings` | 1–1000 |
| `description` | ≤3000 |

`publicJob` = `{id, title, requiredSkills, minExperience, maxExperience, salaryMin, salaryMax, jobLocation, workMode, jobType, openings, description, status, createdAt}`.

There is **no candidate-facing job listing or apply endpoint**. Candidates only see jobs through the company detail page after being contacted.

### 2.5 `/api/company` (A + V + Co)
| Method & path | Body / query | Response | Notes / side effects |
|---|---|---|---|
| POST `/api/company/logo` | multipart **`image`** (≤3 MB) | `{profile}` | Any team member can change it; old logo deleted |
| DELETE `/api/company/logo` | | `{profile}` | |
| PUT `/api/company/profile` | company fields (below) + on first call the first job's fields | `{profile}` | Sets `completed:true`. If the company has no job yet, it validates and creates a Job from the same body (`title`/`hiringFor`, `requiredSkills`, `salaryMax` required; `jobLocation` defaults to `location`) and copies `hiringFor` and `requiredSkills` onto the profile. Verification reset: see the warning below |
| GET `/api/company/feed` | query: `jobId?`, `exclude?` (comma ids), `limit?` (default 10, max 30), filters `location`, `minExp`, `maxExp`, `maxSalary`, `notice` (comma list), `skills` (comma list, ≤10) | `{candidates: Card[], swipesLeft, job: publicJob}` | 403 "Please complete your hiring requirements first"; 403 `code:NO_JOB` "Please add a job you are hiring for first"; 409 "This job is paused or closed. Reopen it to see candidates."; 404 "Job not found". `limit` is capped at `swipesLeft - exclude.length`; if that is 0 the response is `candidates:[]`. Each card has `wishlisted` |
| POST `/api/company/swipe` | `{candidateId, action:'left'\|'right', jobId?}` | `{swipesLeft, contact?: {email, phone}}` (contact only on right) | **Each swipe (left or right) costs 1 credit**. Errors: 400 "Invalid candidate" / "Invalid swipe"; 404 "Candidate not found" (must be step 3 and open to work); 409 `SALARY_MISMATCH` (right only); 403 incomplete profile; 402 `code:NO_SWIPES` "You have used all your swipes. Buy a plan to keep swiping."; 409 "You have already swiped this candidate for this job" (credit refunded). On right: notification `shortlisted` + email to the candidate (anonymous: "A company shortlisted you!") |
| POST `/api/company/swipe/undo` | | `{swipesLeft, action, jobId, card}` | Undoes the **caller's own** latest swipe made within **10 min**. A left swipe is refunded. A right swipe is **not refunded**, and is only allowed if the stage is still `shortlisted` and no message, interview or task was created since; otherwise 409 "You have already contacted this candidate, so this swipe cannot be undone". Deletes the `shortlisted` notification. 404 "There is no recent swipe to undo" |
| PUT `/api/company/wishlist/:candidateId` | `{wishlisted: boolean}` (must be a boolean, else 400 "Invalid request") | `{wishlisted}` | Idempotent and free. Adding requires a live, open-to-work candidate (404) |
| GET `/api/company/wishlist` | | `{candidates: Card[]}` | Scored against the default job (oldest open job, or `null` if there are no jobs). Cards have `wishlisted:true`, `swipe:'right'\|null`, and `contact` only if already right-swiped for any job |
| GET `/api/company/shortlisted` | `jobId?` | `{candidates}` | One entry per right-swipe. Card plus `swipeId`, `job:{id,title}`, `wishlisted`, `swipe:'right'`, `stage`, `notes`, `shortlistedAt`, **`contact:{email, phone}`**. Newest first |
| PATCH `/api/company/pipeline/:swipeId` | `{stage?: shortlisted\|contacted\|task\|interview\|hired\|rejected, notes?: ≤2000}` | `{ok:true, stage?, notes?}` | 404 "This candidate is not in your pipeline". Moving to `hired` (from another stage) sends a `hired` notification + email to the candidate ("Congratulations! `<Company>` selected you 🎉") |
| GET `/api/company/searches` | | `{searches:[{id, name, filters, alerts}]}` | |
| POST `/api/company/searches` | `{name (≤60), filters:{location, minExp, maxExp, maxSalary, notice[], skills[]}, alerts? (default true)}` | 201 `{search}` | 400 "Give this search a name"; 400 "Set at least one filter before saving the search"; max **20** per company. Candidates who already match are pre-marked so they never trigger an alert |
| PATCH `/api/company/searches/:id` | `{alerts?: bool, name?}` | `{search}` | Filters cannot be edited. 404 "Saved search not found" |
| DELETE `/api/company/searches/:id` | | `{ok:true}` | |
| GET `/api/company/verification` | | `{verification:{status, method?, verifiedAt?}, gstin, website, email}` | `email` is the caller's login email |
| POST `/api/company/verification/gst` | `{gstin}` (uppercased; regex `^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`) | `{verification:{status:'pending', method:'gst'}}` | 400 "Please enter a valid 15-character GSTIN"; 409 "Your company is already verified". An admin approves it later |
| POST `/api/company/verification/email/send` | | `{sentTo, devCode?}` | Work-email OTP rules in 4.8 |
| POST `/api/company/verification/email/confirm` | `{code}` | `{verification:{status:'verified', method:'email', verifiedAt}}` | 400 "Code expired, please request a new one"; 429 "Too many wrong attempts, please request a new code" (5 tries); 400 "Wrong code, please check and try again" |

**PUT `/api/company/profile` fields:**

| Field | Rule |
|---|---|
| `companyName*` | ≤100 |
| `industry` | ≤60 |
| `website` | ≤200; normalized to `https://…`, host must contain a dot, else 400 "Please enter a valid web address" (`field:website`) |
| `companySize` | ≤30 |
| `location*` | ≤80. Label "Company location" |
| `about` | ≤1500 |
| `address` | ≤200 |
| `phone` | ≤20, regex `^\+?[\d\s-]{8,16}$` |
| `contactEmail` | ≤120, lowercased, email regex |
| `linkedin` | URL, same normalization as `website` |
| `foundedYear` | 1800–current year |

> **Warning: verification reset.** If the current verification status is not `none` and either `companyName` changes or `(website || '') !== (current.website || '')`, the verification is reset to `{status:'none'}`. If the app **omits `website`** from the PUT while one is saved, the comparison treats it as a change and verification is reset. **Always send the full company form, including `website`.**

**Card shape** (`toCard`) is what companies see about a candidate:
- `id` (candidate user id), `name`, `avatarUrl` (signed)
- `headline`, `location`, `qualification`, `degree`, `college`, `graduationYear`, `skills`
- `experienceYears`, `currentCompany`, `currentPost`, `currentSalary`, `expectedSalary`, `expectedSalaryMax`, `salaryNegotiable`, `noticePeriod`, `about`
- `resumeUrl`, `videoUrl` (signed)
- `workModes`, `jobTypes`, `preferredLocations`
- When a job is given: `matchScore` (0–100) and `matchedSkills[]`
- Plus extras such as `wishlisted`, `contact`, etc.

**Age, gender and phone are never in a card.** Phone and email only appear in `contact`.

### 2.6 `/api/team` (A + V + Co)
| Method & path | Guard | Body | Response |
|---|---|---|---|
| GET `/api/team` | | | `{isOwner, members:[{id, name, email, role:'owner'\|'recruiter', you, joinedAt}], invites:[{id, email, expires}]}` |
| POST `/api/team/invite` | Owner | `{email}` | 201 `{ok, devLink?}`. Errors: 400 invalid email (`field:email`); 409 "This email already has a Swipe Hire account"; 400 "Your team can have up to 10 people." Sends the invite email |
| DELETE `/api/team/invites/:id` | Owner | | `{ok:true}` |
| DELETE `/api/team/members/:id` | Owner | | `{ok:true}`. Errors: 400 "You cannot remove yourself" / "Invalid member"; 404 "Member not found" |

### 2.7 `/api/payment`
| Method & path | Guard | Body | Response |
|---|---|---|---|
| GET `/api/payment/plans` | **public** (defined before auth) | | `{plans: PLANS, freeSwipes, demoMode: bool}` |
| POST `/api/payment/webhook` | Razorpay signature (`x-razorpay-signature`, HMAC-SHA256 of the raw body with `RAZORPAY_WEBHOOK_SECRET`) | raw | `{ok:true}`; 503 if not configured; 400 "Invalid signature". Handles `payment.captured` and `order.paid`. Credits only if `entity.amount === price*100` |
| POST `/api/payment/order` | A + V + Co | `{planId}` | `{mode:'razorpay'\|'demo', orderId, amount (paise), currency:'INR', keyId, plan}`. Errors: 400 "Please choose a valid plan"; 503 "Payments are not available right now". The demo order id is `demo_<16 hex>` |
| POST `/api/payment/verify` | A + V + Co | `{orderId, paymentId, signature}` | `{profile (company), added (swipes credited; 0 if already credited)}`. Razorpay mode checks `HMAC_SHA256(keySecret, "orderId|paymentId")`. Demo mode needs `demoPayments` on. 404 "Order not found", 400 "Payment verification failed" |

### 2.8 `/api/chats` (A + V; either role)
| Method & path | Body | Response | Notes |
|---|---|---|---|
| GET `/api/chats` | | `{conversations: [...]}` | Only conversations with at least one message, sorted by `updatedAt` desc |
| GET `/api/chats/contacts` | | `{contacts:[{id, name, subtitle, verified?, avatarUrl, stage, updatedAt, hasChat}]}` | Everyone you may chat with |
| GET `/api/chats/unread-count` | | `{count}` | |
| GET `/api/chats/:otherId` | | `{with:{id, name, subtitle, verified?, avatarUrl}, messages:[...]}` | Last **200** messages, oldest first. **Marks the other side's messages read.** `by` is the teammate's first name, shown to the company side for messages from other teammates |
| POST `/api/chats/:otherId` | `{text}` (trimmed, 1–2000) | 201 `{message:{id, text, mine:true, at, read:false}}` | 400 "Message cannot be empty" / "Message is too long (max 2000 characters)" |
| POST `/api/chats/bulk` | `{text, candidateIds: string[]}` (1–50 unique) | 201 `{sent, skipped: ids[]}` | Company only (403 "Only companies can message several candidates at once"). Each recipient gets an individual message |

Each `conversations[]` item has:
- `id` (the other side's id), `name`, `subtitle`, `verified?`, `avatarUrl`
- `stage` (latest swipe's stage)
- `lastMessage:{text, at, mine}`, `unread`, `updatedAt`

Each `messages[]` item has `{id, text, mine, by?, at, read}`.

`otherId` meaning:
- For a company user it is the candidate's user id.
- For a candidate it is the company id (owner user id).

Side effects of sending (`deliver`):
- If the sender is a company, every right-swipe for that pair in stage `shortlisted` moves to `contacted`.
- A `message` notification + email is sent to the other side, but only if they have no unread `message` notification from this sender already. To a company, it fans out to the whole team.
- Notification link: `/messages?with=<companyId or candidateId>`.

### 2.9 `/api/interviews` (A + V)
| Method & path | Guard | Body | Response / notes |
|---|---|---|---|
| GET `/api/interviews` | either | | `{interviews:[...]}`, latest 100 by `createdAt` desc |
| POST `/api/interviews` | Co | `{candidateId, jobId?, slots: ISO date strings (1–3), durationMins? (15\|30\|45\|60, default 30), mode? (video\|phone\|in-person, default video), location? (≤200, required if in-person), meetingLink? (≤300, must start `https://`), note? (≤500)}` | 201 `{id}` |
| POST `/api/interviews/:id/accept` | Cand | `{slot}` (must equal one offered slot exactly, by ms timestamp) | `{ok:true}` |
| POST `/api/interviews/:id/cancel` | either | `{reason?}` (≤300) | `{ok:true}` |

Each `interviews[]` item has:
- `id`
- `with:{id, name, subtitle, verified?, avatarUrl}`. For candidates, `subtitle` is the company's `hiringFor`.
- `jobTitle`, `slots[]`, `chosenSlot`, `durationMins`, `mode`
- `meetingLink`: **only when status is `confirmed`**
- `location`, `note`, `status: proposed\|confirmed\|cancelled`, `createdAt`

POST `/api/interviews` rules:
- Requires a shortlisted pair; with `jobId`, the candidate must be shortlisted for that job (403 "This candidate is not shortlisted for that job").
- Every slot must be ≥ now + 15 min.
- 409 "An interview with this candidate is already scheduled" if a proposed interview, or a confirmed one whose slot has not passed, already exists for the pair.
- Video mode without a link auto-creates a Jitsi room `https://meet.jit.si/SwipeHire-<12 hex>`.
- Swipe stage becomes `interview`, unless it is hired or rejected.
- Sends an `interview` notification + email to the candidate, listing the slots in IST.

POST `/:id/accept`:
- 409 "This interview is no longer open" if not proposed.
- 400 "Please choose one of the offered times".
- 400 if the slot has already passed.
- Sets `confirmed` + `chosenSlot` and notifies the company team (+ email).

POST `/:id/cancel`:
- Idempotent.
- Sets `cancelledBy`.
- Notifies the other side (+ email). The body is the reason, or "You can agree on a new time in chat."

There is **no reschedule or edit endpoint**: cancel and create a new one.

### 2.10 `/api/tasks` (A + V)
| Method & path | Guard | Body | Response / notes |
|---|---|---|---|
| GET `/api/tasks` | either | company may pass `?candidateId` | `{tasks:[...]}`, max 200, newest first |
| POST `/api/tasks` | Co | `{candidateId, jobId?, title (≤120), description (≤5000), briefUrl?, dueAt}` | 201 `{id}` |
| POST `/api/tasks/:id/submit` | Cand | `{liveUrl?, repoUrl?, note? (≤1000)}` | `{ok:true}` |
| PATCH `/api/tasks/:id` | Co | `{dueAt}` | `{ok:true}` |
| POST `/api/tasks/:id/cancel` | Co | | `{ok:true}` |

Each `tasks[]` item has:
- `id`, `with:{id, name, subtitle?, verified?, avatarUrl}`, `jobTitle`
- `title`, `description`, `briefUrl`, `dueAt`
- `status`: `assigned`, `submitted`, `cancelled`, or the computed `overdue` (assigned and past `dueAt`)
- `submission:{liveUrl, repoUrl, note, at}` (if submitted), `createdAt`

The company list includes cancelled tasks. The candidate list excludes them.

POST `/api/tasks` (create):
- Requires a shortlisted pair, or shortlisted for `jobId`.
- `dueAt` must be between now + 1 h and now + 30 days.
- Stage `shortlisted` or `contacted` becomes `task`.
- Sends a `task` notification + email to the candidate.
- Errors: "Please give the task a title", "Please describe what the candidate should build", "Please choose a deadline", "The deadline must be at least 1 hour from now", "The deadline can be at most 30 days away".

POST `/:id/submit`:
- At least one of `liveUrl` / `repoUrl` is required.
- Both are normalized to a URL; `https://` is added if no scheme; only http/https are accepted; max 300 chars.
- `repoUrl` host must be github.com or a subdomain of it.
- Allowed repeatedly until `dueAt` (409 "The deadline for this task has passed"; 409 if cancelled).
- Notifies the company team (+ email) with "submitted" or "updated".

PATCH `/:id`:
- Same 1 h–30 d window.
- 409 if cancelled.
- Notifies the candidate (+ email).

POST `/:id/cancel`:
- Idempotent.
- Notifies the candidate **without** email.

### 2.11 `/api/notifications` (A only)
| Method & path | Response |
|---|---|
| GET `/api/notifications` | `{unread, notifications:[{id, type, title, body, link, at, read}]}`, latest **30** |
| POST `/api/notifications/read-all` | `{ok:true}` |
| POST `/api/notifications/:id/read` | `{ok:true}` (silently ignores bad ids) |

### 2.12 `/api/admin` (A + admin email + verified)
| Method & path | Body | Response |
|---|---|---|
| GET `/api/admin/verifications` | | `{companies:[{id (owner user id), companyName, website, location, gstin, contact:{name, email}, requestedAt}]}`, pending only, oldest first |
| POST `/api/admin/verifications/:companyId` | `{approve: true}` approves; anything else rejects | `{ok:true}`. Sets status verified or rejected with method `gst`. 404 "No pending request for this company". Sends a `verified` notification + email to the whole company team |

### 2.13 Files: `GET /uploads/<folder>/<file>?exp=&sig=` (not under `/api`)
- No auth is needed. The HMAC signature in the URL is the permission.
- Invalid or expired signature: 403 "This link has expired, please refresh the page". Unknown extension: 404.
- `Range` is supported, so video can seek.
- Cache: `private, max-age=10800`. Non-PDF files get `CSP: default-src 'none'; sandbox`.

---

## 3. Mongoose models

All models have `timestamps: true` (`createdAt`, `updatedAt`).

**User**
- `name`: String, required, trim, maxlength 80
- `email`: required, **unique**, lowercase, trim
- `password`: required, `select:false`, bcrypt hash
- `role`: enum `candidate|company`, required
- `companyId`: ObjectId → User, indexed. Set for recruiters (points to the owner); empty for owners and candidates.
- `avatarUrl`: String
- `phone`: String. The recruiter's own number.
- `emailVerified`: Boolean, default false
- `emailOtp`: `{hash, expires, sentAt, tries, sends, fails, windowStart, dev}`, `select:false`
- `tokenVersion`: Number, default 0, `select:false`

**CandidateProfile**
- `user`: → User, required, unique
- `step`: Number, default 0, indexed. 0 = details pending, 1 = resume pending, 2 = video pending, 3 = complete/live.
- `headline`, `phone`, `age` (Number), `gender`, `location`
- `qualification`, `degree`, `college`, `graduationYear` (Number)
- `skills`: [String]
- `experienceYears`: Number
- `currentCompany`, `currentPost`
- `currentSalary`, `expectedSalary` (minimum), `expectedSalaryMax`: Number, all LPA
- `salaryNegotiable`: Boolean, default false
- `noticePeriod`, `about`
- `resumeUrl`, `videoUrl`
- `openToWork`: Boolean, default true
- `activeAt`: Date, default now, indexed
- `preferredLocations`: [String]
- `workModes`: [enum onsite|remote|hybrid]
- `jobTypes`: [enum full-time|part-time|internship|contract]

**CompanyProfile**
- `user`: → User (owner), required, unique
- `completed`: Boolean, default false
- `companyName`, `industry`, `website`, `companySize`, `location`, `about`, `logoUrl`, `address`
- `phone`: shown to candidates the company contacted
- `contactEmail`, `linkedin`, `foundedYear`
- Legacy v1 fields: `hiringFor`, `requiredSkills`, `minExperience`, `maxExperience`, `salaryMin`, `salaryMax`, `jobLocation`, `workMode` (enum, default onsite)
- `gstin`
- `verification`: `{status: enum none|pending|verified|rejected (default none), method: enum email|gst, verifiedAt}`
- `emailOtp`: `{hash, expires, tries, sends, fails, windowStart}`, `select:false`
- `swipesLeft`: Number, default `FREE_SWIPES` (5), min 0
- `swipesPurchased`: Number, default 0
- `creditedOrders`: [String], `select:false`

**Job**
- `company`: → User, required, indexed
- `title`: required, trim, max 80
- `requiredSkills`: [String]
- `minExperience`, `maxExperience`
- `salaryMin`, `salaryMax` (LPA)
- `jobLocation`
- `workMode`: enum, default onsite
- `jobType`: enum, default full-time
- `openings`: default 1, min 1
- `description`: max 3000
- `status`: enum `open|paused|closed`, default open
- `createdBy`: → User

**Swipe**
- `company`: → User, required
- `candidate`: required, indexed
- `job`: required
- `action`: enum `left|right`, required
- `stage`: enum `shortlisted|contacted|task|interview|hired|rejected`, default shortlisted
- `notes`: max 2000
- `swipedBy`: → User
- Indexes: unique `{company, candidate, job}` (one swipe per candidate per job); `{company, createdAt:-1}`

**Wishlist**
- `company`, `candidate`, both required
- Unique index `{company, candidate}`

**Message**
- `company`, `candidate`, `sender`: all required
- `text`: required, max 2000
- `readAt`: Date
- Index `{company, candidate, createdAt:-1}`

**Notification**
- `user`: required
- `type`: String, required
- `title`: required
- `body`
- `link`: a web route
- `from`: → User
- `readAt`
- Index `{user, createdAt:-1}`

**Interview**
- `company`, `candidate`: required, indexed
- `job`
- `slots`: [Date], required
- `chosenSlot`
- `durationMins`: default 30
- `mode`: enum `video|phone|in-person`, default video
- `meetingLink`, `location`, `note`
- `status`: enum `proposed|confirmed|cancelled`, default proposed
- `cancelledBy`

**Task**
- `company`, `candidate`: required, indexed
- `job`, `createdBy`
- `title`: required, max 120
- `description`: required, max 5000
- `briefUrl`
- `dueAt`: required
- `status`: enum `assigned|submitted|cancelled`, default assigned
- `submission`: `{liveUrl, repoUrl, note (max 1000), at}`

**Payment**
- `company`: indexed
- `planId`
- `amount` (rupees)
- `swipes`
- `orderId`: unique
- `paymentId`
- `mode`: enum `razorpay|demo`
- `status`: enum `created|paid`, default created

**SavedSearch**
- `company`: indexed
- `createdBy`
- `name`: required, trim, max 60
- `filters`: `{location, minExp, maxExp, maxSalary, notice:[String], skills:[String]}`
- `alerts`: default true
- `notifiedCandidates`: [ObjectId], `select:false`, keeps the last 5000

**TeamInvite**
- `company`: indexed
- `email`: lowercase
- `tokenHash`: unique
- `invitedBy`
- `expires`: required
- `acceptedAt`

**Migrations** (`config/migrate.js`, run on every start):
- Turns a v1 company's `hiringFor` into its first Job and attaches old swipes to it.
- Syncs Swipe indexes.
- Sets `emailVerified:true` where the field is missing.
- Sets `activeAt = updatedAt` where it is missing.

---

## 4. Business rules

### 4.1 Credits and plans
- Every new company gets `FREE_SWIPES` (default **5**) in `swipesLeft`.
- **Both left and right swipes cost 1.** Wishlisting is free. Undoing a left swipe refunds it; undoing a right swipe does not.
- `PLANS` (in `config/index.js`) has a single plan: `{id:'starter', name:'Starter', price:399 (₹), swipes:150, perks:['150 candidate swipes','Full resume & intro video access','Unlimited wishlist','Contact details on shortlist']}`. There are no other packs.
- Payment provider: Razorpay. It is enabled when `RAZORPAY_KEY_ID` and `RAZORPAY_KEY_SECRET` are set. Currency INR, amount in paise. The app would use the Razorpay Android SDK with the returned `orderId` and `keyId`, then call `/payment/verify` with the JSON body `{orderId, paymentId, signature}` (map Razorpay's `razorpay_order_id`, `razorpay_payment_id` and `razorpay_signature` to these names).
- Demo payments: `demoPayments = DEMO_PAYMENTS==='true' && !razorpayEnabled && (!isProd || DEMO_PAYMENTS_ON_LIVE==='true')`. The flow is `order` → `verify {orderId}` → credited immediately. `/plans` returns `demoMode`.
- Crediting is atomic and idempotent per `orderId` (`creditedOrders`). The webhook and verify cannot both credit the same order.

### 4.2 Match score (`utils/match.js matchCandidate(candidate, job)`)
- **Skills (50):** applies only if the job has `requiredSkills`. Score = 50 × matched / required, case-insensitive exact match. `matchedSkills` uses the job's spelling.
- **Experience (20):** always counted. The range is `[minExp ?? 0, maxExp ?? 50]` and the candidate's experience defaults to 0. Inside the range gives 20; otherwise `max(0, 20 − 6 × gap_years)`.
- **Salary (20):** applies only if the job has `salaryMax` and the candidate has `expectedSalary`. `expected ≤ salaryMax` gives 20; `≤ 1.2 × salaryMax` gives 10; otherwise 0.
- **Location (10):** always counted. 10 if the job is remote, or if the job location and candidate location contain each other (case-insensitive substring).
- `matchScore = round(100 × score / max)`.

### 4.3 Salary fit (hard rule)
- `salaryFits` is true when the candidate is `salaryNegotiable`, the job has no `salaryMax`, or `expectedSalary` is null. Otherwise it requires `expectedSalary ≤ job.salaryMax`.
- Candidates who do not fit are **excluded from the feed** (`salaryFitWhere`). A right swipe on them is rejected with 409 `SALARY_MISMATCH`.

### 4.4 Feed ordering and the "I'm active" ring (`utils/activity.js`)
- Candidates must have `step: 3` and `openToWork ≠ false`. Excluded: anyone already swiped for this job, ids in `exclude`, and anyone failing filters or salary fit.
- The database query sorts by `activeAt` desc and takes up to 500. The server then sorts:
  1. **Stale last.** Stale means `now − (activeAt ?? updatedAt) > ACTIVE_DAYS (15) days`.
  2. Then by `matchScore` + **10** if the profile was created less than **7 days** ago.
- The candidate refreshes `activeAt` with `POST /api/candidate/active`. To show a 15-day countdown ring, use `profile.activeAt` + 15 days. The web uses the same constant in `client/src/lib/activity.js`.

### 4.5 Feed filters (`utils/candidates.js`)
`normalizeFilters`:
- `location`: ≤60 chars. Case-insensitive substring regex on `location` **or** `preferredLocations`.
- `minExp` / `maxExp`: numbers, compared to `experienceYears` (inclusive).
- `maxSalary`: `expectedSalary ≤ maxSalary` **or** `salaryNegotiable:true`.
- `notice`: only values from `['Immediate','15 days','30 days','60 days','90 days']` are kept; matched with `noticePeriod $in`.
- `skills`: up to 10. The candidate must have **any** of them (exact, case-insensitive).

The same filters are used for saved searches and alerts.

### 4.6 Saved searches and alerts
- Max 20 per company. At least one filter is required.
- An alert fires when a candidate becomes or stays live: after `PUT /candidate/profile` with step ≥ 3, `POST /candidate/video`, or `PUT /candidate/preferences` with step ≥ 3.
- Every saved search with `alerts:true` that matches, and has not notified for that candidate before, notifies the company team once per candidate:
  - type `alert`
  - title `New match for "<name>"`
  - link `/company/swipe?search=<id>`
  - with email
- Salary fit is **not** applied in alert matching.

### 4.7 Contact-detail visibility
- **Company sees the candidate's** email + phone:
  - in the right-swipe response `contact`
  - in `GET /shortlisted` (always)
  - in `GET /wishlist` (only if right-swiped)
- Cards never include age, gender, phone or email.
- **Candidate sees the company:**
  - A shortlist alone is anonymous. The notification says "A company shortlisted you!", and `stats.hiddenCount` counts these companies.
  - The company is revealed once it **contacts** the candidate: a company-side message, any task, or any interview (`companiesThatContacted`).
  - After that, it appears in `stats.shortlistedBy`, chats and contacts, and `GET /candidate/companies/:id` shows `contactEmail` and `phone`.

### 4.8 Company verification
There are **no document uploads**. The two methods are:

**GST**
- Submit a GSTIN; status becomes `pending`.
- An admin approves (`verified`, method `gst`) or rejects (`rejected`).

**Work email OTP** (instant)
- The login email must not be a free provider: gmail, googlemail, yahoo, ymail, hotmail, outlook, live, msn, rediffmail, icloud, me, aol, proton, protonmail, zoho, gmx, yandex.
- The company profile must have a `website`.
- The email domain must equal the site domain or be a subdomain match in either direction (`www.` is stripped).
- 6-digit code, **10 min** TTL, **5 tries** per code, **5 sends/day**, **15 fails/day** (the daily counts are checked on send only).
- `devCode` is returned only when `!mailEnabled && !isProd`. `SHOW_EMAIL_CODE` does not apply here.

**Other rules**
- Renaming the company or changing the website resets status to `none` (see the warning in 2.5).
- Verified is shown as a `verified: bool` badge to candidates.

### 4.9 Wishlist
- Per company (not per job), free.
- Toggled with a `{wishlisted: bool}` PUT.
- Only live, open-to-work candidates can be added.
- Feed cards carry a `wishlisted` flag.

### 4.10 Shortlist pipeline
Stages: `shortlisted → contacted → task → interview → hired | rejected`. They are per Swipe, i.e. per candidate per job.

Automatic transitions:
- The first company message moves `shortlisted` to `contacted` for all of that pair's right-swipes.
- Creating a task moves `shortlisted`/`contacted` to `task`.
- Creating an interview moves any stage except hired/rejected to `interview`.

Manual changes go through `PATCH /company/pipeline/:swipeId`. `hired` notifies and emails the candidate. Candidates see `rejected` as `closed`.

### 4.11 Chat rules
- A conversation is company ↔ candidate. On the company side the whole team shares it; `mine` means "sent by our side".
- A company can message any candidate it has right-swiped for any job.
- A candidate can message a company only after that company has contacted them.
- One conversation per pair, even across several jobs.
- "Group message" is `POST /chats/bulk`: up to 50 candidates, each getting an individual message. Ids that are not allowed are returned in `skipped`. There are no group chat rooms.
- No attachments. Text only, ≤2000 chars.
- No websockets: the web client polls.

### 4.12 Resume parsing (`utils/resumeParser.js`)
Uses `pdf-parse` (`PDFParse.getText`). `extractProfile` returns only the fields it finds:
- `phone`: Indian mobile `[6-9]\d{4}[\s-]?\d{5}`, optional +91; spaces and dashes stripped.
- `skills`: up to 15 from `SKILLS`, longest names first. Spoken-language sections are excluded. "Java Script" is read as JavaScript.
- `degree`: the highest-ranked degree, mapped to the `DEGREES` list, including specialisations such as "B.Tech (CSE)". Only returned if it is in `DEGREES`.
- `qualification`: one of `PhD`, `Post Graduate`, `Graduate`, `Diploma`, `12th`, `10th`.
- `graduationYear`: the latest year (1960–2039, ≤ now + 6) on the degree line or the next 3 lines.
- `college`: a line containing university/college/institute/IIT etc. School and board lines are skipped.
- `headline`: the first `ROLES` title found in the text.
- `location`: the first `CITIES` entry found (excluding "Remote").
- `experienceYears`, in order of preference:
  1. A stated "N+ years experience" (the max, if ≤45).
  2. Otherwise the sum of job date ranges (overlaps merged), rounded down to 0.5.
  3. Otherwise 0 if the word "fresher" appears.
- `currentCompany`, `currentPost`: from the latest date range's neighbouring lines, or a "Currently working as X at Y" sentence.

### 4.13 Uploads
| Kind | Multipart field | Types | Max | Stored ext |
|---|---|---|---|---|
| Resume | `resume` | `application/pdf`, or `''`/`application/octet-stream` with a `.pdf` filename | 5 MB | .pdf |
| Video | `video` | `video/mp4`, `video/webm`, `video/quicktime` (the declared MIME must match) | 40 MB | .mp4/.webm/.mov |
| Photo / logo | `image` | `image/jpeg`, `image/png`, `image/webp` | 3 MB | .jpg/.png/.webp |

- One file per request.
- The first bytes are checked against magic signatures (`%PDF-`, EBML/`ftyp`, JPEG/PNG/RIFF-WEBP). Failure gives 400 "This file is not a valid PDF / video / image".
- Bad type errors: 400 "Resume must be a PDF file", "Video must be MP4, WebM or MOV", "Photo must be a JPG, PNG or WebP image".
- Storage: when Cloudinary is configured (`CLOUDINARY_URL`, or `CLOUDINARY_CLOUD_NAME` + `CLOUDINARY_API_KEY`/`CLOUDINARY_API` + `CLOUDINARY_API_SECRET`), files go to Cloudinary as `type:'authenticated'` under the folder `CLOUDINARY_FOLDER` (default `swipehire`). PDFs and images are image resources; videos are video resources. Otherwise they stay on local disk.
- The database stores `/uploads/<resumes|videos|images>/<userId>-<ts><ext>`.
- API responses return **relative signed URLs** `/uploads/...?exp=<unix>&sig=<base64url HMAC>`. They are valid **3–6 h**, rounded to 3-hour windows. The app must prefix the backend (or Vercel) origin and re-fetch the parent resource to refresh expired links.
- Replacing a file deletes the old one.

### 4.14 Notification types and links
| type | Recipient | Trigger | Email? | link |
|---|---|---|---|---|
| `shortlisted` | candidate | right swipe | yes | `/candidate` |
| `message` | other side | new message (one unread at a time per sender) | yes | `/messages?with=<id>` |
| `interview` | candidate / company team | invite, confirm, cancel | yes | `/interviews` or `/messages?with=` |
| `task` | candidate / company team | create, submit or update, deadline change, cancel | yes (cancel: no) | `/tasks` |
| `hired` | candidate | stage set to hired | yes | `/messages?with=<companyId>` |
| `verified` | company team | admin decision | yes | `/company/verify` |
| `alert` | company team | saved-search match | yes | `/company/swipe?search=<id>` |

- Company notifications go to every team member.
- Email text is: "Hi `<first name>`, `<body>` Open Swipe Hire: `<CLIENT_URL[0]><link>`".
- Links are web routes; map them to app screens or deep links.
- Email is sent via Brevo (`BREVO_API_KEY`), Resend (`RESEND_API_KEY`, or `SMTP_HOST=smtp.resend.com`), or SMTP, in that order. With none of them, emails go to the console log.
- There is no push (FCM) support in the backend.

### 4.15 Polling (web client, `usePoll`; only while visible)
| What | Endpoint | Interval |
|---|---|---|
| Unread chat badge | `/chats/unread-count` | 15 s |
| Notifications bell | `/notifications` | 30 s |
| Interviews page | `/interviews` | 30 s |
| Tasks page | `/tasks` | 30 s |
| Open chat thread | `/chats/:otherId` | 4 s |
| Conversation list | `/chats` | 10 s |

Stay well under the 600/min per-IP limit.

### 4.16 Jobs
- Each job has its own feed, swipe dedupe and pipeline.
- `jobId` is optional on feed, swipe, interviews and tasks. Without it the server uses the oldest **open** job, or the oldest job of any status.
- Max 25 non-closed jobs.
- A paused or closed job's feed returns 409.
- A swipe does not check job status, only the feed does.

---

## 5. `shared/taxonomy.js`
Path: `D:\Swipe Hire\shared\taxonomy.js`. It is an ES module (`shared/package.json` has `"type":"module"`), plain arrays with no imports. Port it to Kotlin or bundle it as a JSON asset.

| Export | Size | Samples |
|---|---|---|
| `ROLES` | 195 | 'Web Developer', 'Full Stack Developer', 'Android Developer', 'Data Analyst', 'UI/UX Designer', 'HR Executive', 'Telecaller', 'Fresher / Intern' |
| `SKILLS` | 206 | 'HTML', 'JavaScript', 'React', 'Node.js', 'Python', 'MongoDB', 'AWS', 'Figma', 'SEO', 'Tally', 'Communication', 'Hindi' |
| `DEGREES` | 47 | 'B.Tech', 'B.Tech (CSE)', 'B.E.', 'BCA', 'MCA', 'B.Sc', 'B.Com', 'MBA', 'PGDM', 'Diploma (Engineering)', 'ITI', 'CA', 'PhD', '12th (Science)', '10th' |
| `CITIES` | 183 | 30 major cities first ('Jaipur', 'Delhi', 'New Delhi', 'Mumbai', 'Bengaluru', 'Hyderabad', 'Pune'…), then the rest alphabetically, legacy names ('Bangalore', 'Gurgaon', 'Bombay'…), and finally 'Remote' |
| `STATES` | 36 | 28 states + 8 UTs ('Andhra Pradesh' … 'West Bengal', 'Delhi NCR', 'Chandigarh UT', 'Puducherry'…) |
| `LOCATIONS` | 219 | major cities + other cities + states + 'Remote' (location autocomplete) |

Option lists that are **not** in `taxonomy.js`, with where they live:
- Notice periods `['Immediate','15 days','30 days','60 days','90 days']`: enforced by the server in filters (`utils/candidates.js NOTICE_OPTIONS`); the web also has it in `client/src/pages/candidate/CandidateOnboarding.jsx` and `FeedFilters.jsx`.
- Qualifications `['10th','12th','Diploma','Graduate','Post Graduate','PhD']` and genders `['Male','Female','Other']`: web-only, in `CandidateOnboarding.jsx`.
- Company sizes `['1–10','11–50','51–200','201–1000','1000+']` and industries `['IT / Software','E-commerce','Finance','Healthcare','Education','Manufacturing','Marketing / Media','Retail','Real Estate','Other']`: web-only, in `client/src/pages/company/CompanyOnboarding.jsx`.
- Work modes `onsite|hybrid|remote` and job types `full-time|part-time|internship|contract`: server enums; the labels are in `client/src/lib/options.js`.
- The server stores qualification, gender, notice period, company size and industry as **free strings with no enum**. Only notice-period values matter for filtering.

---

## 6. Env and config relevant to clients
- **Production:** frontend `https://swipe-hire-sand.vercel.app`, backend `https://swipe-hire-z1th.onrender.com`. The API is at `/api`; files are at `/uploads` on the same origin.
- Server env variable **names**:
  - Core: `PORT` (default 5000), `NODE_ENV`, `MONGO_URI` (required in production; dev falls back to an embedded mongod in `server/.data`), `JWT_SECRET` (≥32 chars, must not start with `change-me`, else the server refuses to start; it also signs file URLs).
  - Web/session: `CLIENT_URL` (comma-separated CORS origins; the first is used in email links and the invite `/join?token=` link), `COOKIE_SAMESITE`, `TRUST_PROXY`.
  - Product: `FREE_SWIPES`, `ADMIN_EMAILS`.
  - Email: `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`, `MAIL_FROM`, `BREVO_API_KEY`, `RESEND_API_KEY`.
  - Payments: `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `DEMO_PAYMENTS`, `DEMO_PAYMENTS_ON_LIVE`.
  - Testing: `SHOW_EMAIL_CODE`.
  - Storage: `CLOUDINARY_URL`, `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API`, `CLOUDINARY_API_SECRET`, `CLOUDINARY_FOLDER`.
- Client env (`client/.env.example`): `VITE_API_URL` (e.g. `https://api.swipehire.in/api`), `VITE_FILES_URL`, `VITE_SITE_URL`.
- The client can find out at runtime whether payments are in demo mode (`GET /api/payment/plans` → `demoMode`) and whether verification codes are shown on screen (`devCode` present in the `/auth/email/send` response).

## 7. Things the backend does not have
Plan around these on Android or add them server-side:
- No delete-account endpoint.
- No forgot or reset password.
- No company document upload (GSTIN text plus admin review only).
- No push notifications (FCM) or websockets; polling only.
- No candidate job browsing or apply.
- No interview reschedule (cancel and recreate).
- No chat attachments.
- No pagination params on lists: notifications 30, chat 200 messages, interviews 100, tasks 200.
- Only one paid plan (Starter: ₹399 for 150 swipes).

---

# Part B. Candidate and shared screens

Source: client at `client/src`, server rules at `server/src`, shared option lists at `shared/taxonomy.js`.

Two things people often expect but the website **does not have**: there is no "delete account" option (Settings only has photo, name, password and "Log out of all devices"), and chat has no attachments (text only, up to 2000 characters).

## B0. Global behaviour

### API, login and session
- **Base URL:** `VITE_API_URL` or `/api`. Every web request sends `withCredentials: true` and the header `X-Requested-With: XMLHttpRequest`. This header is a CSRF guard: on cookie-based requests the server rejects POST/PUT/PATCH/DELETE without it, with "Request blocked, please refresh the page and try again".
- **Web login:** a cookie called `sh_session` (httpOnly, 30 days, path `/api`).
- **App login:** the server also accepts `Authorization: Bearer <jwt>`.
  - Send the header `X-Auth-Mode: token` on `/auth/register`, `/auth/login`, `/auth/accept-invite` and `PUT /account/password`; the JSON response then also contains `token`.
  - With a Bearer token, the `X-Requested-With` check is skipped.
  - The JWT carries `v` (tokenVersion). "Log out of all devices" and a password change increase it, which invalidates older tokens.
- **Session restore:** on start the client calls `GET /auth/me`, which returns `{user, profile}`. A 401 means logged out. Any other error (network or 5xx) shows the offline screen.
- **`user` shape:** `{id, name, email, role: 'candidate'|'company', emailVerified, isAdmin, avatarUrl, phone, companyId?, isOwner?}`.
- **Candidate `profile` fields:**
  - Progress and contact: `step`, `headline`, `phone`, `age`, `gender`, `location`
  - Education: `qualification`, `degree`, `college`, `graduationYear`
  - Work: `skills[]`, `experienceYears`, `currentCompany`, `currentPost`
  - Salary: `currentSalary`, `expectedSalary`, `expectedSalaryMax`, `salaryNegotiable`
  - Other: `noticePeriod`, `about`
  - Files: `resumeUrl`, `videoUrl`
  - Preferences and activity: `openToWork` (default true), `activeAt`, `preferredLocations[]`, `workModes[]`, `jobTypes[]`
  - Timestamps: `createdAt`, `updatedAt`
- **`step` values:** 0 = details pending, 1 = resume pending, 2 = video pending, 3 = complete. The profile is "live" at step 3 or more.
- **Logout:** `POST /auth/logout` (errors ignored), clear drafts and local state, go to `/auth`.
- **Error text:** show `err.response.data.message`, or "Something went wrong, please try again". Many errors also return `field`, which the form uses to put the message under that input.
- **File URLs:** resume, video, avatar and logo URLs are signed (`/uploads/...?exp=&sig=`) and valid for 3–6 hours. Prefix relative paths with the files origin; full `http(s)` URLs are used as they are.
- **Rate limits:** auth: 30 failed attempts per 15 minutes → "Too many attempts, please try again in a few minutes". Chat send: 30 per minute → "You are sending messages too fast, please slow down".

### Home path and route guards
**Home path** decides where a signed-in user goes:
- No user → `/auth`
- `emailVerified === false` → `/verify-email`
- Candidate: `profile.step >= 3` → `/candidate`, otherwise `/candidate/onboarding`
- Company: `profile.completed` → `/company/swipe`, otherwise `/company/onboarding`

**Guards** (all show a full-screen spinner while auth is loading):
- **Guard:** no user → `/auth`; unverified → `/verify-email`; wrong role, or onboarding required and not done → home path.
- **GuestOnly** (`/auth`, `/join`): a signed-in user is sent to the home path.
- **Unverified** (`/verify-email`): no user → `/auth`; already verified → home path.
- **`/`:** a signed-in user is sent to the home path, otherwise the Landing page is shown.

| Route | Who can open it |
|---|---|
| `/` | Landing for visitors; signed-in users redirected |
| `/auth` | GuestOnly |
| `/verify-email` | Unverified |
| `/candidate/onboarding` | Candidate. If step ≥ 3 and no `?edit`, it redirects to `/candidate` |
| `/candidate` | Candidate, onboarded |
| `/messages`, `/interviews`, `/tasks`, `/settings` | Any role, onboarded |
| `/join?token=` | GuestOnly |
| `*` | Not found page |

- Page transition: opacity fade, 0.22 s.
- Browser titles use "X · Swipe Hire": My dashboard, My profile, Messages, Interviews, Tasks, Account settings, Verify your email, Join your team, "Page not found".

### Offline screen
- **When:** the `/auth/me` check fails with something other than 401. Shown on every route except `/` and `/auth`.
- **Content:** illustration `offline`, heading **"Can't reach Swipe Hire"**, text "Check your internet connection and try again.", button **"Try again"** (calls `/auth/me` again).

### Toasts
- Desktop (≥768 px) bottom-right; mobile top-center, 76 px from the top so they don't cover the header.

### Theme (website today)
- **Themes:** light (default; sky blue on white, background `#f3f7fc`) and dark (pink `#ff4d6d` / violet `#7c5cff` on near-black `#07070d`).
- **Storage:** localStorage key `swipehire_theme`, value `'light'` or `'dark'`. Toggle button: sun icon when light, moon icon when dark.
- **Light palette:** brand-500 `#0284c7`, violet-brand `#2563eb`, danger `#dc2626`. Dark danger `#fb7185`.
- **Font:** Plus Jakarta Sans.
- **Illustrations:** `/illustrations/{name}.webp` for dark and `{name}-light.webp` for light.
- **Pending change:** the client wants deep green `#1F4D42` + white and no cartoon illustrations (see the top of this document).

### Drafts
- The onboarding form is saved in sessionStorage while the user is on steps 0–1 (key `swipehire_draft_candidate_<userId>`, with `_edit` added when editing), so a refresh keeps the answers. Cleared on logout and on Cancel. In the app, keep an equivalent local draft.

### Polling
Runs immediately, then every N ms, only while the screen is visible; runs again when it becomes visible.

| What | Endpoint | Interval |
|---|---|---|
| Unread message badge | `GET /chats/unread-count` | 15 s |
| Notifications | `GET /notifications` | 30 s |
| Conversation list | `GET /chats` | 10 s |
| Open chat thread | `GET /chats/:id` | 4 s |
| Interviews | `GET /interviews` | 30 s |
| Tasks | `GET /tasks` | 30 s |

### Modals
- Bottom sheet on mobile, centred card on wider screens. Backdrop tap closes the modal (except onboarding steps). Page scroll is locked while a modal is open.

### App shell (Home, Messages, Interviews, Tasks, Settings)
**Top header, 64 px**, left to right: logo; desktop nav; on the right: theme toggle, notification bell, avatar button (account menu).

**Candidate nav items:** Home `/candidate` (house icon), Messages `/messages` (chat icon, unread badge), Tasks `/tasks` (clipboard icon), Interviews `/interviews` (calendar-clock icon). Badge shows a number, or "9+" above 9.

**Mobile bottom nav:** floating rounded bar, 4 equal columns, icon + 10 px label, active icon in the brand colour, badge on Messages. Page content has 96 px bottom padding so the bar doesn't cover it.

**Account menu:** header with avatar, name, email. Items: "Account settings" → `/settings`; "Edit profile" → `/candidate/onboarding?edit`; "Admin" (only if `isAdmin`); "Log out".

### Notification bell
- **Button:** bell icon that wiggles when the unread count changes; red badge with the count ("9+" above 9).
- **Panel:** full width on phones (below the header), 384 px dropdown on larger screens. Opening it reloads the list.
- **Panel header:** "Notifications", plus **"Mark all read"** (only when there are unread items) → `POST /notifications/read-all`.
- **List:** the 30 newest from `GET /notifications` → `{unread, notifications:[{id,type,title,body,link,at,read}]}`.
- **Row:** type icon (highlighted if unread), title (bold if unread), body clamped to 2 lines, relative time ("just now", "5m ago", "3h ago", "yesterday", "4d ago"). Unread rows have a tinted background and a dot.
- **Tap a row:** if unread → `POST /notifications/:id/read` (update the UI immediately), then open `link`.
- **Empty state:** illustration `no-notifications`, text "No notifications yet".

**Icons by type:** shortlisted = sparkles, message = chat bubble, interview = calendar-clock, hired = party popper, verified = badge-check, alert = bell-ring, task = clipboard.

**Notifications a candidate receives:**

| Trigger | Title | Body | Link |
|---|---|---|---|
| Shortlisted | "A company shortlisted you!" | "For a {job} role. You'll see who it is as soon as they message you or send a task or interview invite." | `/candidate` |
| Message | "New message from {Company}" | First 120 characters of the message | `/messages?with={companyId}` |
| Interview invite | "{Company} invited you to an interview" | "Pick a time that works for you: … (IST)" | `/interviews` |
| Interview cancelled by company | "{Company} cancelled the interview" | The reason, or "You can agree on a new time in chat." | `/messages?with={companyId}` |
| Task sent | "{Company} sent you a task" | — | `/tasks` |
| Task deadline changed | "New deadline for "{title}"" | — | `/tasks` |
| Task cancelled | ""{title}" was cancelled" | — | `/tasks` |
| Hired | "Congratulations! {Company} selected you 🎉" | — | `/messages?with={companyId}` |

Only one unread "message" notification exists per conversation at a time. Most notifications are also emailed.

### Shared input components
- **Field:** label 11 px uppercase, letter-spaced; error text (danger colour) under the input; hint shown only when there is no error.
- **Select:** first option "Select" acts as the placeholder.
- **ChipSelect:** single choice. **MultiChipSelect:** toggle chips.
- **Autocomplete:** free text allowed; suggestion list (max 10) opens on focus or typing; closes when the value exactly matches an option; matched word prefixes in bold.
- **Search ranking** (used by every suggestion list): exact (4) > starts-with (3) > every typed word starts a word (2) > contains, or a loose typo match (1). The loose match needs ≥3 letters, the same first letter, and the letters in order. Ties keep list order (most popular first).
- **LocationInput:** suggestions from `LOCATIONS` (major cities, other cities, Indian states, "Remote") with a map-pin icon. Shows up to 7 cities and up to 3 states; strict prefix matches first, looser matches only if there are none (typing "j" shows Jaipur, Jodhpur, Jabalpur, …, Jharkhand, Jammu and Kashmir).
- **TagInput (chips):** suggestions from `SKILLS`, skipping tags already added. Enter adds the highlighted suggestion (or the typed text); a comma adds exactly what was typed; leaving the field adds pending text; Backspace on an empty input removes the last chip. Case-insensitive de-duplication; if the text matches an option, the option's spelling is used ("react" → "React"). Each chip has an ×. Placeholder becomes "Add more…" once there are tags. The server keeps at most 30 items, each trimmed to 40 characters (preferred cities: max 10).
- **Lists** in `shared/taxonomy.js`: `ROLES` (job titles), `SKILLS`, `DEGREES`, `CITIES`, `STATES`, `LOCATIONS`.
- **Avatar:** image, or 2-letter initials on a gradient. Company avatars are rounded squares; logos shown "contain" on white. Sizes: 32 / 40 / 48 / 56 / 96 px.
- **Verified badge:** filled badge-check icon, tooltip "Verified company".
- **Stage pill (candidate view):**

| Stage | Label shown to the candidate |
|---|---|
| shortlisted | Shortlisted |
| contacted | Contacted |
| task | Task sent |
| interview | Interview |
| hired | "Selected 🎉" |
| rejected | shown as "Closed" |
| closed | Closed |

---

## B1. Landing page `/`
- Visitors only (signed-in users are redirected). Title "Swipe Hire – Best Hiring Platform & Job App in India"; FAQ structured data. Sections fade in on scroll.

**Sections, top to bottom:**
1. **Floating header** (sticky rounded bar 12–16 px from the top): logo; anchor links (large screens): How it works, For companies, For job seekers, Pricing, FAQ; theme toggle; "Log in" → `/auth?mode=login`; "Get started" → `/auth` (button with a logo tile that slides across on hover).
2. **Hero:** pill "The swipe-to-hire platform for India"; heading "The best way to hire **is a swipe.**"; paragraph "Swipe Hire is the hiring platform where companies swipe through resumes and 15-second intro videos to shortlist the right people in minutes, and job seekers find the best job opportunities without sending a hundred applications."; buttons "I'm hiring" → `/auth?role=company` and "I want a job" → `/auth`; ticks "Free for job seekers", "Free swipes for companies", "Verified companies"; art `hero-swipe`.
3. **How it works** (`#how-it-works`): "How Swipe Hire works" / "Three steps from profile to interview. No long forms, no inbox full of PDFs."; art `how-it-works`; three cards:
   1. "Create your profile" – "Candidates upload a resume (we fill the form from it) and record a 15-second intro video."
   2. "Companies swipe" – "Recruiters see each candidate as a card with resume, video and match score. Right = shortlist, left = pass."
   3. "Chat, task, interview" – "Shortlisted candidates get messages, take-home tasks and interview invites in one place."
4. **For companies:** "A faster hiring platform for growing teams"; art `for-companies`; six cards: Swipe, don't sift / Match score / Salary fit built in / Tasks with deadlines / Interviews in a click / Hire as a team.
5. **For job seekers:** "Find the best job opportunities without endless applications"; art `shortlisted`; six items: "One profile, auto-filled from your resume", "A 15-second intro video that shows who you are", "Set your salary range, and mark it negotiable if you like", "Your phone and email are shared only after a company shortlists you", "Age and gender are never shown to companies", "Chat, tasks and interviews with the companies that want you".
6. **Pricing:** data from `GET /payment/plans` (public). Job seekers card: "Free", "Forever, for every candidate", three perks, "Create my profile" → `/auth`. Companies card: "Companies · {plan.name}", "₹{price} for {swipes} swipes", "Start with N free swipes · no subscription", perks, "Start hiring". Fallback if the API fails: Starter, ₹399, 150 swipes.
7. **FAQ:** six expandable questions.
8. **CTA banner:** art `cta-banner`, "Right swipe, **right job.**", buttons "Start hiring" / "Find a job".
9. **Footer:** logo with tagline, "© {year} Swipe Hire. Made in India.", links.

(The Android app does not need the marketing landing page; it can open on a short welcome screen with "I'm hiring" / "I want a job" and "Log in".)

## B2. Auth `/auth`
- **Query:** `?mode=login` opens the login tab; `?role=company` preselects the company role.
- **Card:** tabs "Create account" / "Log in" (switching clears errors). Heading "Join Swipe Hire" / "Welcome back"; sub-text "It takes less than 2 minutes." / "Log in to continue where you left off."
- **Register-only:** role cards "I want a job / Get discovered by companies" (default) and "I'm hiring / Swipe through candidates"; name: label "Full name" (or "Your name" for company), placeholder "Riya Sharma".
- **Common:** email: label "Email" (or "Work email" when registering a company), placeholder "you@example.com"; password: placeholder "At least 6 characters", eye button to show / hide.
- **Validation:** "Please enter your name"; email regex `^[^\s@]+@[^\s@]+\.[^\s@]+$` → "Please enter a valid email"; password under 6 → "At least 6 characters".
- **Submit:** register `POST /auth/register {name,email,password,role}` (server error e.g. "An account with this email already exists"); login `POST /auth/login {email,password}` (wrong details → "Incorrect email or password").
- **After success:** toast "Account created!" or "Welcome back, {first name}!", then go to the home path (a new account goes to verify email).

## B3. Verify email `/verify-email`
- **On open:** `POST /auth/email/send` automatically → `{sentTo, retryIn, devCode?}`, or `{verified:true}` (then go home).
- **Card:** mail icon, "Verify your email", "We sent a 6-digit code to **{email}**. It expires in 15 minutes." (before that: "Sending you a code…"; on failure the error in danger colour).
- **Code input:** digits only, max 6, centred, letter-spaced, placeholder "••••••", autofocus, one-time-code autofill. Submits automatically at 6 digits; button "Verify email". Fewer than 6 digits: "Enter the 6-digit code from the email".
- **Verify:** `POST /auth/email/verify {code}`. On error show the message, clear and refocus the input. Server errors: "Wrong code, please check and try again"; "This code has expired. Tap "Send a new code"."; "Too many wrong attempts. Tap "Send a new code"."; "Too many wrong attempts today. Please try again tomorrow.". Success: toast "Email verified!", go home.
- **Testing mode:** when `devCode` is present show "Testing mode: your code is **123456**".
- **Resend:** "Didn't get it? Check your spam folder, or **send a new code**"; disabled while counting down "send a new code in {n}s" (60 s).
- **Wrong email:** "Wrong email ({email})? **Log out and sign up again**" → logout.

## B4. Join `/join?token=` (recruiter invite)
- **Load:** `GET /auth/invite/:token` → `{email, companyName}`.
- **Invalid:** "Invite not valid" + "This invite link is invalid or has expired. Ask your team for a new one.", button "Go to login".
- **Form:** "Join {companyName}", "as a recruiter · {email}"; "Your name" (placeholder "Your full name"); "Choose a password" (placeholder "At least 6 characters"). Errors: "Please enter your name" / "Password must be at least 6 characters".
- **Submit:** `POST /auth/accept-invite {token,name,password}` → toast "Welcome to {company}!" → home path.

## B5. Not found
- Logo, art `not-found`, "This page swiped left", "The link may be old or mistyped.", button "Go to home".

---

## B6. Candidate onboarding `/candidate/onboarding` (and `?edit`)

### Shell
- Header: logo, theme toggle, then **Log out** (normal) or **Cancel ×** (edit mode → home, clears drafts). Below: "Welcome, {first name}".
- Steps sit in a modal that cannot be dismissed, showing "Step N of 4", "{25/50/75/100}%", a progress bar, the step title and subtitle. Steps slide (direction follows forward / back). Sticky footer.

| # | Title | Subtitle |
|---|---|---|
| 0 | "Tell us about yourself" | "Basic and education details" |
| 1 | "Your work & skills" | "This is what companies match you on" |
| 2 | "Upload your resume" | "Companies double-tap your card to read it" |
| 3 | "Record a quick intro" | "5–15 seconds: your name, your role and what makes you great" |

**Starting step:** a saved draft on step 0 or 1 → that step; edit mode → step 0; otherwise by `profile.step`: 0 → details, 1 → resume, 2 → video. The form starts from the profile's values, overwritten by draft values.

### Step 0 – Details
**Resume auto-fill box** (top; only when not editing and there is no resume yet):
- "**Save time: fill this from your resume**" / "Upload your PDF resume and we'll fill in your skills, college, experience, last company and more."; button "Upload resume & auto-fill" (PDF picker).
- Client checks: "Please choose a PDF file"; over 5 MB → "Your PDF must be under 5 MB".
- Upload `POST /candidate/resume/autofill` (multipart `resume`), progress "Uploading… N%", then "Reading your resume…". Response `{fields, profile}`.
- Fills only empty fields: phone, skills (up to 15), degree, qualification, college, graduationYear, headline, location, experienceYears, currentCompany, currentPost.
- Toasts: "Filled N field(s) from your resume. Please check them." or "Resume saved. We couldn't read new details from it, please fill the form."
- Afterwards the box becomes a green note "Resume uploaded · N fields filled for you. You won't need to upload it again." The resume is saved on the server, so the resume step is already done.

**Fields** (2 columns on wide screens, 1 on phones):

| Label | Type / placeholder | Required | Validation |
|---|---|---|---|
| Phone number | tel, "98765 43210" | yes | `^[+\d][\d\s-]{8,15}$` → "Enter a valid phone number" (server: `^\+?[\d\s-]{10,16}$`, "Please enter a valid phone number") |
| Age | number 16–75, "24" | yes | "Enter your age" / "Age must be between 16 and 75" |
| Gender | chips: Male, Female, Other | yes | "Select your gender" |
| Current city | LocationInput, "Jaipur" | yes | "Enter your city" |
| Highest qualification | select: 10th, 12th, Diploma, Graduate, Post Graduate, PhD | yes | "Select your qualification" |
| Degree / course | Autocomplete (DEGREES), "B.Tech (CSE)" | yes | "Enter your degree" |
| College / university | text, "Optional" | no | — |
| Passing year | number, "2023" | no | 1960–2040 → "Enter a year like 2023" |

Footer "Continue →": validates locally and moves to step 1 (nothing sent yet).

### Step 1 – Work and skills
| Label | Input | Required | Validation / hint |
|---|---|---|---|
| Role you are looking for | Autocomplete (ROLES), "e.g. Web Developer, Sales Executive" | yes | "Enter the role you are looking for" |
| Your skills | TagInput (SKILLS), "React, Excel, Communication…"; hint "Enter adds the highlighted skill · type a comma to add exactly what you typed" | yes (≥1) | "Add at least one skill" |
| Experience (years) | number, min 0, step 0.5, "0 if fresher" | yes | "Enter your experience (0 if fresher)" / "Enter years between 0 and 50" |
| Notice period | select: Immediate, 15 days, 30 days, 60 days, 90 days | no | — |
| Current / last company | text, "Optional" | no | — |
| Current / last post | Autocomplete (ROLES), "Optional" | no | — |
| Current salary (LPA) | number, step 0.1, "e.g. 4.5" | no | "Enter a valid salary" |
| Expected salary (LPA) → Minimum | number, "e.g. 6" | yes | "Enter the minimum salary you expect" / "Enter a valid salary" |
| Expected salary (LPA) → Maximum | number, "e.g. 8"; hint "Optional" | no | "Enter a valid salary" / "Should be more than the minimum" |
| My salary is negotiable | checkbox | no | live sub-text, see below |
| Preferred work mode (optional) | multi-chips On-site / Hybrid / Remote (`onsite`, `hybrid`, `remote`) | no | — |
| Job type (optional) | multi-chips Full-time / Part-time / Internship / Contract (`full-time`, `part-time`, `internship`, `contract`) | no | — |
| About you | textarea, max 600, "I build fast, accessible web apps…"; hint "2–3 lines that make you stand out (optional)" | no | — |

- **Negotiable sub-text:** on → "Companies can shortlist you even if their budget is below your minimum."; off → "Only companies whose budget reaches your minimum can shortlist you."
- **Salary rules:** values are in LPA (lakh per year). A value ≥ 1000 is treated as a yearly rupee amount and converted (÷100000); the hint then shows "= ₹4.5 LPA (₹4,50,000 per year)", otherwise "In lakh per year, e.g. 4.5". Above 1000 LPA or not a number is invalid.
- **Footer:** "←" (back to step 0) and "Save & continue →" → `PUT /candidate/profile` with the whole form. The server sets the step to at least 1 (or 2 if a resume already exists) and returns `{profile}`. If the error has a `field`, show it under that field (jumping back to step 0 if needed); otherwise under the form.
- **Server text limits:** headline 80, phone 20, location 80, degree 80, college 120, company / post 80, notice 30, about 600, gender 30, qualification 40.
- **Server required fields** ("X is required"): Phone number, Age, Gender, Location, Qualification, Degree, Job title / role, At least one skill, Experience, Minimum expected salary.

### Step 2 – Resume
- **Drop zone / picker:** upload icon, "Drop your resume here" (or "Choose a different PDF" once a file exists), "or click to browse · 1 PDF only · max 5 MB". Several files dropped: "Only one resume is allowed. Please drop a single PDF."
- **Client errors:** "Please choose a PDF file", "Your PDF must be under 5 MB".
- **Preview card:** first PDF page as a 128×176 thumbnail; file name (or "Current resume"); "{KB} KB · ready to upload" or "Already uploaded"; "Keep current resume" when replacing. Failed preview: "Could not load resume".
- **Footer:** "←" and the main button "Upload & continue" (or "Continue" when one already exists and none is chosen). Nothing chosen and nothing existing: "Please choose your resume". Upload `POST /candidate/resume` (multipart `resume`) with a progress bar; the server sets step 2; go to step 3.
- **Server errors:** "Resume must be a PDF file", "This file is not a valid PDF", "Please complete the previous step first".

### Step 3 – Intro video
- **Rules:** minimum **5 s**, maximum **15 s**; file up to **40 MB**; MP4, WebM or MOV.
- **Mode switch:** "Record now" (default) / "Upload video" (hidden while recording).

**Record mode:**
- Camera box 3:4. **Idle:** art `record-video`, "Say your name, your role and why a company should hire you.", button "Turn on camera".
- Camera: front camera, about 720×960, with audio. Denied: "We could not access your camera or microphone. Please allow access, or upload a video instead."
- **Ready:** mirrored preview; big red record button inside a progress ring; caption "Tap to start · 5–15 seconds".
- **Countdown:** 3-2-1 (0.8 s each), then recording starts.
- **Recording:** top progress bar with a marker at 5 s; pill with a blinking red dot and "N / 15 sec"; the ring fills over 15 s.
- **Stopping:** before 5 s the stop button is disabled and pulses ("Keep talking… N sec more"); after 5 s a square stop icon ("Tap to stop · stops by itself at 15 sec"); stops automatically at 15 s. Clip shorter than 4.5 s: "Please record at least 5 seconds."
- Leaving the step while recording stops the camera and discards the clip.

**Upload mode:**
- "Choose a video", "5–15 seconds · MP4 / WebM / MOV · max 40 MB".
- Errors: "Please choose a video file", "Please choose an MP4, WebM or MOV video", "Video must be under 40 MB", and outside 4.5–15.5 s "Your video is N seconds. Please upload a 5–15 second video." (accepted anyway if the duration can't be read).

**Clip preview:** player with controls, "{x.x} seconds", **Retake** button. **Existing video:** collapsible "Your current intro video" with a player.

**Footer:** "←" (disabled while uploading / recording); main button "Upload & finish" (new clip) or "Keep current & finish". With nothing: "Please record or upload your intro video". Upload `POST /candidate/video` (multipart `video`) with progress; the server sets step 3 and the profile goes live. Server errors: "Video must be MP4, WebM or MOV", "This file is not a valid video".

### Done screen
- Confetti, art `profile-complete`, "You're live!" (or "Profile updated!" when editing), "Companies can now discover your profile. We'll show you here when someone shortlists you.", button "Go to my dashboard" → `/candidate`.

---

## B7. Candidate home `/candidate`
- **Data:** `GET /candidate/stats` → `{shortlistedBy[], hiddenCount, viewedCount, wishlistedCount}` (on failure use `{shortlistedBy:[]}`).
- **Greeting:** pulsing dot + "Your profile is live" (green) or "Your profile is hidden" (grey, from `openToWork`); "Hi {firstName} 👋"; "Companies are swiping through profiles like yours right now." or "Turn on "Open to work" when you are ready for new offers."
- **Stats** (three cards in a row, "–" while loading): "Profile views" (number of swipes, left or right, on this candidate), "Wishlisted", "Shortlisted" (`shortlistedBy.length + hiddenCount`).
- **Layout:** desktop main column + 400 px side column; mobile stacks them, side column last.

### Main column
**1. Activity ring** (only when open to work):
- 15 days counted from `activeAt` (or `updatedAt`); the ring fills with the brand gradient.
- **Not full:** centre "{days left}" / "day(s) left" (min 1); title "You're at the top of company feeds"; text "This ring fills up over 15 days. When it's full, it becomes an **I'm active** button: tap it to stay on top. If you don't, companies will see your profile much lower."
- **Full** (≥ 15 days): amber card; centre button "↻ I'm active" → `POST /candidate/active` → toast "You're back at the top of company feeds!"; title "Your profile has moved down"; text "You haven't confirmed you're still looking for 15+ days, so companies now see you much lower. Tap **I'm active** to go back to the top."

**2. Profile strength:**
- Score ring with "{score}%", header "PROFILE STRENGTH" and a level: ≥ 90 "All-star" (`#34d399`), ≥ 70 "Strong" (`#38bdf8`), ≥ 45 "Good start" (`#fbbf24`), below 45 "Needs work" (`#ff4d6d`).
- Sub-text "Complete profiles get shortlisted more often." or "Your profile has everything companies look for."

| Item | Points | Done when | Opens |
|---|---|---|---|
| Intro video | 20 | videoUrl set | edit profile |
| Resume | 15 | resumeUrl set | edit profile |
| At least 5 skills | 15 | ≥ 5 skills | edit profile |
| A few lines about you | 10 | about ≥ 30 characters | edit profile |
| Current or last company & role | 10 | experienceYears = 0, or company and post set | edit profile |
| Job title you want | 5 | headline set | edit profile |
| College & passing year | 5 | both set | edit profile |
| Notice period | 5 | set | edit profile |
| Expected salary | 5 | set | edit profile |
| Work mode & job type | 5 | both non-empty | job preferences section |
| Cities you would work in | 5 | ≥ 1 | job preferences section |

Shows the top 4 missing items (highest points first): dashed circle, label, "+N%", chevron. Nothing missing: "✓ Nothing left to add."

**3. "Companies that shortlisted you":**
- **Hidden companies:** if `hiddenCount > 0`, a banner with the number and "1 company shortlisted you" / "N companies shortlisted you", plus "You'll see who they are as soon as they message you or send a task or interview invite." (companies that only swiped right, with no message, task or interview yet).
- **Empty:** art `waiting-shortlist`, "No shortlists yet", "A great intro video and a complete skill list help you get noticed faster."
- **Rows** (companies that contacted the candidate): company logo, name + verified badge, "{job title} · {location}", stage pill and a date ("Today", "Yesterday", "N days ago"). Tap → company details modal; chat icon → `/messages?with={companyId}`.
- Footer note: "These companies can see your email and phone number and may contact you directly."

**4. Open to work switch:** on → green "Open to work" / "Companies can discover your profile."; off → "Not looking right now" / "Your profile is hidden from companies.". Toggle `PUT /candidate/preferences {openToWork}` → toast "Preferences saved".

**5. Job preferences** (`#preferences`): "Work mode" (On-site / Hybrid / Remote), "Job type" (Full-time / Part-time / Internship / Contract), "Cities you'd work in" (TagInput with LOCATIONS, placeholder "Jaipur, Pune…", max 10). "Save preferences" appears only when something changed → `PUT /candidate/preferences {workModes, jobTypes, preferredLocations}` → toast "Preferences saved".

### Side column (my profile card)
- Avatar (tap → Settings, "Change photo"), name, headline, "Edit profile" → onboarding in edit mode.
- Intro video player.
- "View my resume" → resume viewer: full-height modal "{name}'s resume", "Scroll to read all pages", "Open" (new tab) and ×; every PDF page rendered.
- **Candidate details:** skills chips; "DETAILS" 2-column tiles (empty values hidden), in order: Experience ("Fresher" or "N years"), Expected salary ("₹6–8 LPA · Negotiable" or "₹6 LPA"), Current salary, Notice period, Current / last company, Current / last role, Qualification, Degree, College, Graduation year, Age, Gender, Location, Open to cities, Work mode, Job type; then "ABOUT".

### What companies see
- Card fields: headline, location, qualification, degree, college, graduationYear, skills, experienceYears, currentCompany, currentPost, currentSalary, expectedSalary (+max), salaryNegotiable, noticePeriod, about, resumeUrl, videoUrl, workModes, jobTypes, preferredLocations, plus name and avatar.
- **Never shown to companies:** age and gender.
- **Email and phone:** only for companies that shortlisted (right-swiped) the candidate.
- Candidates with Open to work off are not in the feed. Profiles not confirmed active for more than 15 days rank after active ones. New candidates (first 7 days) get +10 on the match score.

### Company details modal (candidate → company)
- `GET /candidate/companies/:companyId`; allowed only once that company has shortlisted and contacted the candidate (otherwise 403 "This company has not contacted you yet").
- Header: logo, name + verified badge, "{industry} · {location}".
- "SHORTLISTED YOU FOR": a card per role with title, "{jobLocation} · {workMode} · {job type} · ₹{min}–{max} LPA", description.
- "ABOUT"; rows: Website, LinkedIn (open externally), Email (mail app), Phone (dialer), Address, Size ("{n} employees"), Founded. No details: "This company hasn't added more details yet."
- Footer: "Message {Company}" → chat.

---

## B8. Messages `/messages` (`?with={otherUserId}`)
- Header "Messages" and a **"New message"** button. On phones show either the list or the open chat.

**Conversation list** (`GET /chats`, every 10 s):
- Only conversations with at least one message; candidates only see companies that contacted them.
- Row: avatar; name (bold if unread) + verified badge; preview "You: …" or the text (else the subtitle); relative time ("new" if none); unread count badge. Tapping opens the chat and clears its unread count.
- Empty: art `no-messages`, "No conversations yet", "When a company messages you, the chat shows up here." Desktop with nothing selected: "Choose a conversation".

**Chat** (`GET /chats/:otherId`, every 4 s):
- Returns `{with:{id,name,subtitle,verified,avatarUrl}, messages:[{id,text,mine,at,read}]}`, up to 200 messages; opening it marks incoming messages as read.
- Header: back arrow (phones), avatar, name, verified badge, "Tap for company details" (opens the company modal).
- Body: day separators ("Wed, 15 Oct"); own messages on the right (brand colour), theirs on the left (grey), max 80% width, line breaks kept; time ("3:45 pm"); own messages show ✓ (sent) or ✓✓ (read). Scroll to the newest message when one arrives. Empty: "No messages yet. Say hello!"
- Composer: growing text box (max ~5 lines), placeholder "Type a message…", max 2000 characters; send button disabled when empty or sending. Send `POST /chats/:otherId {text}` → append and refresh the list. Errors: "Message cannot be empty", "Message is too long (max 2000 characters)", "This company has not contacted you yet", rate limit message.

**New message modal:** "New message" / "Companies that contacted you"; search "Search by name or role"; data `GET /chats/contacts` → `[{id,name,subtitle,verified,avatarUrl,stage,hasChat}]`; tap a row to open that chat. Empty: "No company has contacted you yet."; no match: "No one matches "{q}"."

## B9. Interviews `/interviews`
- Header "Interviews", "Companies that want to meet you will appear here."
- Data `GET /interviews` (every 30 s): `{id, with:{id,name,subtitle,verified,avatarUrl}, jobTitle, slots[], chosenSlot, durationMins, mode, meetingLink (only when confirmed), location, note, status, createdAt}`.
- Empty: art `no-interviews`, "No interviews yet."
- **Groups** ("{TITLE} · {count}"): "Needs your reply" (status `proposed`); "Upcoming" (confirmed, future, soonest first); "Past & cancelled".
- **Card:** status tile (green confirmed, grey cancelled, amber otherwise); company + badge; "For {jobTitle}"; status pill "Pick a time" / "Confirmed" / "Done" / "Cancelled"; chips: mode ("Video call" / "Phone call" / "In person"), "{n} min" (15/30/45/60), location; note in quotes.
- **Confirmed:** large date and time ("Wed, 15 Oct, 3:30 pm"). If not past: **"Join video call"** (opens `meetingLink`, a Jitsi room `https://meet.jit.si/SwipeHire-<hex>` created automatically for video interviews unless the company gave its own link) and **"Add to calendar"** (title "Interview: {company}", start / end, note and join link, location or link).
- **Proposed:** "Choose a time that suits you" and up to 3 slot buttons (past slots disabled). Tap → `POST /interviews/:id/accept {slot}` → toast "Interview confirmed! Added to your interviews.". Errors: "This interview is no longer open", "Please choose one of the offered times", "That time has already passed, please ask for a new time in chat".
- **Links** (not when cancelled or past): "Ask for another time" → chat; "Cancel interview" → modal "Cancel interview with {name}?" / "They will be notified. You can agree on a new time in chat.", "Reason (optional)" (max 300), buttons "Keep it" / "Cancel interview" → `POST /interviews/:id/cancel {reason}` → toast "Interview cancelled".

## B10. Tasks `/tasks` (candidate view)
- Header "Tasks", "Assignments from companies. Submit your live link and GitHub repo before the deadline."
- Data `GET /tasks` (every 30 s; candidates never get cancelled tasks): `{id, with:{id,name,verified,avatarUrl}, jobTitle, title, description, briefUrl, dueAt, status, submission?{liveUrl,repoUrl,note,at}, createdAt}`. Status `assigned`, `submitted`, `overdue` (assigned and past the deadline, computed by the server) or `cancelled`.
- Empty: art `no-jobs`, "No tasks yet. When a company sends you one, it shows up here."
- Filter chips with counts: All / Waiting / Submitted / Deadline passed ("Nothing here." when empty).
- **Task card:** company avatar, name + badge, "For {jobTitle}", chat icon; title and status pill ("Waiting" amber, "Submitted" green, "Deadline passed" brand colour, "Cancelled"); due line "Due {Wed, 15 Oct, 6:00 pm} · {2 days 4 h left / 5 h left / 45 min left}" (bold when only minutes are left); "Show task details" / "Hide details" (open by default for assigned tasks) with the description and a "Reference" link (briefUrl); submission block "YOUR SUBMISSION · {date}" with "Live" and "GitHub" links and the note.
- **Submit form** (assigned or submitted, before the deadline): "Live link" (placeholder "my-app.vercel.app"), "GitHub repo" ("github.com/you/project"), "Note for the company" (optional, max 1000, "Login: demo@test.com / demo123"). At least one link: "Add your live link or GitHub repo link". Server: https added if missing; http / https only; max 300 characters; the repo must be on github.com ("The repo link must be a github.com link"); otherwise "Please enter a valid live link" / "…GitHub repo link".
- Button "Submit task" or "Update submission" → `POST /tasks/:id/submit {liveUrl, repoUrl, note}` → toast "Task submitted! The company has been notified." or "Submission updated". Re-submitting is allowed until the deadline.
- **Overdue:** "The deadline has passed. Message the company if you need more time." (server: "The deadline for this task has passed").

## B11. Settings `/settings`
- Header "Account settings", "Your photo, name and login details."
- **Photo:** 96 px avatar with a camera overlay; "Profile photo", "JPG, PNG or WebP · up to 3 MB"; "Upload" / "Change" and "Remove". Errors "Please choose a JPG, PNG or WebP image", "Image must be under 3 MB". Upload `POST /account/avatar` (multipart `image`) → "Photo updated"; remove `DELETE /account/avatar` → "Photo removed".
- **Full name:** max 80; empty → "Please enter your name". **Email:** read-only, "Your login email can't be changed". Candidate note: "Phone, skills, resume and video are on **Edit profile**."
- "Save changes" (only when changed) → `PUT /account {name}` → "Saved".
- **Change password:** "Current password" ("Enter your current password"), "New password" ("At least 6 characters"), "Confirm new password" ("Passwords do not match"). "Update password" → `PUT /account/password {current, next}`; wrong current → "Your current password is not correct" (field `current`); success → fields cleared, toast "Password changed. Other devices have been logged out." (send `X-Auth-Mode: token` to get the new token).
- "Used Swipe Hire on a shared or lost device?" → **"Log out of all devices"** → confirm "Log out of Swipe Hire on all devices, including this one?" → `POST /auth/logout-all` → logout → "Logged out of all devices".

## B12. Illustration names (website)
- Candidate side: `offline`, `not-found`, `record-video`, `profile-complete`, `waiting-shortlist`, `no-notifications`, `no-messages`, `no-interviews`, `no-jobs` (Tasks page).
- Landing: `hero-swipe`, `how-it-works`, `for-companies`, `shortlisted`, `cta-banner`.
- Company side: `empty-pipeline`, `empty-wishlist`, `no-candidates`, `out-of-swipes`, `verified`.
- The client has asked to replace cartoon illustrations with a more professional look; in the app prefer simple line icons for empty states.

## B13. Keyboard behaviour on the website (adapt for touch)
- Chat: Enter sends, Shift+Enter new line. Suggestion lists: ↑ / ↓ / Enter / Escape. TagInput: Enter, comma, Backspace. Escape closes the notification panel and the top modal. The email code submits automatically at 6 digits.

---

# Part C. Company (recruiter) and admin screens

Source: `client/src` (company pages and components); server rules from `server/src`.

---

## 0. Global rules

### Routes and guards (`App.jsx`)

**Guard order:**
1. While auth is loading, show a full-screen spinner.
2. No user → `/auth`.
3. `emailVerified === false` → `/verify-email`.
4. Wrong role → the user's home path.
5. `admin` route and not admin → home path.
6. `onboarded` route and not onboarded → home path.

**Company home path:** `profile.completed` ? `/company/swipe` : `/company/onboarding`.

**Company routes:**

| Route | Guard |
|---|---|
| `/company/onboarding` | role=company |
| `/company/swipe` | company + onboarded |
| `/company/wishlist` | company + onboarded |
| `/company/shortlisted` | company + onboarded |
| `/company/plans` | company + onboarded |
| `/company/jobs` | company + onboarded |
| `/company/profile` | company + onboarded |
| `/company/team` | company + onboarded |
| `/company/verify` | company + onboarded |
| `/settings`, `/messages`, `/interviews`, `/tasks` | any role, onboarded |
| `/admin` | admin |
| `/join?token=` | guests only |

**Offline screen** (any page except `/` and `/auth` when the API can't be reached):
- Illustration `offline`.
- Heading "Can't reach Swipe Hire".
- Text "Check your internet connection and try again."
- Button "Try again" (calls `GET /auth/me` again).

**Pages:** each is lazy-loaded with a spinner fallback and a 0.22s fade between pages.

**Session:** a login cookie (httpOnly). The axios base is `/api`, with header `X-Requested-With: XMLHttpRequest`. `GET /auth/me` returns `{user, profile}`.
- The company `user` has `role`, `companyId`, `isOwner`, `isAdmin`, `emailVerified`, `name`, `email`, `avatarUrl`.
- The `profile` is the CompanyProfile: `companyName`, `swipesLeft`, `completed`, `verification{status, method}`, `logoUrl`, etc.

**Generic API error text:** `response.data.message`, or "Something went wrong, please try again". Some errors also carry `field` (shown under that input) or `code`.

**Salary input rule:** salaries are entered in LPA. Any value ≥ 1000 is treated as a yearly rupee amount and converted (450000 → 4.5).
- Hint under an empty salary field: "In lakh per year, e.g. 4.5".
- Hint for a large number: "= ₹4.5 LPA (₹4,50,000 per year)".

**Files:** images and PDFs come from signed URLs.

### App shell (company navigation)

**Header** (sticky, 64px high, blurred):
- Logo on the left.
- Desktop nav from `md` up, **icons only on tablet and labels from `lg`**: Swipe (`/company/swipe`), Jobs, Shortlisted, Wishlist, Messages (unread badge), Interviews, Tasks.
- On the right: **SwipeCounter**, theme toggle, NotificationBell, avatar ProfileMenu.

**Mobile bottom nav** (floating, below `md`), 5 tabs: Swipe, Jobs, Shortlisted, Messages, Interviews.
- Wishlist and Tasks are desktop-only in the nav. On phones, Wishlist is linked from the swipe screen and Tasks from the profile menu.
- The badge shows "9+" above 9.

**Unread polling:** `GET /chats/unread-count` every 15s, only while the tab is visible, and again when the tab becomes visible.

**SwipeCounter (pill button):**
- Shows a ⚡ icon and an animated number (`profile.swipesLeft`). The word "swipes" is hidden on mobile. Title "Swipes left".
- When the count is 0, the pill turns brand-red.
- Tapping it goes to `/company/plans`.

**ProfileMenu** (avatar; opens a dropdown about 320px wide; closes on outside tap):
- Header shows the avatar, user name, and companyName.
- Items:
  - Account settings → `/settings`
  - Company profile → `/company/profile`
  - Tasks → `/tasks` (mobile only)
  - Team → `/company/team`
  - "Verified company" when verified, otherwise "Get verified badge" → `/company/verify`
  - Plans & swipes → `/company/plans`
  - Admin → `/admin` (only if `isAdmin`)
  - Log out (`POST /auth/logout`, clears form drafts)

**NotificationBell:**
- Polls `GET /notifications` every 30s and also reloads when opened. The response is `{unread, notifications:[{id, type, title, body, link, read, at}]}`.
- The badge shows a count ("9+" above 9) and the bell wiggles.
- Panel: title "Notifications" and a "Mark all read" button (`POST /notifications/read-all`).
- Empty state: illustration `no-notifications`, text "No notifications yet".
- Tapping an item calls `POST /notifications/:id/read` and navigates to `n.link`.
- Icons by type: shortlisted, message, interview, hired, verified, alert, task.
- Relative time: "just now", "5m ago", "3h ago", "yesterday", "4d ago".
- On mobile the panel is full width; Esc closes it.

**Notifications a company receives:**
- `alert`: "New match for "<search>"", linking to `/company/swipe?search=<id>`.
- `verified`: approved or rejected, linking to `/company/verify`.
- `message`: "New message from <candidate>".
- Task submitted (from the candidate's submission).

### Shared components

**Modal:**
- A bottom sheet on mobile (rounded top, max height 94dvh); centred on `sm`+ (default max width `lg`).
- The backdrop click closes it. **Esc closes only the topmost modal.** Body scrolling is locked while it is open.

**Field:** an uppercase small label. The error text is red and animated under the input; the hint shows only when there is no error.

**Input:** optional left icon.

**Select:** a native select whose disabled first option is the placeholder ("Select" by default).

**Textarea:** minimum height about 96px, not resizable.

**ChipSelect:** single choice, pills, the active one has a gradient. **MultiChipSelect:** a toggle for each chip.

**Autocomplete:** free text plus a suggestion list.
- Arrow keys, Enter and Esc work through the list.
- The list closes once the text exactly equals an option.

**LocationInput:** an Autocomplete over Indian cities and states (`shared/taxonomy.js`).
- Suggests up to 7 cities and up to 3 states, prefix matches first, with a typo-tolerant fallback.
- Default placeholder "City, e.g. Jaipur".

**TagInput:**
- Enter or a comma adds a tag. Backspace on an empty input removes the last tag. Leaving the field adds whatever is typed.
- Duplicates are ignored (case-insensitive), and the list's spelling is used ("react" → "React").
- Suggestions come from SKILLS, excluding tags already added.
- Placeholder changes to "Add more…" once there are tags.

**ImageUploader:**
- Shows an XL avatar (company logo style is a rounded square) with a hover camera overlay.
- Label, then "JPG, PNG or WebP · up to 3 MB · square works best" (the last part only for company).
- Buttons: "Upload" or "Change", plus "Remove" when an image exists. A progress bar shows during upload.
- Client checks: wrong type → toast "Please choose a JPG, PNG or WebP image"; over 3 MB → "Image must be under 3 MB".
- `POST endpoint` (multipart field `image`) → toast "Logo updated". `DELETE endpoint` → "Logo removed".

**ResumeViewer** (modal, 94dvh tall, `sm:max-w-3xl`):
- Header: file icon, "<Name>'s resume", subtitle "Scroll to read all pages", an "Open" link in a new tab (the label is hidden on mobile), and a close X.
- Body: every PDF page rendered with react-pdf, up to 820px wide.
- Loading: a white page with a spinner. Error: "Could not load resume".

**Illustrations:** `/illustrations/<name>.webp` for dark and `<name>-light.webp` for light.

**Candidate card fields** (from `GET /company/feed`, wishlist and shortlisted):
- `id`, `name`, `avatarUrl`, `headline`, `location`, `qualification`, `degree`, `college`, `graduationYear`, `skills`.
- `experienceYears`, `currentCompany`, `currentPost`, `currentSalary`, `expectedSalary`, `expectedSalaryMax`, `salaryNegotiable`.
- `noticePeriod`, `about`, `resumeUrl`, `videoUrl`, `workModes`, `jobTypes`, `preferredLocations`, `matchScore`, `matchedSkills`, `wishlisted`.
- **No phone or email until shortlisted.** Age and gender are never sent to companies, even though `CandidateDetails` has rows for them.

**Match score (0–100), computed against the job:**

| Part | Points | Rule |
|---|---|---|
| Skills | 50 | Share of required skills the candidate has |
| Experience | 20 | Full if in range, otherwise 6 points lost per year outside |
| Salary | 20 | Expected ≤ max = 20; ≤ 1.2× max = 10 |
| Location | 10 | Remote job, or the locations contain each other |

The result is normalised to 100.

**MatchBadge:** "NN% match". Green at 75 or more, amber at 45 or more, grey otherwise.

**Experience label:** 0 = "Fresher", otherwise "N yr(s) exp".

**Expected salary label:** "₹6–8 LPA · Negotiable", where the range part appears only if `expectedSalaryMax > expectedSalary` and "· Negotiable" only if the candidate is open to negotiate.

**CandidateDetails** (used inside cards and modals):
1. "Intro video" (`<video controls>`, max height 440px).
2. "Skills" chips. Skills matching the job's required skills are green with a ✓.
3. "Details" grid (2 columns). Rows: Experience ("N years" or "Fresher"), Expected salary, Current salary ("₹X LPA"), Notice period, Current / last company, Current / last role, Qualification, Degree, College, Graduation year, Age, Gender, Location, Open to cities, Work mode (On-site/Hybrid/Remote), Job type. Empty rows are hidden.
4. "About" text.

---

## 1. Company onboarding: `/company/onboarding`

**Access and redirects:**
- If the profile is already completed and the URL has no `?edit`, it immediately redirects to `/company/swipe`.
- `?edit` mode shows only step 1 and saves only the company fields.

**Layout (OnboardingShell):**
- Background, Logo, theme toggle.
- Top right: "Log out" (label hidden on mobile). In edit mode it is "Cancel" instead, which clears drafts and goes home.
- Centre text: "Welcome, <first name>".
- The steps sit in a modal that is **always open and cannot be dismissed** (no X).
- Modal header: "Step N of M", "NN%", a progress bar, then the step title and subtitle. Steps slide horizontally with a blur.
- The footer sticks to the bottom.
- **Draft persistence:** answers and the current step are kept in sessionStorage (`swipehire_draft_company_<userId>[_edit]`), so a refresh keeps them. Drafts are cleared on save or logout.

### Step 1 of 2: "About your company"

Subtitle: "Candidates see this when you shortlist them".

| Field | Type | Placeholder | Required | Notes |
|---|---|---|---|---|
| Company name | text, building icon | "Acme Technologies" | Yes | Error "Enter your company name". Server max 100 chars. |
| Industry | select | "Select" | No | Options: IT / Software, E-commerce, Finance, Healthcare, Education, Manufacturing, Marketing / Media, Retail, Real Estate, Other |
| Company size | select | "Employees" | No | Options: 1–10, 11–50, 51–200, 201–1000, 1000+ |
| Location | LocationInput | "Jaipur" | Yes | Error "Enter your company location". Server max 80. |
| Website | text, globe icon | "Optional" | No | Server normalises to https. Bad value → field error "Please enter a valid web address". |
| About the company | textarea, max 600 | "What do you do? Why is it great to work with you?" | No | Hint "Optional" |

- On phones, Industry, Company size, Location and Website stack in one column; from `sm` they are in 2 columns.
- Footer button: "Continue →". It validates and moves to step 2 with no API call.
- If job location is still empty, it is pre-filled with the company location.
- In edit mode the button is "Save changes", which calls `PUT /company/profile` with only the company fields and then goes to `/company/swipe`. A server error shows in red text under the footer.

### Step 2 of 2: "Who are you hiring?"

Subtitle: "We rank candidates by how well they match this". This creates the **first job**.

| Field | Type | Placeholder | Validation and error |
|---|---|---|---|
| Role you are hiring for | Autocomplete (ROLES) | "e.g. Frontend Developer" | Required: "Enter the role you are hiring for" |
| Skills you need | TagInput | "React, JavaScript…" | Required: "Add at least one skill". Hint "Candidates with these skills are shown first · comma adds exactly what you typed" |
| Min experience (yrs) | number | "0" | 0–50, else "Enter years between 0 and 50". If above max: "Must be less than maximum" |
| Max experience (yrs) | number | "5" | 0–50 |
| Min salary (LPA) | number, step 0.1 | "3" | Invalid or over 1000 LPA: "Enter a valid salary". Above max: "Must be less than maximum". Salary hint below. |
| Max salary (LPA) | number, step 0.1 | "8" | Required: "Enter the maximum salary you can offer". Invalid: "Enter a valid salary". Salary hint below. |
| Job location | LocationInput | "Jaipur" | Optional; pre-filled from company location |
| Work mode | ChipSelect | | On-site (default) / Hybrid / Remote |

Footer buttons:
- "←" (ghost): back to step 1.
- **"Start swiping →"**: `PUT /company/profile` with all fields: `companyName`, `industry`, `website`, `companySize`, `location`, `about`, `hiringFor`, `requiredSkills`, `minExperience`, `maxExperience`, `salaryMin`, `salaryMax`, `jobLocation`, `workMode`.
  - The server creates the first Job when the company has none. Title comes from `hiringFor`; job location defaults to the company location.
  - The server sets `completed: true`.
  - If the server returns `field` = companyName or location, the form jumps back to step 1 with that error. Any other error shows in red text.

### Done screen

- Burst confetti and illustration `profile-complete`.
- Heading "You're all set!".
- Text "You have {swipesLeft ?? 5} free swipes. Swipe right to shortlist a candidate, left to pass." Free swipes come from server config `FREE_SWIPES`, default 5.
- Button "Start swiping" goes to `/company/swipe` (replace).

---

## 2. Swipe screen: `/company/swipe` (main screen)

Query params: `?job=<id>` and `?search=<savedSearchId>`.

### Layout

**Desktop (`lg`+):**
- Left sidebar (288px, sticky), card 1 "**Hiring for**" with a sliders icon linking to `/company/jobs` (title "Edit job"). Rows:
  - Role
  - Experience ("min–max yrs", where max can be ∞)
  - Budget ("₹min–max LPA")
  - Location ("jobLocation · workMode")
  - Required skill chips
- Card 2 "**Shortcuts**": Pass ←, Shortlist →, Open resume = double-click.
- Hidden below `lg`.

**Centre column (max width 430px), top to bottom:**

1. **Job selector "Hiring for"** (only if there are open jobs):
   - A select with a briefcase icon. Options read "Title · jobLocation", **open jobs only**.
   - Next to it, a ghost button "+ Job" (the label is hidden on mobile) linking to `/company/jobs` (title "Manage jobs").
   - Which job is chosen: `?job` first, then the last used job (localStorage `swipehire_job_<companyId>`), then the first open job.
   - Changing the job saves it, resets the feed, and resets the undo count.

2. **Filter row:**
   - Left: "Filters" ghost button with a count badge of active filters; the border is highlighted when filters are on.
   - Right: "Clear filters" when filters are active, otherwise a "♡ Wishlist" link to `/company/wishlist`. This is the mobile entry point for Wishlist.

3. **Saved search chips:** a horizontal scroll of up to 6 chips, each a bookmark icon plus the name. Tapping one applies its filters.

4. **Card stack** (minimum height 60dvh):
   - Up to 3 cards are visible. Cards behind are scaled (1 − 0.05 × depth) and moved down by 16px each; depth over 2 is hidden.
   - The top card is in normal page flow, so **the whole page scrolls through the resume, video and details**.

5. **Action bar:** sticky above the mobile nav (`bottom-24`, or `bottom-6` on desktop), in a pill. Buttons in order:

| Button | Size | Colour | Label / tooltip | Disabled when |
|---|---|---|---|---|
| ↺ Undo | 48px | amber | "Undo last swipe" | Nothing undoable, or undo in progress |
| ✕ Pass | 64px | red | "Pass" | No card |
| ♡ Wishlist | 48px | violet, filled when wishlisted | "Add to wishlist" / "Remove from wishlist" | No card |
| ✓ Shortlist | 64px | green, BadgeCheck icon | "Shortlist" | No card |

### Swipe card (`SwipeCard`)

**Sticky header** (sticks at `top-16`, below the app header):
- Large avatar, name (2xl, extra-bold), headline.
- **Heart button** (44px circle) at top right toggles the wishlist; filled red when wishlisted.
- Chips row: MatchBadge, 📍 location, 💼 "N yrs exp"/"Fresher", ₹ expected salary label.
- Drag stamps: **"SHORTLIST"** (green border, rotated −12°, on the left) and **"PASS"** (red, rotated 12°, on the right). Their opacity follows how far the card is dragged. The card is also tinted green (right) or red (left), up to 22% opacity.

**Body:**
- **Resume first page** on a white background, aspect ratio 1:1.3. The PDF of cards at depth 2 or less is preloaded.
- A pill at the bottom: "⤢ Double-tap to open resume".
- **Double-click on desktop or double-tap on phones** (two taps within 330ms, not while dragging) opens the ResumeViewer.
- Top card only: a bouncing hint "⌄ Scroll down for intro video & details", then CandidateDetails (video, skills, details, about).

**Gestures:**
- Horizontal drag only (direction lock, `touch-pan-y` so vertical scrolling still works). Dragging doesn't start on video, button or link elements.
- Rotation is ±9° at ±320px.
- **Commit** when |offset| > 100px, or velocity > 500 with |offset| > 40. Right is shortlist, left is pass. Otherwise the card springs back.
- The exit animation flies the card off-screen in the swipe direction (0.45s). The next card scales in from 0.8.

**Keyboard:** ArrowRight = shortlist, ArrowLeft = pass. Ignored while the resume, paywall or filters modal is open, or when focus is in an input.

### Swipe action (`swipe(dir)`)

- **If `swipesLeft <= 0`, open the paywall modal and don't swipe.**
- Otherwise it is optimistic: remove the top card, take 1 from the counter, scroll to the top. Then `POST /company/swipe {candidateId, action:'right'|'left', jobId}`.
- Response: `{swipesLeft, contact?:{email, phone}}` (contact only for right swipes). The undo count goes up by 1.
- **Right swipe success → "ShortlistFlash" overlay** (about one third down the screen, 1.8s, confetti): "✓ <FirstName> shortlisted!" and the candidate's email underneath.
- The server notifies the candidate anonymously: "A company shortlisted you!".

Errors (the counter is restored by 1 first):
- `NO_SWIPES` (402, "You have used all your swipes. Buy a plan to keep swiping."): set the counter to 0, put the card back, open the paywall.
- `SALARY_MISMATCH` (409): toast for 6s, e.g. "<First> expects at least ₹X LPA, above this job's budget of ₹Y LPA, and is not open to negotiate." The card is not put back.
- 409 duplicate ("You have already swiped this candidate for this job"): silent.
- Other errors: card put back and an error toast.

**Every swipe, left or right, costs 1 credit. Wishlist is free.**

### Undo / rewind

- `POST /company/swipe/undo` undoes **the current user's most recent swipe, within 10 minutes**.
- Response: `{swipesLeft, action, jobId, card}`. If the job matches, the card **flies back in from the side it left** and becomes the top card again.
- Toasts:
  - Pass undone: "Pass undone, swipe refunded".
  - Shortlist undone: "Shortlist undone. Its swipe is not refunded, as contact details were shown."
- Errors:
  - 404 "There is no recent swipe to undo" (also resets the undo count to 0).
  - 409 "You have already contacted this candidate, so this swipe cannot be undone" (a message, interview or task was sent, or the stage changed).
- Undoing a shortlist deletes the candidate's "shortlisted" notification.

### Wishlist toggle (heart on the card or the action bar)

- Optimistic flip, then `PUT /company/wishlist/:candidateId {wishlisted: bool}`.
- Toast "Added to wishlist" or "Removed from wishlist". On error the flip is reverted and an error toast shows.

### Feed loading

- `GET /company/feed?limit=10&exclude=<ids in stack + pending>&jobId=&...filters` runs whenever fewer than 3 cards are left.
- Response: `{candidates, swipesLeft, job}`.
- **The server never sends more cards than `swipesLeft`.**
- It excludes candidates already swiped for this job, candidates not open to work, and **candidates whose expected salary is above the job's max and who won't negotiate**.
- Order: active candidates first (stale ones last), then match score, with a boost for people who joined this week.
- An empty response marks the feed as exhausted. Buying swipes clears that and fetches again.
- Feed errors:
  - Job paused or closed: 409 "This job is paused or closed. Reopen it to see candidates."
  - Not completed: 403 "Please complete your hiring requirements first".

### Empty and other states (inside the card area)

| State | What shows |
|---|---|
| Loading with no card | Spinner |
| **No open jobs** | Briefcase icon, "No open jobs", "Post a job (or reopen one) to start swiping candidates for it.", button "+ Go to jobs" |
| **Feed error** | "Could not load candidates", the error message, button "Try again" |
| **Out of swipes** (`swipesLeft <= 0`) | Illustration `out-of-swipes`, "You're out of swipes", "Get more swipes to keep discovering great candidates.", button "👑 See plans" → `/company/plans` |
| **Filters on, no results** | Illustration `no-candidates`, "No one matches your filters", "Try widening them to see more candidates.", buttons "Edit filters" (ghost) and "Clear filters" (primary) |
| **Everyone seen** | Illustration `no-candidates`, "You've seen everyone", "New candidates join every day. Check back soon, or review your wishlist.", button "♡ Open wishlist" |

### Paywall modal (`sm:max-w-2xl`)

- Title "You've used all your swipes".
- Text "Pick a plan to keep swiping. Your wishlist and shortlist stay safe.", plus an X close button.
- PlanCards are embedded below. A purchase closes the modal.

### Filters modal (`FeedFilters`)

- Header "Filter candidates", subtitle "Only matching candidates will appear in your stack", X close.
- **Saved searches** list (if any), each row:
  - The name, which applies that search when tapped.
  - A bell toggle (amber when on; tooltip "Alerts on: we notify you about new matches" or "Alerts off") → `PATCH /company/searches/:id {alerts}` (optimistic; reverted with a toast on error).
  - A trash icon → `DELETE /company/searches/:id` (optimistic, silent).
- Fields:

| Field | Type | Placeholder / hint | Behaviour |
|---|---|---|---|
| City | LocationInput | "e.g. Jaipur (also matches preferred cities)" | Matches the candidate's location or preferred locations (case-insensitive, partial) |
| Min experience (yrs) | number | "Any" | |
| Max experience (yrs) | number | "Any" | |
| Your budget (max LPA) | number | "Any". Hint when empty: "Shows candidates whose expected range starts at or below this, plus anyone open to negotiate". Otherwise the salary hint. | Candidate's expected salary ≤ value, **or** negotiable |
| Notice period | MultiChipSelect | | Immediate, 15 days, 30 days, 60 days, 90 days |
| Must have any of these skills | TagInput | "React, Excel…" | Any one skill matches (exact, case-insensitive). Server keeps up to 10. |

- **"Save this search & get alerts"** box:
  - Text "We'll notify you when a new candidate matching these filters joins."
  - Name input (max 60, placeholder "e.g. React devs in Jaipur") and a "Save" button, disabled until at least one filter is set and the name is filled.
  - Under the box when no filters are set: "Set at least one filter first."
  - `POST /company/searches {name, filters, alerts:true}` → toast `Saved "<name>". We'll alert you about new matches.`
  - Server errors: "Give this search a name", "Set at least one filter before saving the search", "You can save up to 20 searches. Delete one first."
  - Only candidates who join or change their profile later trigger alerts (existing matches are excluded).
- Footer: "↺ Clear" (resets the form only) and "Show candidates" (applies the filters, closes the modal, resets the feed).
- **Filters are remembered** in localStorage per user (`swipehire_filters_<userId>`).
- **Alert flow:** a notification "New match for "<name>"" with body "<Name> · <headline> · <location> just joined. Swipe now before others do." links to `/company/swipe?search=<id>`, which applies that saved search automatically and removes the param.

---

## 3. Wishlist: `/company/wishlist`

`GET /company/wishlist` returns `{candidates}`, newest first, with the match score against the oldest open job. Candidates who are already shortlisted come back with `swipe:'right'` and `contact`.

**Header:**
- Heart icon, title "Wishlist", count pill.
- Subtitle "Candidates you saved to look at again".

**Loading:** spinner.

**Empty state:**
- Illustration `empty-wishlist`.
- Text "Tap the heart on a candidate card to save them here."
- Button "Start swiping" → `/company/swipe`.

**Grid:** 1 column, 2 from `sm`, 3 from `lg`. Each card can be opened by tap, Enter or Space and lifts on hover. Card contents:
- Avatar, name, headline.
- A green BadgeCheck if already shortlisted.
- A message icon button (only if shortlisted) → `/messages?with=<id>`.
- MatchBadge, location and experience chips.
- Contact email in green (only if shortlisted).
- First 4 skills, then "+N".

**Candidate modal** (`sm:max-w-xl`):
- Header: large avatar, name, headline, MatchBadge, X close.
- Body:
  - Contact rows when available: ✉ email (mailto) and ☎ phone (tel), each with a copy icon → toast "Copied".
  - "Message" button (only if already shortlisted).
  - "View resume" button → ResumeViewer.
  - CandidateDetails.
- Footer:
  - **"♡ Remove"** → `PUT /company/wishlist/:id {wishlisted:false}`. Removes the card, closes the modal, toast "Removed from wishlist".
  - **"Shortlist"** (only if not yet swiped) → `POST /company/swipe {candidateId, action:'right'}` (**no jobId, so the server uses the oldest open job; costs 1 swipe**). Updates the counter, shows the contact, toast "<First> shortlisted!".

---

## 4. Shortlisted (pipeline): `/company/shortlisted`

Query param: `?job=<id>`.

`GET /company/shortlisted[?jobId=]` returns **one row per (candidate, job)** shortlisted. Each row has `swipeId`, `job{id, title}`, `stage`, `notes`, `shortlistedAt`, `contact{email, phone}`, and the card fields.

**Header:**
- Users icon, title "Shortlisted", count pill.
- Subtitle "Everyone you shortlisted. Tap a candidate for full details, message them, send a task or schedule an interview."
- **Job filter select** on the right (only if the company has more than one job, open or not):
  - Options: "All jobs", then each job title, with " (paused)" or " (closed)" for jobs that aren't open.
  - It sets `?job=`. Jobs come from `GET /company/jobs`.

**Empty state:**
- Illustration `empty-pipeline`.
- Text "Swipe right on a candidate to shortlist them and unlock their contact details."
- Button "Start swiping".

**Stage tabs** (horizontal scroll, animated pill):
- All, Shortlisted, Contacted, Task sent, Interview, Hired, Rejected, each with a count.
- If a stage has no one: "Nobody in this stage yet."

**Stage pill colours:**

| Stage | Colour |
|---|---|
| Shortlisted | grey |
| Contacted | sky |
| Task sent | violet |
| Interview | amber |
| Hired | green |
| Rejected | red |

**Selection bar** (when there are visible people):
- A checkbox labelled "Select all", or "N selected" once some are ticked. It selects the people in the current tab, de-duplicated by person.
- "Clear" (when something is selected).
- Primary button: "Message N selected", or "Message all (N)" when nothing is selected. It opens the **GroupMessageModal**.

**Pipeline card:**
- A custom checkbox (stops the card from opening), avatar, name, headline, StagePill, message icon → `/messages?with=`.
- Job title line in violet (briefcase icon).
- MatchBadge, location and experience chips, email in green, first 4 skills then "+N".
- A selected card gets a red ring.

**Candidate modal (pipeline mode):**
- Contact rows (email and phone with copy).
- **PipelineControls** box:
  - "Stage": ChipSelect of the 6 stages → optimistic `PATCH /company/pipeline/:swipeId {stage}` → toast "Moved to <Label>". Reverted on error.
  - Setting **Hired** sends the candidate "Congratulations! <Company> selected you 🎉".
  - "Private notes": textarea (max 2000, placeholder "Only your team can see these notes"). While unsaved it shows "Saves when you click outside the box". Saving happens when the textarea loses focus: `PATCH /company/pipeline/:swipeId {notes}` → toast "Notes saved".
  - 3 buttons:
    - "Message" → `/messages?with=<id>`.
    - "Send task" → SendTaskModal.
    - "Interview" (primary) → ScheduleInterviewModal.
- **Tasks** list: `GET /tasks?candidateId=` (cancelled tasks hidden), shown as compact TaskCards.
- "View resume" button, then CandidateDetails.

**Stage changes that happen automatically:**
- First company message: shortlisted → contacted (for every job that person is shortlisted for).
- Task sent: shortlisted or contacted → task.
- Interview invite: → interview, unless already hired or rejected.

### GroupMessageModal

- Title "Message N candidate(s)", subtitle "Each one gets it as a private chat message and an email."
- "To": chips with an avatar and name. Each chip has an × to remove it, except when only one is left.
- "Message" textarea (max 2000, 6 rows). Placeholder: "Hi! Thanks for your interest in the role.\nWe would like to invite you for an interview next week. Please reply with your availability."
- Note: "Candidates will see your company name with this message, and can reply in Messages."
- Errors shown in red: "Write a message first", "Choose at least one candidate".
- Button "Send to N candidate(s)" → `POST /chats/bulk {candidateIds, text}`. Server limits: **up to 50 at once, 20 bulk sends per hour**.
- Response `{sent, skipped}` → toast "Message sent to N candidate(s)". Rows still in Shortlisted move to Contacted on screen and the selection is cleared.

### ScheduleInterviewModal

Also opened from the chat header.

- Title "Schedule interview", subtitle "With <Name> · they pick the time that suits them".
- **"Time options (up to 3)"**: `datetime-local` inputs, defaulting to tomorrow 11:00 and the day after 11:00. Each has a trash icon when there is more than one. "+ Add another time" while there are fewer than 3.
- "Duration": chips 15 / 30 (default) / 45 / 60 min.
- "Interview type": Video call (default) / Phone / In person.
- Video: "Meeting link", placeholder "https://meet.google.com/...", hint "Leave empty and we'll create a free Jitsi video room for you".
- In person: "Office address", placeholder "2nd floor, Tower B, Malviya Nagar, Jaipur".
- "Note for the candidate": max 500, hint "Optional", placeholder "Please bring your portfolio".
- Client errors: "Add at least one time slot", "Time slots must be in the future" (must be at least 15 minutes ahead), "Please add the interview address".
- Server errors: "Meeting link must start with https://", "An interview with this candidate is already scheduled", "This candidate is not shortlisted for that job", "Please offer 1 to 3 time slots".
- Button "Send invite" → `POST /interviews {candidateId, jobId, slots[ISO], durationMins, mode, location, meetingLink, note}` → toast "Interview invite sent to <First>". The stage becomes interview.

### SendTaskModal

- Title "Send a task", subtitle "To <Name> · they submit a live link and GitHub repo before the deadline".
- Fields:
  - "Task title": max 120, placeholder "Build a to-do app with login", error "Give the task a title".
  - "What should they build?": max 5000, 6 rows. Hint "Requirements, tech stack, what you will check". Error "Describe what they should build". Placeholder: "- React front end, any backend\n- Users can add, edit and delete tasks\n- Deploy it and share the live link + GitHub repo".
  - "Reference link": optional, placeholder "https://figma.com/…", hint "Optional: a brief, Figma design or doc". Server error "Please enter a valid reference link".
  - "Deadline": preset chips "1 day", "3 days" (default), "1 week" (each sets that day at 23:59), plus a `datetime-local` input. Error "Pick a deadline at least 1 hour from now". Server: "The deadline can be at most 30 days away".
- Button "Send task" → `POST /tasks {candidateId, jobId, title, description, briefUrl, dueAt}` → toast "Task sent to <First>". The stage becomes task.

---

## 5. Jobs: `/company/jobs`

**Header:**
- Title "Jobs".
- Subtitle "N hiring now", or "Every job has its own swipe feed and pipeline." while loading.
- Primary button "+ Post a job".

**Data:** `GET /company/jobs` returns jobs sorted open, then paused, then closed. Each has `stats{swiped, shortlisted, interviewing, hired}`.

**Empty state:** illustration `no-jobs`, "No jobs yet. Post your first one!"

**Grid:** 1 column, 2 from `lg`. Job card, top to bottom:
1. Gradient briefcase tile, title, a line "📍location · On-site/Hybrid/Remote · full time".
2. Status pill: **Hiring** (green), **Paused** (amber), **Closed** (grey; the whole card is dimmed).
3. "₹min–max LPA" (or "Up to max LPA"), " · min–max yrs" (max can be ∞), " · N openings" when there is more than 1.
4. Up to 6 skill chips.
5. 4 stat tiles: Seen, Shortlist, Interview, Hired.
6. Actions:
   - "Swipe" (open jobs only) → `/company/swipe?job=id`.
   - "Shortlisted" → `/company/shortlisted?job=id`.
   - "Edit" → modal.
   - On the right, icon buttons: Pause (open jobs), Reopen/Play (paused or closed), Close (not closed).
   - These call `PATCH /company/jobs/:id/status {status}` → toasts "Job paused", "Job reopened", "Job closed".
   - Server limit: **25 active (non-closed) jobs**. Error "You can have up to 25 active jobs. Close an old one first." (or "...active jobs." when reopening).

### JobFormModal (`sm:max-w-xl`)

- Title "Post a new job" or "Edit job", subtitle "Candidates are ranked against these requirements".

| Field | Type | Placeholder | Required / validation |
|---|---|---|---|
| Job title | Autocomplete (ROLES) | "e.g. Frontend Developer" | Client: "Enter the role you are hiring for"; server max 80 |
| Skills you need | TagInput | "React, JavaScript…" | Client: "Add at least one skill". Hint "Candidates with these skills are shown first" |
| Min experience (yrs) | number | "0" | Server 0–50 ("Please enter a valid minimum experience"). Min > max: "Minimum experience cannot be more than maximum experience" |
| Max experience (yrs) | number | "5" | 0–50 |
| Min salary (LPA) | number | "3" | Salary hint. Server: "Minimum salary cannot be more than maximum salary" |
| Max salary (LPA) | number | "8" | Client: "Enter the maximum salary" |
| Job location | LocationInput | "Jaipur" | New jobs default to the company location |
| Openings | number, min 1 | | Default 1. Server 1–1000 |
| Work mode | ChipSelect | | On-site (default) / Hybrid / Remote |
| Job type | ChipSelect | | Full-time (default) / Part-time / Internship / Contract |
| Description | textarea, max 3000 | "What will this person do? What's great about the team?" | Hint "Optional · shown to candidates you shortlist" |

- The numeric fields are in a 2-column grid.
- Button "Post job" or "Save changes":
  - Create: `POST /company/jobs` → toast "Job posted! Start swiping for it."
  - Edit: `PUT /company/jobs/:id` → toast "Job updated".
- Server errors with a `field` show under that field.

---

## 6. Plans and payment: `/company/plans` (also inside the paywall)

**Header:**
- "Swipe more, **hire faster.**" (gradient text).
- "Every swipe (left or right) uses one credit. Saving candidates to your wishlist is always free."
- Pill "⚡ You have **N** swipes left".

**PlanCards:** data from `GET /payment/plans` → `{plans, freeSwipes, demoMode}`. On error: toast "Could not load plans".

1. **Free card** (gift icon):
   - "Free", "₹0", "{freeSwipes} swipes to try Swipe Hire" (default 5).
   - Points: "Given on sign-up", "Resume & video access".
2. **One paid plan** (the server's PLANS array; pricing is still being finalised with the client):
   - **Starter: ₹399, one-time, 150 swipes.**
   - Card has an animated gradient border, crown icon, and "Most popular" pill.
   - "₹399 one-time", "150 swipes · ₹2.7 per candidate".
   - Perks: "150 candidate swipes", "Full resume & intro video access", "Unlimited wishlist", "Contact details on shortlist".
   - Button "Buy 150 swipes".
3. In demo mode, small amber text: "Demo mode: Razorpay keys are not set, so purchases are simulated (no real money is charged)."

**Buy flow:**
1. `POST /payment/order {planId}` → `{mode, orderId, amount (paise), currency:'INR', keyId, plan}`.
   - Errors: "Please choose a valid plan", "Payments are not available right now" (503).
2. **Demo mode:** wait 900ms, then `POST /payment/verify {orderId}`.
3. **Razorpay:** load `checkout.razorpay.com/v1/checkout.js` and open checkout:
   - name "Swipe Hire", description "Starter plan · 150 swipes".
   - Prefilled with the user's name and email; theme in the brand colour.
   - On success: `POST /payment/verify {orderId, paymentId, signature}`.
   - Closing the window does nothing.
   - Failure: toast with the error description, or "Payment failed".
   - Script fails to load: "Could not open payment window, check your internet".
4. Verify returns `{profile, added}` → toast "**150 swipes added. Happy hiring!**". The profile updates, so the counter changes everywhere and the paywall closes.
   - Verify errors: "Order not found", "Payment verification failed".
   - A Razorpay webhook also credits the order, and an order is never credited twice.

---

## 7. Company profile: `/company/profile`

**Header:** building icon, "Company profile", a blue ✓ VerifiedBadge if verified, and "Candidates you shortlist see these details. A complete profile gets more replies."

**Section 1:** ImageUploader, label "Company logo", endpoint `POST`/`DELETE /company/logo`. Any team member can change it.

**Section 2, "About the company":**
- Company name: building icon, max 100, required, error "Enter your company name".
- Industry: select, same 10 options as onboarding.
- Company size: select, placeholder "Employees".
- Founded in: number, calendar icon, placeholder "2018". Server 1800 to the current year: "Please enter a valid founded year".
- Description: textarea, max 1500, placeholder "We build…". Hint "What you do, your culture, why people love working with you".

**Section 3, "Contact & links":**
- Website: placeholder "yourcompany.com". Error "Please enter a valid web address".
- LinkedIn page: placeholder "linkedin.com/company/…". Same check.
- Contact number: tel, placeholder "+91 98765 43210". Server pattern `^\+?[\d\s-]{8,16}$`: "Please enter a valid phone number".
- Contact email: email, placeholder "careers@yourcompany.com", hint "For candidates, e.g. careers@…". Error "Please enter a valid email address".
- City: LocationInput, placeholder "Jaipur", required, error "Enter your city".
- Office address: placeholder "Floor, building, area", hint "Used for in-person interviews".

**Unsaved changes bar:** appears when anything has changed. It is fixed at the bottom, above the mobile nav (`bottom-24`, or `bottom-6` on desktop).
- Text "You have unsaved changes".
- "Discard" resets the form.
- "Save changes" → `PUT /company/profile` (all fields) → toast "Company profile saved".

**Warning:** changing the company name or website **resets verification to none** if the company was pending, verified or rejected.

---

## 8. Team: `/company/team`

**Header:** users icon, "Team", "Recruiters on your team share jobs, swipes, pipeline and chats. Up to 10 people."

**Data:** `GET /team` → `{isOwner, members:[{id, name, email, role:'owner'|'recruiter', you, joinedAt}], invites:[{id, email, expires}]}`.

**There are only two roles: Owner and Recruiter.** Every invitee becomes a Recruiter.

**Invite box** (owner only):
- Title "Invite a recruiter".
- Email input (placeholder "colleague@company.com") and "Send invite" button (disabled while empty) → `POST /team/invite {email}` → toast "Invite sent to <email>".
- Errors shown under the field:
  - "Please enter a valid email address"
  - "This email already has a Swipe Hire account"
  - "Your team can have up to 10 people." (members plus pending invites)
  - "Only the account owner can do this"
- The invite link lasts **7 days**. Re-inviting the same email replaces the old invite.
- Dev mode without email: an amber box "Development mode (no email server). Share this link with <email>:" followed by the link; tapping it copies → "Link copied".

**Member list:**
- Initials tile, name, "(you)" for yourself, email.
- Badge "👑 Owner" (amber) or "Recruiter".
- The owner sees a trash icon on recruiters. It asks to confirm "Remove <name> from your team? They will lose access immediately.", then `DELETE /team/members/:id` → toast "<name> removed". This deletes the recruiter's login.

**Pending invites:**
- Dashed mail tile, email, "Invite pending", shown dimmed.
- The owner's trash icon calls `DELETE /team/invites/:id` (silent).

**Non-owner:** footer text "Only the account owner can invite or remove people."

### Join page: `/join?token=` (guests only)

- Loads `GET /auth/invite/:token`.
- Invalid: "Invite not valid", the error, and a "Go to login" button.
- Valid: "Join <Company>", "as a recruiter · <email>".
  - "Your name" (placeholder "Your full name"); missing → toast "Please enter your name".
  - "Choose a password" (placeholder "At least 6 characters"); shorter → "Password must be at least 6 characters".
  - "Join team" → `POST /auth/accept-invite {token, name, password}` → signed in, toast "Welcome to <Company>!", then the home path.

---

## 9. Verification: `/company/verify`

**Header:** sky-coloured shield icon, "Get verified", "A verified badge shows candidates you are a real company. Verified companies get more replies."

**Data:** `GET /company/verification` → `{verification:{status, method}, gstin, website, email}`.

**Statuses:** `none`, `pending`, `verified`, `rejected`. Methods: `email` or `gst`.

**There are no document uploads.** There are two methods:

### A. "Verify with work email · instant"

- Text: "Your login email (<email>) must be on your company website's domain (<website>)."
- "Send code to my email" → `POST /company/verification/email/send` → toast "Code sent to <email>".
- Errors shown under the button:
  - Personal email (gmail, yahoo, hotmail, outlook, rediffmail, icloud, proton, zoho and similar): "Your login email is a personal email. Use GST verification, or sign up with your work email."
  - No website: "Add your company website in your company profile first, so we can match your email to it."
  - Domain mismatch: "Your email (@x) does not match your website (y)."
  - Over 5 sends or 15 wrong codes per 24h: "Too many codes requested today. Please try again tomorrow, or use GST verification."
- After sending:
  - Field "Enter the 6-digit code sent to <email>": digits only, max 6, centred and widely spaced, placeholder "123456", one-time-code autofill.
  - Dev mode shows "Development mode (no email server): your code is NNNNNN".
  - Buttons "Resend" and "Verify" (Verify is enabled only at 6 digits) → `POST /company/verification/email/confirm {code}`.
  - Errors: "Wrong code, please check and try again", "Code expired, please request a new one" (codes last 10 minutes), "Too many wrong attempts, please request a new code" (5 tries).
  - Success: verified straight away.

### B. "Verify with GSTIN · reviewed by our team"

- Text: "Use this if you sign in with a personal email."
- Input: automatically uppercased, spaces removed, max 15, placeholder "22AAAAA0000A1Z5".
- Button "Submit", or "Update" while pending. Enabled only at 15 characters.
- `POST /company/verification/gst {gstin}` → status becomes pending, toast "Submitted! We will review it shortly."
- Server format `^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$`, error "Please enter a valid 15-character GSTIN".

### Status banners

- **Pending:** amber banner "GSTIN <x> is under review. You will get a notification once it is approved, usually within one working day."
- **Rejected:** red banner "We could not verify your GSTIN. Please check it, or verify with your work email instead."
- **Verified:** the whole page is replaced by a success card:
  - Confetti and illustration `verified`.
  - "Your company is verified".
  - "Candidates see a blue badge next to your name in chats and interview invites (verified by GSTIN)" or "(verified by work email)".

The profile menu label changes to "Verified company". The badge appears on the Company profile title and to candidates.

---

## 10. Messages: `/messages` (company view)

**Header:** "Messages". On the right, the active conversation's StagePill (company only) and a "New message" button.

**Layout:** a glass panel. Desktop has 2 columns (320px list and the thread). On mobile only one shows at a time: the list, or the thread with a ← back button.

**Conversation list:** `GET /chats`, polled every 10s.
- Each row: avatar, name (bold if unread), verified badge, last message ("You: …" for messages from your side; any teammate counts as you), or the subtitle.
- Time ago, or "new". Unread count badge.
- **Empty:** illustration `no-messages`, "No conversations yet", "Message a candidate from your Shortlisted page, or tap New message.", button "Open shortlisted".
- When nothing is selected (desktop): "Choose a conversation".

**Thread** (`?with=<candidateId>`): `GET /chats/:id`, polled **every 4s**.
- Header: avatar, name, subtitle (headline/role), and an **"Interview"** button (label hidden on mobile) that opens ScheduleInterviewModal.
- Messages: day headers ("Mon, 5 Oct"). My bubbles are on the right with a gradient; theirs are on the left in grey. Each shows the time and ✓ (sent) or ✓✓ (read).
- Auto-scrolls to the newest message.
- Empty: "Say hello to <First> 👋".
- Composer: textarea, max 2000, placeholder "Type a message…". **Enter sends; Shift+Enter adds a new line.** Send button.
  - `POST /chats/:id {text}`.
  - Errors: "Message cannot be empty", rate limit "You are sending messages too fast, please slow down" (30 per minute).
- **The company can only message candidates it has shortlisted.** The first message moves the candidate to Contacted. The candidate is notified and emailed.

**New message modal:**
- Title "New message", subtitle "Candidates you shortlisted". `GET /chats/contacts`.
- Search box: "Search by name or role".
- Rows: avatar, name, subtitle, StagePill, and a chat icon if a chat already exists.
- Empty: "Shortlist a candidate first, then you can message them."
- No search match: "No one matches “q”."

---

## 11. Interviews: `/interviews` (company view)

- Title "Interviews", subtitle "Invite candidates from your Shortlisted page or from chat."
- `GET /interviews`, polled every 30s.
- **Empty:** illustration `no-interviews`, "No interviews yet.", button "Open shortlisted".

**Groups** (each with a count):
- "Waiting for the candidate" (proposed).
- "Upcoming" (confirmed and in the future, soonest first).
- "Past & cancelled".

**Interview card:**
- Calendar tile, candidate name, verified badge, "For <job title>".
- Status pill: "Waiting for reply" (amber), "Confirmed", "Done" (past), or "Cancelled".
- Chips: Video call / Phone call / In person, "N min", location.
- Note shown in quotes.
- **Confirmed:** a green box with the date and time (e.g. "Mon, 5 Oct, 11:00 am"). If it is still upcoming: "Join video call" (meeting link; a Jitsi room is created automatically when no link was given) and "Add to calendar" (a Google Calendar template link).
- **Proposed:** "Times you offered" with the slots as read-only chips. **The candidate picks the slot; the company cannot confirm one.**
- If not cancelled and not past:
  - "Message candidate" → chat.
  - "Cancel interview" opens a modal: "Cancel interview with <name>?", "They will be notified. You can agree on a new time in chat.", a reason textarea (max 300, "Reason (optional)"), and buttons "Keep it" / "Cancel interview" → `POST /interviews/:id/cancel {reason}` → toast "Interview cancelled".

---

## 12. Tasks: `/tasks` (company view)

On mobile this is reached from the profile menu.

- Title "Tasks", subtitle "Assignments you sent to shortlisted candidates. Send one from the Shortlisted page."
- `GET /tasks`, polled every 30s. The company also sees cancelled tasks.
- **Empty:** illustration `no-jobs`, "No tasks sent yet.", button "Open shortlisted".
- **Filter chips** with counts: All, Waiting (assigned), Submitted, Deadline passed (overdue). With no results: "Nothing here."
- Statuses: Waiting (amber), Submitted (green), Deadline passed (red), Cancelled (grey). "Overdue" isn't stored; it is an assigned task whose deadline has passed.

**TaskCard:**
- Header: candidate avatar, name, "For <job>", message icon.
- Title with a clipboard icon and status pill.
- "Due Mon, 5 Oct, 11:59 pm · 2 days 4 h left". Under 1 hour it shows "N min left" in red.
- "Show task details" / "Hide details" toggle: the description plus a "Reference" link.
- **Submission** (if submitted): "Submission · <date>", with "Live" and "GitHub" link rows (open in a new tab) and the candidate's note.
- Company actions (not cancelled):
  - **"Change deadline"**: an inline `datetime-local` (defaults to the later of now and the due date, plus 2 days), "Save" / "Cancel" → `PATCH /tasks/:id {dueAt}` → toast "Deadline updated". Rules: at least 1 hour away, at most 30 days.
  - **"Cancel task"**: confirms `Cancel "<title>"? The candidate will be told they don't need to submit it.` → `POST /tasks/:id/cancel` → toast "Task cancelled".

The compact version of this card (no header) is used inside the Shortlisted candidate modal.

---

## 13. Account settings: `/settings` (shared; company-specific parts only)

- Profile photo uploader.
- Full name.
- **"Your phone (optional)"** (company only): placeholder "98765 43210", hint "Only your teammates see this".
- Email: read-only, "Your login email can't be changed".
- `PUT /account` → toast "Saved".
- A link card to "Company profile".
- Change password: Current / New / Confirm → `PUT /account/password` → toast "Password changed. Other devices have been logged out."
- "Log out of all devices" → `POST /auth/logout-all` → toast "Logged out of all devices".

---

## 14. Admin: `/admin`

**Access:**
- Client guard `admin` checks `user.isAdmin`.
- Server: the user's email must be in the `ADMIN_EMAILS` environment setting **and** the email must be verified. Otherwise 403 "Admins only".
- The admin is an ordinary user (candidate or company) whose profile menu also shows "Admin". The page uses the normal AppShell with that user's own navigation.

**Scope:** the admin can **only review GSTIN verification requests**. There are no user, job or payment management tools.

**Layout:**
- Title "🛡 Admin · company verification".
- Subtitle "Check each GSTIN on the government portal before approving."
- Spinner while loading.
- Empty: "No pending requests 🎉".

**Data:** `GET /admin/verifications` returns pending companies, oldest first: `{id, companyName, website, location, gstin, contact{name, email}, requestedAt}`.

**Row card:**
- Company name (bold).
- "contact name · contact email · location · website".
- The GSTIN in large monospace.
- Buttons:
  - "↗ Check GSTIN": opens https://services.gst.gov.in/services/searchtp in a new tab.
  - "✕ Reject" → `POST /admin/verifications/:companyId {approve:false}` → row removed, toast "<Company> rejected".
  - "✓ Approve" (primary) → `{approve:true}` → toast "<Company> verified".
- On error: "No pending request for this company" (404).

**What the company receives:**
- Approved: "Your company is verified ✓" / "Candidates now see a verified badge next to your company name."
- Rejected: "Verification was not approved" / "We could not verify your GSTIN. Please check it, or verify with your work email instead."
- Both link to `/company/verify` and are also emailed.

---

## 15. Points worth copying exactly in the Android app

- **Credits:**
  - Server default is 5 free swipes (`FREE_SWIPES`).
  - Each left or right swipe costs 1; the wishlist is free.
  - Shortlisting from the Wishlist also costs 1.
  - Undoing a pass refunds the swipe; undoing a shortlist does not. Undo only works within 10 minutes and only before the candidate is contacted.
  - The feed never returns more cards than the swipes left, so 0 swipes leads to the "You're out of swipes" state.
  - The counter changes optimistically and is then corrected from the server response.
- **Filters:**
  - Stored per device in localStorage.
  - The selected job is stored per company.
  - The active filter count counts the city, min experience, max experience and budget fields individually, plus one for notice period and one for skills.
- **The salary rule hides candidates** who expect more than the job's max salary and won't negotiate. A right swipe on such a candidate is refused with SALARY_MISMATCH.
- **One person can appear on more than one pipeline row** (one per job). Group messaging de-duplicates by person.
- **Polling intervals:**

| What | Interval |
|---|---|
| Chat thread | 4s |
| Conversation list | 10s |
| Unread count | 15s |
| Notifications, interviews, tasks | 30s |

  All of them pause while the tab is hidden and refresh when it becomes visible again.
- **Limits:**

| Limit | Value |
|---|---|
| Active jobs | 25 |
| Team size (members + pending invites) | 10 |
| Saved searches | 20 |
| Group message recipients | 50 |
| Group sends per hour | 20 |
| Chat messages per minute | 30 |
| Interview slots | 1–3, at least 15 min ahead |
| Task deadline | 1 hour to 30 days |
| Logo size | 3 MB |
| Notes | 2000 chars |
| Message | 2000 chars |
