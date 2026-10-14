require("dotenv").config();

const { createApp } = require("./app");
const { prisma } = require("./lib/prisma");
const { startTaskReminders } = require("./jobs/taskReminders");
const { startMaintenance } = require("./jobs/maintenance");

const isProduction = process.env.NODE_ENV === "production";

if (isProduction) {
  const required = [
    "DATABASE_URL",
    "JWT_SECRET",
    "FIREBASE_SERVICE_ACCOUNT_PATH",
    "RESEND_API_KEY",
    "RESEND_FROM_EMAIL",
    "CORS_ORIGIN",
  ];
  const missing = required.filter((name) => !process.env[name]);
  if (missing.length) {
    console.error(`Refusing to start in production: missing ${missing.join(", ")}`);
    process.exit(1);
  }
  if (process.env.JWT_SECRET.length < 32) {
    console.error("Refusing to start in production: JWT_SECRET must be at least 32 characters");
    process.exit(1);
  }
}

const port = Number(process.env.PORT) || 4000;
const server = createApp().listen(port, () => {
  console.log(`Backend listening on http://localhost:${port} (${isProduction ? "production" : "development"})`);
  startTaskReminders();
  startMaintenance();
});

// Finish in-flight requests and close the database connection when the
// host stops the process (deploys, scale-down), instead of cutting them off.
// A crash exits non-zero so a process manager knows to restart it.
let shuttingDown = false;
function shutdown(reason, exitCode = 0) {
  if (shuttingDown) return;
  shuttingDown = true;
  console.log(`[shutdown] ${reason}, closing...`);
  const force = setTimeout(() => process.exit(exitCode || 1), 10000);
  force.unref();
  server.close(async () => {
    await prisma.$disconnect().catch(() => {});
    process.exit(exitCode);
  });
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));

// A rejected promise nobody awaited is logged; it must not take the API down.
process.on("unhandledRejection", (reason) => {
  console.error("[unhandledRejection]", reason);
});
// State after an uncaught exception can't be trusted: stop cleanly and fail.
process.on("uncaughtException", (err) => {
  console.error("[uncaughtException]", err);
  shutdown("uncaughtException", 1);
});

// The port is taken, or the socket can't be opened.
server.on("error", (err) => {
  console.error("[server]", err.message);
  process.exit(1);
});
