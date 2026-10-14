const express = require("express");
const cors = require("cors");
const helmet = require("helmet");
const rateLimit = require("express-rate-limit");

const { prisma } = require("./lib/prisma");
const authRoutes = require("./routes/auth");
const userRoutes = require("./routes/users");
const candidateRoutes = require("./routes/candidates");
const jobRoutes = require("./routes/jobs");
const opportunityRoutes = require("./routes/opportunities");
const swipeRoutes = require("./routes/swipes");
const companyRoutes = require("./routes/company");
const { notifications: notificationRoutes, templates: templateRoutes } = require("./routes/inbox");

// Builds the Express app without starting a listener, so the same app can
// be served by server.js and driven directly by tests.
function createApp() {
  const app = express();
  app.set("trust proxy", 1);
  app.disable("x-powered-by");
  app.use(helmet());
  app.use(cors({ origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(",") : true }));
  app.use(express.json({ limit: "256kb" }));

  const authLimiter = rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: Number(process.env.AUTH_RATE_LIMIT) || 30,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: { error: "Too many attempts. Please wait a moment and try again." },
  });

  const apiLimiter = rateLimit({
    windowMs: 60 * 1000,
    limit: Number(process.env.API_RATE_LIMIT) || 300,
    standardHeaders: "draft-8",
    legacyHeaders: false,
    message: { error: "Too many requests. Please slow down." },
  });

  // Liveness + database reachability, for load balancers and uptime monitors.
  app.get("/health", async (req, res) => {
    try {
      await prisma.$queryRaw`SELECT 1`;
      res.json({ ok: true });
    } catch {
      res.status(503).json({ ok: false });
    }
  });

  app.use("/auth", authLimiter, authRoutes);
  app.use("/users", apiLimiter, userRoutes);
  app.use("/candidates", apiLimiter, candidateRoutes);
  app.use("/jobs", apiLimiter, jobRoutes);
  app.use("/opportunities", apiLimiter, opportunityRoutes);
  app.use("/swipes", apiLimiter, swipeRoutes);
  app.use("/company", apiLimiter, companyRoutes);
  app.use("/notifications", apiLimiter, notificationRoutes);
  app.use("/templates", apiLimiter, templateRoutes);

  app.use((req, res) => res.status(404).json({ error: "Not found." }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err.type === "entity.parse.failed") {
      return res.status(400).json({ error: "Invalid JSON body." });
    }
    if (err.type === "entity.too.large") {
      return res.status(413).json({ error: "That request is too large." });
    }
    if (err.code === "P2025") {
      return res.status(404).json({ error: "Not found." });
    }
    console.error(`[error] ${req.method} ${req.originalUrl}:`, err);
    res.status(500).json({ error: "Something went wrong. Please try again." });
  });

  return app;
}

module.exports = { createApp };
