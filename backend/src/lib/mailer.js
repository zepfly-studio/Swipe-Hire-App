const { Resend } = require("resend");

function emailConfigured() {
  return Boolean(process.env.RESEND_API_KEY && process.env.RESEND_FROM_EMAIL);
}

let client;
function resend() {
  if (!client) client = new Resend(process.env.RESEND_API_KEY);
  return client;
}

function sender() {
  const fromName = process.env.RESEND_FROM_NAME || "SwipeHire";
  return `${fromName} <${process.env.RESEND_FROM_EMAIL}>`;
}

function escapeHtml(text) {
  return String(text ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

async function deliver(message) {
  const { error } = await resend().emails.send({ from: sender(), ...message });
  if (error) {
    const err = new Error(error.message || "Resend rejected the email");
    err.response = { body: error };
    throw err;
  }
}

const COPY = {
  signup: {
    subject: "Your SwipeHire verification code",
    intro: "Use this code to verify your email and finish creating your SwipeHire account:",
  },
  reset: {
    subject: "Reset your SwipeHire password",
    intro: "Use this code to reset your SwipeHire password:",
  },
};

// Sends through Resend (https://resend.com). RESEND_FROM_EMAIL must be an
// address on a domain verified in the Resend dashboard, or
// `onboarding@resend.dev` while testing (which can only deliver to the
// account owner's own inbox).
async function sendOtpEmail({ to, otp, purpose }) {
  const { subject, intro } = COPY[purpose];
  await deliver({
    to,
    subject,
    text: `${intro} ${otp}\n\nIt expires in 10 minutes. If you didn't request this, you can ignore this email.`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;color:#1a1a1a">
        <h2 style="margin:24px 0 8px">SwipeHire</h2>
        <p>${intro}</p>
        <p style="font-size:32px;font-weight:700;letter-spacing:8px;margin:16px 0">${otp}</p>
        <p style="color:#666">It expires in 10 minutes. If you didn't request this, you can ignore this email.</p>
      </div>`,
  });
}

// An update about the hiring process (task assigned, interview scheduled...).
// `attachments` is [{ filename, content }] -- e.g. the interview .ics.
async function sendNotificationEmail({ to, subject, heading, body, attachments }) {
  const paragraphs = String(body ?? "")
    .split("\n")
    .filter((line) => line.trim())
    .map((line) => `<p style="margin:6px 0;line-height:1.5">${escapeHtml(line)}</p>`)
    .join("");
  await deliver({
    to,
    subject,
    text: `${heading}\n\n${body}\n\nOpen SwipeHire to respond. You can turn these emails off in your profile.`,
    html: `
      <div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;color:#1a1a1a">
        <h2 style="margin:24px 0 8px">${escapeHtml(heading)}</h2>
        ${paragraphs}
        <p style="color:#888;font-size:12px;margin-top:24px">
          Open SwipeHire to respond. You can turn these emails off in your profile.
        </p>
      </div>`,
    attachments,
  });
}

module.exports = { emailConfigured, sendOtpEmail, sendNotificationEmail };
