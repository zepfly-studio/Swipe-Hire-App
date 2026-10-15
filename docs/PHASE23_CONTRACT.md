# Phase 2 + 3 API contract (our backend, website-parity behaviour)

Source of behaviour: `docs/SWIPE_HIRE_APP_SPEC.md` (the website spec; its MongoDB backend is NOT
used). We keep OUR Express/Prisma/Postgres backend and OUR route style. This file pins the
endpoint shapes so backend and Flutter work can proceed in parallel.

Conventions
- Auth: `Authorization: Bearer <jwt>` (existing). Errors: `{ error: string, field?: string, code?: string }`.
- "Company" == a user with role `recruiter`. For now the company id in payloads is the
  recruiter's user id (a team feature comes later; do not model teams).
- Salaries are LPA. Times are ISO-8601 UTC strings.
- All new tables exist already (see backend/prisma/schema.prisma, migration
  `website_parity_core`): CandidateSwipe, WishlistEntry, ChatMessage, Interview, HiringTask,
  SavedSearch, Payment; Company has swipesLeft/swipesPurchased/creditedOrders + profile
  fields; JobPosting has status/openings/workMode/maxExperienceYears; Notification has `link`.
- The older tables/routes (Swipe, Opportunity, Message, Task, /swipes, /opportunities,
  candidate job apply) stay mounted but are NOT used by the new app. Do not extend them.

## A. Company, jobs, credits (backend agent A)

### Company
`GET /company/me` (recruiter) ->
`{ company: Company | null, suggestedName }` where Company =
`{ id, name, website, about, industry, size, location, logoUrl, address, phone, contactEmail,
   linkedin, foundedYear|null, verificationStatus, verified(bool), swipesLeft, swipesPurchased }`.
`PUT /company/me` body = any of those editable fields (name >=2 chars required on create).
`POST /company/onboarding` body `{ company: {name, industry?, size?, location, website?, about?},
  job: {title, skills[], minExperienceYears?, maxExperienceYears?, salaryMinLpa?, salaryMaxLpa,
  location?, workMode?} }` -> upserts the Company (starts with 5 swipes), creates the first job if
the recruiter has none, sets User.profileComplete=true. Returns `{ company, job }`.
Validation errors carry `field` (e.g. `company.name`, `job.title`, `job.salaryMaxLpa`).

### Jobs (existing `/jobs`, extended)
`GET /jobs/mine` -> `{ jobs: [Job] }`, Job =
`{ id, title, description, skills[], location, employmentType (job type: full-time|part-time|internship|contract),
   workMode (onsite|hybrid|remote), openings, salaryMinLpa, salaryMaxLpa, minExperienceYears,
   maxExperienceYears|null, status (open|paused|closed), isOpen, createdAt,
   stats: { swiped, shortlisted, interviewing, hired } }` sorted open, paused, closed then newest.
`POST /jobs`, `PUT /jobs/:id` accept those editable fields (`title`, `skills`, `salaryMaxLpa` required).
`PATCH /jobs/:id/status { status }` -> `{ job }`. Max 25 non-closed jobs per recruiter:
400 `{error:"You can have up to 25 active jobs. Close an old one first."}`.
`PATCH /jobs/:id { isOpen }` keeps working and keeps `status` in sync.

### Deck / feed (existing `GET /candidates`, extended; recruiter only)
Query: `jobId` (default: the recruiter's oldest open job), `exclude` (comma ids already in the
client's stack), `limit` (default 10, max 30), `location` (matches location OR preferredLocations,
case-insensitive substring), `expMin`, `expMax`, `maxSalary` (budget: expected <= value OR
salaryNegotiable), `notice` (comma list of exact notice-day buckets, e.g. `0,15,30`), `skills`
(comma, any-of, max 10), `q`, `cursor` (opaque).
Response `{ candidates: [Card], nextCursor, hasMore, swipesLeft, job: Job }`.
Rules: excludes candidates already swiped for THIS job (CandidateSwipe), `openToWork=false`,
and candidates whose expected salary is above the job's `salaryMaxLpa` and who are not
`salaryNegotiable` (hard salary-fit rule); never returns more cards than `swipesLeft -
exclude.length` (0 -> empty list); ordering as already implemented (stale last, match + new-user
bonus, newest). Errors: 403 `{code:'NO_JOB'}` when the recruiter has no job; 409 when the job is
paused/closed ("This job is paused or closed. Reopen it to see candidates."); 404 job not found.
Card = existing card + `matchScore`, `matchedSkills[]`, `wishlisted(bool)`; `contact` only for
candidates this company already right-swiped.

