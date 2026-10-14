# Email OTP (Resend) — one-time setup

Signup verifies the email with a 6-digit code before the account is created,
and "Forgot password?" uses the same mechanism. Both codes are issued and
emailed by the Node backend (`backend/src/routes/auth.js` -> `issueOtp`,
`backend/src/lib/mailer.js`), for candidates and recruiters alike, through
[Resend](https://resend.com).

Until Resend is configured the backend runs in dev mode: the code is logged
to its console and returned to the app, which shows it on the verify screen
(`DevOtpBanner`). In production the server refuses to start without the
Resend settings, so real builds can never fall into that mode.

## 1. Get a Resend API key

1. Create a free account at https://resend.com (free tier: 3,000 emails/month,
   100/day).
2. **API Keys → Create API Key** — "Sending access" is enough. Copy the key
   (`re_xxxx...`); Resend only shows it once.

## 2. Pick the sender address

- **Testing right now (no domain):** use `onboarding@resend.dev`. Resend only
  delivers from this address to the email you signed up to Resend with, so
  sign up in the app with that same email to see the OTP arrive.
- **Real users:** **Domains → Add Domain**, add the DNS records Resend shows
  (SPF/DKIM) at your domain registrar, wait for "Verified", then use any
  address on that domain, e.g. `no-reply@yourdomain.com`.

## 3. Put them in the backend's `.env`

```
RESEND_API_KEY=re_xxxx...
RESEND_FROM_EMAIL=onboarding@resend.dev
RESEND_FROM_NAME=SwipeHire
```

Restart the backend. Codes are now emailed and no longer returned to the app.

## 4. Verify

Run the app, go to Create account, fill the form, submit — you should land
on "Verify your email" (with no code shown on screen) and receive the email
within a few seconds. Then try "Forgot password?" on the login screen.

If sending fails the backend logs `[otp] email send failed for <email>:`
with Resend's error (most often: unverified domain, or `onboarding@resend.dev`
used to send to an address other than your own).
