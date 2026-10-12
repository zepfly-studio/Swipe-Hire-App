const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const STATUS_ACTIONS = {
  shortlisted: "shortlisted you",
  interviewScheduled: "scheduled an interview with you",
  offered: "sent you an offer",
  hired: "marked you as hired",
  rejected: "updated your application status",
};

/**
 * Pushes a notification to a candidate's device whenever a recruiter
 * creates or changes the status of one of their `opportunities` docs
 * (the Flutter app's HiringPipelineScreen) -- this is what makes the
 * candidate dashboard's "Hiring Activity" updates show up as a real push
 * notification instead of something only visible on next app open.
 */
exports.notifyCandidateOnOpportunityChange = onDocumentWritten("opportunities/{opportunityId}", async (event) => {
  const after = event.data?.after?.exists ? event.data.after.data() : null;
  if (!after) return; // the opportunity was deleted -- nothing to notify

  const before = event.data?.before?.exists ? event.data.before.data() : null;
  if (before && before.status === after.status) return; // no status change -- skip (e.g. a typo fix)

  const candidateUid = after.candidateUid;
  if (!candidateUid) return;

  const db = getFirestore();
  const userSnap = await db.collection("users").doc(candidateUid).get();
  const fcmToken = userSnap.data()?.fcmToken;
  if (!fcmToken) return; // candidate has no device registered for push yet

  const action = STATUS_ACTIONS[after.status] || "updated your application";
  const company = after.companyName || "A recruiter";
  const role = after.role || "a role";

  try {
    await getMessaging().send({
      token: fcmToken,
      notification: {
        title: company,
        body: `${company} ${action} for ${role}.`,
      },
      data: {
        opportunityId: event.params.opportunityId,
        status: after.status || "",
      },
    });
  } catch (error) {
    // A stale/invalid token is expected eventually (uninstalled app,
    // signed out elsewhere) -- log and move on rather than retry forever.
    console.error(`Failed to send notification to ${candidateUid}:`, error);
  }
});