### Swipe, undo, wishlist, shortlisted, pipeline (all under `/company`, recruiter only)
- `POST /company/swipe { candidateId, action: 'left'|'right', jobId? }` -> `{ swipesLeft, contact?: {email, phone} }`
  (contact only on right). Costs 1 swipe for left AND right; wishlist is free.
  Errors: 402 `{code:'NO_SWIPES', error:'You have used all your swipes. Buy a plan to keep swiping.'}`;
  409 `{code:'SALARY_MISMATCH', error:'<First> expects at least ₹X LPA, above this job\'s budget of ₹Y LPA, and is not open to negotiate.'}` (right swipe only);
  409 duplicate "You have already swiped this candidate for this job" (the credit is refunded);
  404 candidate not found / not live. A right swipe sends the candidate an anonymous
  notification `{type:'shortlisted', title:'A company shortlisted you!', link:'/candidate'}` (+ push/email via existing notify lib).
- `POST /company/swipe/undo` -> `{ swipesLeft, action, jobId, card }`: undoes THIS recruiter's most
  recent swipe made within 10 minutes. A left swipe is refunded; a right swipe is not, and is only
  allowed while stage is still `shortlisted` and no chat message, interview or task exists for the
  pair since (else 409 "You have already contacted this candidate, so this swipe cannot be undone").
  404 "There is no recent swipe to undo". Deletes the `shortlisted` notification.
- `PUT /company/wishlist/:candidateId { wishlisted: bool }` -> `{ wishlisted }` (idempotent, free; candidate must be live + open to work).
- `GET /company/wishlist` -> `{ candidates: [Card] }` newest first, scored against the oldest open job;
  `contact` present when already shortlisted.
- `GET /company/shortlisted?jobId=` -> `{ candidates: [ShortlistRow] }`, one row per right swipe, newest first.
  ShortlistRow = Card + `{ swipeId, jobId, job:{id,title}, wishlisted, stage, notes, shortlistedAt, contact:{email, phone} }`.
- `PATCH /company/pipeline/:swipeId { stage?, notes? }` -> `{ ok, stage?, notes? }`. stage in
  shortlisted|contacted|task|interview|hired|rejected; notes <= 2000. Moving to `hired` notifies the
  candidate `{type:'hired', title:'Congratulations! <Company> selected you 🎉', link:'/messages?with=<companyId>'}`.
- Saved searches: `GET /company/searches` -> `{searches:[{id,name,filters,alerts}]}`;
  `POST /company/searches {name(<=60), filters:{location,minExp,maxExp,maxSalary,notice[],skills[]}, alerts?}` -> 201 `{search}`
  (400 "Give this search a name" / "Set at least one filter before saving the search"; max 20);
  `PATCH /company/searches/:id {alerts?, name?}`; `DELETE /company/searches/:id`.
  Alerts: when a candidate saves their profile (step complete), uploads video or changes
  preferences, every saved search with alerts that now matches and has not notified for that
  candidate yet gets ONE notification `{type:'alert', title:'New match for "<name>"', link:'/company/swipe?search=<id>'}`.

### Plans / payment (mounted at `/payment`)
- `GET /payment/plans` (public) -> `{ plans:[{id:'starter', name:'Starter', price:399, swipes:150, perks:[...]}], freeSwipes:5, demoMode:bool }`.
- `POST /payment/order { planId }` (recruiter) -> `{ mode:'razorpay'|'demo', orderId, amount(paise), currency:'INR', keyId, plan }`.
  Razorpay when `RAZORPAY_KEY_ID`/`RAZORPAY_KEY_SECRET` are set (create the order over Razorpay REST with basic auth);
  otherwise demo mode, allowed only when NODE_ENV != production OR `DEMO_PAYMENTS=true`; else 503 "Payments are not available right now".
- `POST /payment/verify { orderId, paymentId?, signature? }` -> `{ swipesLeft, added }`. Razorpay: HMAC_SHA256(secret, `orderId|paymentId`) must equal signature.
  Demo: only `{orderId}`. Crediting is atomic and idempotent per orderId (`Company.creditedOrders`).
- `POST /payment/webhook` (raw body, `x-razorpay-signature`): credits `payment.captured`/`order.paid` once.

### Candidate side bits that change (agent A)
`GET /candidates/me/stats` must now read CandidateSwipe/WishlistEntry/chat/interview/task:
`viewedCount` = all CandidateSwipe rows for the candidate; `wishlistedCount` = WishlistEntry rows;
`shortlistedCount` = right swipes; `hiddenCount` = distinct companies that right-swiped but have not
contacted (no ChatMessage from the company, Interview or HiringTask for the pair);
`shortlistedBy[]` only those that contacted: `{ id: swipeId, recruiterId, companyId: recruiterId,
companyName, industry, hiringFor (job title), location, verified, logoUrl, stage, date }`
(stage is the PipelineStage; `rejected` is shown to the candidate as closed by the app).

