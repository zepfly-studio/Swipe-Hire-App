# Admin / moderation — manual process (for now)

There's no admin role in the signup flow and no in-app admin screen yet
(that's a roadmap item — see `docs/PRODUCTION_ROADMAP.md`, Phase 3). All
data lives in the backend's Postgres database, so moderation today is done
directly against the database.

## Removing a fraudulent job posting or abusive account right now

1. In `backend/`, run `npm run prisma:studio` — it opens a browser UI over
   every table.
2. **Job posting:** open `job_postings`, find the row (search by title or
   `recruiterId`), and either set `isOpen` to `false` (hides it from
   candidates, keeps the record) or delete the row (its applications and
   chats are deleted with it).
3. **Account:** open `users`, find the row by email, delete it. Postgres
   cascades: their profile, postings, applications, messages, saved jobs
   and swipes all go with it. The Firebase Auth record for that uid should
   then be removed by hand in the Firebase console (Authentication → Users)
   or the account owner's old session will keep a dangling Firebase user.

Only someone with the database credentials can do this, so a compromised
app client can never self-promote or moderate anyone.

## What a real admin role will need

- A `role = admin` value on `users` (enum change + migration) that the
  signup route never accepts.
- Admin-only routes: list/search users and postings, close/remove a posting,
  suspend an account, view reports.
- A web panel on top of those routes.
