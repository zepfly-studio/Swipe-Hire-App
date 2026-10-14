# Web error reporting (Sentry) — one-time setup

Firebase Crashlytics has no web SDK, so web errors previously only showed
up in `debugPrint` output -- invisible once deployed. Sentry fills that gap
for the web build only (mobile keeps using Crashlytics as before).

## 1. Get a DSN

1. Create a free account at https://sentry.io (generous free tier).
2. Create a new project, platform = Flutter (or just JavaScript/Browser --
   either works for a web-only Flutter build).
3. Copy the DSN it gives you (looks like `https://xxxx@o0.ingest.sentry.io/0`).

## 2. Wire it in

Set `ErrorReporter.sentryWebDsn` in `lib/services/error_reporter.dart`
(currently an empty string, which means Sentry is never initialized and
every call is a safe no-op):

```dart
static const String sentryWebDsn = 'https://xxxx@o0.ingest.sentry.io/0';
```

That's it -- `lib/main.dart` already wraps the web app startup in
`SentryFlutter.init` when this is non-empty, and `ErrorReporter.report()`
forwards manually-caught errors there too.

## 3. Verify

Run a web build, trigger an error (e.g. throw inside a button's onTap
temporarily), and check it shows up in the Sentry project dashboard within
a minute or two.
