# Phase 4 contract: verification, admin, team, account security

Behaviour source: `docs/SWIPE_HIRE_APP_SPEC.md` (Part A 1.3, 1.6, 1.7, 2.1, 2.2, 2.12, 4.8; Part C 8, 9, 14).
We keep OUR backend/routes. Conventions as in `docs/PHASE23_CONTRACT.md`
(Bearer JWT, errors `{error, field?, code?}`, "company" == user with role `recruiter`).

## Already in place (done by the coordinator)
- Migration `phase4_team_security_verification` applied locally; Prisma client generated.
  `User.tokenVersion`, `User.companyOwnerId`, model `TeamInvite`, `Company.gstin`,
  `Company.verificationMethod`, `Company.verificationOtp` (Json).
- `middleware/requireAuth.js`: JWT carries `v` (tokenVersion); a mismatch -> 401 "Your session has
  expired, please log in again."; sets `req.user.companyId` (owner id for a team member, own id
  otherwise) and `req.user.isOwner`.
- `lib/admin.js`: `isAdminUser(user)` (ADMIN_EMAILS env, comma separated, verified email).
- `GET/PATCH /users/me` (toProfile) now also returns `isAdmin`, `isOwner`, `companyId`.
- Routers mounted: `/team` + `/auth` extras (routes/team.js exports `{team, auth}`), `/admin`.

## Team rule (everything shared goes through companyId)
Every recruiter-side record is keyed by the hiring account id = `req.user.companyId`:
Company row, JobPosting.recruiterId, CandidateSwipe.recruiterId, WishlistEntry.recruiterId,
SavedSearch.recruiterId, Payment.recruiterId, credits (Company.swipesLeft),
ChatMessage.companyId, Interview.companyId, HiringTask.companyId. Things that identify the PERSON
keep `req.user.id`: ChatMessage.senderId, HiringTask.createdById, who swiped. For an owner
companyId === id so nothing changes. Notifications meant for "the company" go to the owner AND every
member. In company-side chat threads a message sent by a teammate carries `by` = that person's first
name (own messages keep `mine:true`; messages from other teammates are `mine:true` with `by` set).
Candidates always see `with.id` = the owner's user id.

## Account security
- `POST /auth/logout-all` (auth) -> `{ok:true}`: tokenVersion++ (every token on every device, incl. this one, dies).
- `POST /auth/logout` (auth) -> `{ok:true}` (no-op, kept for symmetry).
- `PUT /users/me/password { current, next }` (auth) -> `{ok:true, token}` where `token` is a freshly signed JWT
  (tokenVersion bumped, so all OTHER devices are logged out). 400 `{error:"Your current password is not correct", field:"current"}`,
  400 `{error:"New password must be at least 8 characters", field:"next"}`. The app must store the new token.
- Password reset (`/auth/password/reset`) also bumps tokenVersion.

## Company verification (recruiter; team members read, only the owner changes name/website)
Company.verificationStatus values: `unverified` (shown as "none"), `pending`, `verified`, `rejected`;
`verificationMethod`: `email` | `gst` | "". The existing domain auto-verify stays (it counts as method `email`).
- `GET /company/verification` -> `{ verification:{status:'none'|'pending'|'verified'|'rejected', method, verifiedAt}, gstin, website, email }`
  (`email` = the caller's login email).
- `POST /company/verification/gst { gstin }` -> `{ verification:{status:'pending', method:'gst'} }`; gstin upper-cased,
  regex `^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$` else 400 "Please enter a valid 15-character GSTIN" (field gstin);
  409 "Your company is already verified".
- `POST /company/verification/email/send` -> `{ sentTo, devCode? }`. Rules: the caller's login email must not be a free
  provider (gmail, googlemail, yahoo, ymail, hotmail, outlook, live, msn, rediffmail, icloud, me, aol, proton,
  protonmail, zoho, gmx, yandex): 400 "Your login email is a personal email. Use GST verification, or sign up with your work email.";
  company needs a website: 400 "Add your company website in your company profile first, so we can match your email to it.";
  domain must match the website (either is a subdomain of the other, www stripped): 400 "Your email (@x) does not match your website (y).".
  6-digit code (sha256 stored in Company.verificationOtp), 10 min TTL, 5 tries per code, max 5 sends/day and 15 failed
  tries/day (429 "Too many codes requested today. Please try again tomorrow, or use GST verification."). Emailed via lib/mailer
  (subject "<code> is your Swipe Hire code"). `devCode` only when email is not configured outside production OR
  OTP_DEV_FALLBACK=true and the send was refused by the test sender (reuse the existing logic style in routes/auth.js issueOtp).
- `POST /company/verification/email/confirm { code }` -> `{ verification:{status:'verified', method:'email', verifiedAt} }`;
  400 "Code expired, please request a new one", 429 "Too many wrong attempts, please request a new code", 400 "Wrong code, please check and try again".
- Renaming the company or changing the website resets `verified/pending/rejected` to `unverified` unless the existing
  domain auto-verify re-verifies it; always send the full company form from the app.
- Verification is notified: type `verified`, link `/company/verify`, titles "Your company is verified ✓" /
  "Verification was not approved" (to every team member, +email).

## Admin (`/admin`, auth + isAdminUser else 403 "Admins only")
- `GET /admin/verifications` -> `{ companies:[{ id (owner user id), companyName, website, location, gstin, contact:{name,email}, requestedAt }] }` pending GST requests, oldest first.
- `POST /admin/verifications/:companyId { approve:boolean }` -> `{ ok:true }` (approve true -> verified/method gst; else rejected). 404 "No pending request for this company".

## Team (`/team`, recruiters only; owner = isOwner)
- `GET /team` -> `{ isOwner, members:[{ id, name, email, role:'owner'|'recruiter', you:bool, joinedAt }], invites:[{ id, email, expires }] }`.
- `POST /team/invite { email }` (owner) -> 201 `{ ok:true, inviteCode? }`. 400 invalid email (field email); 409 "This email already has a Swipe Hire account";
  400 "Your team can have up to 10 people." (members + pending invites incl. the owner); replaces an older pending invite for the same email.
  Token = 24 random bytes base64url, only its sha256 is stored, valid 7 days. The email (lib/mailer, sendNotificationEmail-style) tells the person to
  open SwipeHire -> "Join a team" and enter this code; `inviteCode` is also returned in the response when email is not configured OR
  OTP_DEV_FALLBACK=true so the owner can share it manually.
- `DELETE /team/invites/:id`, `DELETE /team/members/:id` (owner; 400 "You cannot remove yourself"; removing a member deletes that login).
- `GET /auth/invite/:token` (public) -> `{ email, companyName }`; 404 "This invite link is invalid or has expired. Ask your team for a new one."
- `POST /auth/accept-invite { token, name, password(>=8) }` (public) -> 201 `{ token, firebaseToken, user }` like signup: creates a recruiter with
  `companyOwnerId`, `emailVerified:true`, `profileComplete:true`. 409 "An account with this email already exists" / "This invite was already used".
Members can do everything inside the company except invite/remove people and change the company name/website (owner only).
