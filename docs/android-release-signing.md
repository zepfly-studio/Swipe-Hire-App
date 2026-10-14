# Android release signing — one-time setup

Release builds currently fall back to the debug keystore (`build.gradle.kts`
prints a warning when it does). Play Store will reject a debug-signed build,
so do this once before your first real release.

## 1. Generate your own keystore

Run this yourself in a terminal (not something to hand off — pick your own
password and keep it somewhere safe, like a password manager; it can never
be recovered if lost, and losing it means you can never update the app on
Play Store under the same listing again):

```bash
cd android/app
keytool -genkeypair -v \
  -keystore release-keystore.jks \
  -alias swipehire \
  -keyalg RSA -keysize 2048 -validity 10000
```

It will prompt for a store password, a key password (can be the same), and
some identity fields (org name etc. — doesn't need to be exact).

## 2. Create `android/key.properties`

Copy `android/key.properties.example` to `android/key.properties` and fill
in the real values:

```
storePassword=<the password you just set>
keyPassword=<the password you just set>
keyAlias=swipehire
storeFile=release-keystore.jks
```

This file is already gitignored — never commit it or the `.jks` file.

## 3. Build

```bash
flutter build appbundle --release
```

`build.gradle.kts` will now sign with this keystore automatically. If
`key.properties` is missing, the build still succeeds but falls back to the
debug keystore with a warning — fine for local testing, not for Play Store.

## Keeping the keystore safe

- Back up `release-keystore.jks` and its password outside this repo (e.g. a
  password manager + a cloud backup). If you lose it, you cannot publish
  updates to an existing Play Store listing under the same app — you'd have
  to publish as a new app.
- If you ever move to Play App Signing (recommended, Google manages the
  final signing key), you still need this "upload key" to authenticate
  uploads.
