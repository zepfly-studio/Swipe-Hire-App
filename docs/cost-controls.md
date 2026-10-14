# Cost controls — Firebase Budget Alerts & usage limits

All app data lives in the backend's Postgres database, so the main costs to
watch are the Postgres/Node host (Railway, Render, Neon, etc. -- each has its
own usage dashboard and free tier) and Cloudinary media bandwidth. Firebase is
only used for the auth session and FCM push, both free at any realistic
scale, and the project stays on the free Spark plan. If you ever move Firebase
to Blaze (pay-as-you-go), set a budget alert immediately.

## Firebase / Google Cloud Budget Alerts (do this before/when moving to Blaze)

1. Google Cloud Console → Billing → Budgets & alerts → Create budget.
2. Scope it to this project's billing account.
3. Set a monthly amount you're comfortable with, with alert thresholds at
   50%/90%/100% (the defaults are reasonable).
4. Add your email as a recipient.

This does **not** automatically stop usage/billing when hit -- it's a
notification only. For a hard cap you'd need a scheduled job that disables
billing-dependent features past a threshold, which isn't set up here
(overkill before there's real paid traffic).

## Cloudinary free tier

Cloudinary's free tier has its own bandwidth/storage/transformation
limits, shown on their dashboard. There's no budget-alert equivalent for
the free tier (it just stops serving once you hit the cap) -- watch the
usage graph on the Cloudinary dashboard periodically once there's real
traffic. See `docs/cloudinary-setup.md` for also locking down the upload
preset against abuse that would burn through this quota early.

## What's NOT set up (intentionally, for now)

- Automated quota-based circuit breakers (e.g. disabling uploads once
  near the Cloudinary cap) -- not worth the complexity before there's
  real usage to react to.
- Per-user caps on writes (e.g. job postings per recruiter per day) --
  only a global per-IP rate limit exists on the backend today; tracked in
  `docs/PRODUCTION_ROADMAP.md`.