## B. Pair features: chat, interviews, tasks (backend agent B)

### Chats (`/chats`, both roles)
- `GET /chats` -> `{ conversations: [{ id: <other side's user id>, name, subtitle, verified?, avatarUrl, stage, lastMessage:{text, at, mine}, unread, updatedAt }] }` (only pairs with >=1 message, newest first).
- `GET /chats/contacts` -> `{ contacts: [{ id, name, subtitle, verified?, avatarUrl, stage, updatedAt, hasChat }] }`
  (company: candidates it right-swiped; candidate: companies that contacted them).
- `GET /chats/unread-count` -> `{ count }`.
- `GET /chats/:otherId` -> `{ with:{ id, name, subtitle, verified?, avatarUrl }, messages:[{ id, text, mine, at, read }] }`
  (last 200, oldest first; marks the other side's messages read).
- `POST /chats/:otherId { text }` (1-2000 chars) -> 201 `{ message }`. Company -> candidate allowed when the company right-swiped
  the candidate for any job; candidate -> company only after that company contacted them (403 "This company has not contacted you yet").
  First company message moves that pair's `shortlisted` swipes to `contacted`. Notifies the other side once while unread
  (`{type:'message', title:'New message from <name>', body:first 120 chars, link:'/messages?with=<senderId>'}`) + push/email via notify lib.
  Rate limit 30/min/user.
- `POST /chats/bulk { text, candidateIds[1..50] }` (company only) -> 201 `{ sent, skipped:[ids] }`; 20 bulk sends/hour.

### Interviews (`/interviews`, both roles)
Item `{ id, with:{id,name,subtitle,verified?,avatarUrl}, jobTitle, slots:[ISO], chosenSlot|null, durationMins, mode, meetingLink (only when confirmed), location, note, status, createdAt }`.
- `GET /interviews` -> `{ interviews:[...] }` latest 100.
- `POST /interviews` (company) `{ candidateId, jobId?, slots[1..3 ISO, each >= now+15min], durationMins (15|30|45|60, default 30), mode (video|phone|in-person), location (required for in-person, <=200), meetingLink? (https://, <=300), note? (<=500) }` -> 201 `{ id }`.
  Needs a right swipe for that candidate (for `jobId` if given). 409 if a proposed/upcoming-confirmed interview already exists for the pair.
  Video without link auto-creates `https://meet.jit.si/SwipeHire-<12 hex>`. Stage -> `interview` unless hired/rejected. Notifies the candidate (+email listing slots in IST).
- `POST /interviews/:id/accept { slot }` (candidate): slot must equal an offered slot, not in the past, status proposed. -> `{ ok:true }`. Notifies company (+email, ics attached).
- `POST /interviews/:id/cancel { reason? <=300 }` (either side, idempotent) -> `{ ok:true }`; notifies the other side.

### Tasks (`/tasks`, both roles)
Item `{ id, with:{id,name,subtitle?,verified?,avatarUrl}, jobTitle, title, description, briefUrl, dueAt, status ('assigned'|'submitted'|'overdue'|'cancelled'), submission?:{liveUrl, repoUrl, note, at}, createdAt }`.
- `GET /tasks` (company may pass `?candidateId=`) -> `{ tasks:[...] }`, max 200 newest first; candidates never see cancelled ones.
- `POST /tasks` (company) `{ candidateId, jobId?, title<=120, description<=5000, briefUrl?, dueAt }` -> 201 `{ id }`.
  dueAt between now+1h and now+30d. Stage shortlisted|contacted -> `task`. Notifies the candidate (+email).
- `POST /tasks/:id/submit` (candidate) `{ liveUrl?, repoUrl?, note?<=1000 }`: at least one link; http(s) only (add https if missing), <=300 chars; repo must be github.com; allowed repeatedly until dueAt (409 after); notifies company.
- `PATCH /tasks/:id { dueAt }` (company, same window) ; `POST /tasks/:id/cancel` (company, idempotent, notify without email).

### Reminders (src/jobs/taskReminders.js, port to the new tables)
Task due within 24h and unsubmitted -> candidate once; interview confirmed: 24h and 1h before -> both sides (Interview.remindersSent).

### Notifications
Existing `/notifications` keeps its shape and now also returns `link` per item. Types used: shortlisted, message, interview, task, hired, alert.

## C. Flutter company side (phase 2) / D. Flutter pair features (phase 3)
Owned files and class names are in each agent's brief. Shared rules: use the existing
`ApiClient`/`AppToast`/theme (green palette); never hard-code colours outside lib/theme; do not
edit files owned by the other Flutter agent; placeholders already exist for
`ShortlistedScreen`, `MessagesScreen`, `InterviewsScreen`, `TasksScreen` (agent D replaces them).
