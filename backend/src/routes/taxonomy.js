const express = require("express");
const { requireAuth } = require("../middleware/requireAuth");
const { taxonomy } = require("../lib/taxonomy");

const router = express.Router();
router.use(requireAuth);

// GET /taxonomy -> { roles, skills, degrees, cities, states, locations }
// The pick-lists behind every role / skill / degree / city field in the app.
router.get("/", (req, res) => {
  res.json(taxonomy());
});

module.exports = router;
