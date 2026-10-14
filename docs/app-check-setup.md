# Firebase App Check — turning on real enforcement

The app now activates App Check with the real attestation providers
(Play Integrity on Android, App Attest on iOS) in release builds, and the
debug provider in debug builds. With app data now in the Node/Postgres
backend, App Check only protects the Firebase Auth session and FCM -- it is
low priority; the backend's own JWT auth is what protects the data. With app data now in the Node/Postgres
backend, App Check only protects the Firebase Auth session and FCM -- it is
low priority; the backend's own JWT auth is what protects the data. Activating it alone doesn't block
anything yet — each Firebase service only rejects unattested requests once
you turn on "Enforce" for it in the console, which you should only do after
confirming real builds are passing attestation.

## 1. Register debug tokens (for local/debug testing)

1. Run a debug build; the first run prints something like:
   `Firebase App Check debug token: XXXXXXXX-XXXX-...` to the device log.
2. Firebase console → App Check → Apps → your Android/iOS app → manage
   debug tokens → add that token.
3. Without this, debug builds will fail App Check once enforcement is on.

## 2. Enable Play Integrity (Android)

1. Play Console → your app → Setup → App integrity → make sure Play
   Integrity API is enabled for the app (it is automatically for apps
   using Play App Signing).
2. Firebase console → App Check → Apps → Android app → register the
   provider as Play Integrity (it should auto-detect once the app's SHA
   fingerprints match what's in Play Console).

## 3. Enable App Attest (iOS) — only if/when iOS ships

Not needed yet since this project is Android + Web only for now. Revisit
when iOS is added.

## 4. Turn on enforcement — do this LAST, per service

Firebase console → App Check → APIs tab → for each Firebase service the
app still uses (Authentication, Cloud Messaging), click "Enforce" **only
after** you've confirmed a real release build (or a debug build with its
token registered) is successfully attaching App Check tokens — check the
"Requests" metrics graph for each API first. Turning on enforcement before
that will lock out real users whose builds aren't attesting yet. (App data
no longer lives in Firebase; the backend's own JWT auth protects it.)

## 5. Web

Not configured yet — needs a reCAPTCHA v3 site key from the Firebase
console (App Check → Apps → Web app → register reCAPTCHA v3), then wire it
into `lib/main.dart`'s `_activateAppCheck()` (currently returns early on
`kIsWeb`). Left out for now since a placeholder key would break every
Firebase call on web.
