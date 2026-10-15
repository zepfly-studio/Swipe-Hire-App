// Saved searches and their "new match" alerts.
//
// A search with alerts on notifies its owner ONCE per candidate: the first
// time that candidate is live and matches. "Once" is enforced in the database
// (the candidate id is appended to notifiedCandidates by a conditional UPDATE),
// so two concurrent profile saves cannot both notify.

const { prisma } = require("./prisma");
const { notify } = require("./notify");
const { filtersMatch, filterConditions, cleanFilters } = require("./deck");

const MAX_SEARCHES = 20;
const PREMARK_LIMIT = 5000;

function toSearch(row) {
  return { id: row.id, name: row.name, filters: cleanFilters(row.filters), alerts: row.alerts };
}

/** Candidate ids that are live right now and match these filters (salary fit not applied). */
async function liveCandidateIdsMatching(filters) {
  const conditions = await filterConditions(filters);
  const users = await prisma.user.findMany({
    where: { role: "candidate", profileComplete: true, AND: conditions },
    select: { id: true },
    take: PREMARK_LIMIT,
  });
  return users.map((u) => u.id);
}

/**
 * Appends the candidate to a search's notified list unless it is already
 * there. @returns true when this call added it (and so should notify).
 */
async function markNotified(searchId, candidateId) {
  const rows = await prisma.$queryRaw`
    UPDATE "saved_searches"
    SET "notifiedCandidates" = array_append("notifiedCandidates", ${candidateId}::text)
    WHERE "id" = ${searchId} AND NOT (${candidateId}::text = ANY("notifiedCandidates"))
    RETURNING "id"`;
  return rows.length > 0;
}

/**
 * Called after a candidate saves their profile, uploads a video or changes
 * preferences. Skips candidates who are not live and open to work.
 * `assumeComplete`: the profile save itself finishes onboarding (the app marks
 * the account complete right after), so it counts as live.
 * @returns the number of alerts sent
 */
async function evaluateAlertsForCandidate(candidateId, { assumeComplete = false } = {}) {
  try {
    const user = await prisma.user.findUnique({ where: { id: candidateId }, include: { candidateProfile: true } });
    if (!user || user.role !== "candidate" || !user.candidateProfile) return 0;
    if (user.candidateProfile.openToWork === false) return 0;
    if (!user.profileComplete && !assumeComplete) return 0;

    const searches = await prisma.savedSearch.findMany({
      where: { alerts: true, NOT: { notifiedCandidates: { has: candidateId } } },
      take: 1000,
    });
    let sent = 0;
    for (const search of searches) {
      if (!filtersMatch(search.filters, user.candidateProfile)) continue;
      if (!(await markNotified(search.id, candidateId))) continue;
      await notify(search.recruiterId, {
        type: "alert",
        title: `New match for "${search.name}"`,
        body: "A new candidate matches your saved search.",
        link: `/company/swipe?search=${search.id}`,
        email: true,
      });
      sent += 1;
    }
    return sent;
  } catch (err) {
    console.error(`[alerts] could not evaluate saved searches for ${candidateId}:`, err.message);
    return 0;
  }
}

module.exports = { MAX_SEARCHES, toSearch, liveCandidateIdsMatching, evaluateAlertsForCandidate };
