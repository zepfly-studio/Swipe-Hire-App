const path = require("path");
const admin = require("firebase-admin");

let initialized = false;

function firebaseApp() {
  if (!initialized) {
    const keyPath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;
    if (!keyPath) throw new Error("FIREBASE_SERVICE_ACCOUNT_PATH is not set in .env");
    admin.initializeApp({ credential: admin.credential.cert(path.resolve(keyPath)) });
    initialized = true;
  }
  return admin;
}

function firebaseAuth() {
  return firebaseApp().auth();
}

// The app signs into Firebase Auth with this token so it has a Firebase
// session (AuthGate listens to it) keyed by the Postgres user id.
function mintFirebaseToken(user) {
  return firebaseAuth().createCustomToken(user.id);
}

// Best effort: signInWithCustomToken creates a bare uid-only record anyway if
// this fails (e.g. the email is still held by a legacy Firebase-Auth account).
async function ensureFirebaseUser(user) {
  try {
    await firebaseAuth().createUser({
      uid: user.id,
      email: user.email,
      displayName: user.name,
      emailVerified: true,
    });
  } catch (err) {
    if (err.code !== "auth/uid-already-exists") {
      console.warn(`[firebase] could not create auth record for ${user.id}: ${err.message}`);
    }
  }
}

async function deleteFirebaseUser(uid) {
  try {
    await firebaseAuth().deleteUser(uid);
  } catch (err) {
    if (err.code !== "auth/user-not-found") throw err;
  }
}

// Verifies the Firebase ID token the app got after "Continue with Google"
// and returns its claims ({ uid, email, name, email_verified, ... }).
function verifyIdToken(idToken) {
  return firebaseAuth().verifyIdToken(idToken);
}

/// Push notification to one device token (FCM). Never throws: a stale
/// token (uninstalled app, signed out elsewhere) is expected eventually.
async function sendPush(fcmToken, { title, body, data = {} }) {
  if (!fcmToken) return;
  try {
    await firebaseApp().messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v ?? "")])),
    });
  } catch (err) {
    console.error(`[push] failed to send to token ${fcmToken.slice(0, 12)}...: ${err.message}`);
  }
}

module.exports = { mintFirebaseToken, ensureFirebaseUser, deleteFirebaseUser, verifyIdToken, sendPush };
