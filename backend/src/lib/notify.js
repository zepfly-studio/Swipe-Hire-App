// One place that tells a user something happened. Every event is
//   1. saved to their in-app inbox (the bell),
//   2. pushed to their phone, and
//   3. optionally emailed -- only for the important ones, only if they have
//      email notifications on.
// It never throws: a failed push or email must not fail the action that
// caused it.

const { prisma } = require("./prisma");
const { sendPush } = require("./firebase");
const { emailConfigured, sendNotificationEmail } = require("./mailer");

/**
 * @param userId  who to tell
 * @param event   { title, body, type, opportunityId, link, inbox, email: boolean | { subject, attachments } }
 *                `link` is the in-app route the notification opens, e.g. "/messages?with=<id>".
 *                `inbox: false` skips the in-app inbox (chat messages only
 *                move the unread badge, they don't fill the bell).
 * @returns the saved inbox row, or null when none was saved
 */
async function notify(userId, { title, body = "", type = "info", opportunityId = null, link = "", email = false, inbox = true } = {}) {
  if (!userId || !title) return null;

  let user;
  let row = null;
  try {
    user = await prisma.user.findUnique({
      where: { id: userId },
      select: { fcmToken: true, email: true, emailNotifications: true },
    });
    if (!user) return null;
    if (inbox) row = await prisma.notification.create({ data: { userId, type, title, body, opportunityId, link } });
  } catch (err) {
    console.error(`[notify] could not save notification for ${userId}:`, err.message);
    return null;
  }

  try {
    await sendPush(user.fcmToken, {
      title,
      body,
      data: { type, opportunityId: opportunityId || "", link: link || "", notificationId: row ? row.id : "" },
    });
  } catch (err) {
    console.error(`[notify] push failed for ${userId}:`, err.message);
  }

  if (email && user.emailNotifications && emailConfigured()) {
    const options = typeof email === "object" ? email : {};
    try {
      await sendNotificationEmail({
        to: user.email,
        subject: options.subject || title,
        heading: title,
        body,
        attachments: options.attachments,
      });
    } catch (err) {
      // Resend's test sender only reaches the account owner; that is expected
      // until a domain is verified, so keep it to one quiet line.
      console.warn(`[notify] email to ${userId} not sent: ${err.message}`);
    }
  }
  return row;
}

// Notifications that are sent without making the request wait (so a slow
// email provider can't slow an API call). Tracked so tests -- and a shutdown
// -- can wait for them to finish.
const pending = new Set();

function inBackground(promise) {
  const tracked = Promise.resolve(promise).catch((err) => console.error("[notify] background send failed:", err.message));
  pending.add(tracked);
  tracked.finally(() => pending.delete(tracked));
  return tracked;
}

function idle() {
  return Promise.all([...pending]);
}

module.exports = { notify, inBackground, idle };
