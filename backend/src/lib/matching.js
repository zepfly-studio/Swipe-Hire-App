// How well a candidate fits a job, as a 0-100 score plus the reasons behind
// it. The same function powers "Recommended for you" on the candidate side
// and the match percentage on the recruiter's deck and applicant lists, so
// both sides see consistent numbers.
//
// Weights (skills carry the most because they are the most concrete signal):
//   skills 55 · experience 15 · location 15 · salary 15
// A job that lists no skills has nothing to compare, so that weight is
// shared out proportionally to the other three.

const WEIGHTS = { skills: 55, experience: 15, location: 15, salary: 15 };

function toList(value) {
  return Array.isArray(value) ? value : [];
}

function skillsFit(job, candidate) {
  const wanted = toList(job.skillsNormalized);
  if (wanted.length === 0) return null; // nothing to compare
  const have = new Set(toList(candidate.skillsNormalized));
  const matched = wanted.filter((s) => have.has(s));
  return { value: matched.length / wanted.length, matched };
}

function experienceFit(job, candidate) {
  const need = Number(job.minExperienceYears) || 0;
  const years = Number(candidate.experienceYears) || 0;
  if (need <= 0) return 1;
  if (years >= need) return 1;
  return Math.max(0, years / need);
}

function locationFit(job, candidate) {
  const jobLoc = String(job.location || "").toLowerCase().trim();
  const candLoc = String(candidate.location || "").toLowerCase().trim();
  if (!jobLoc || /remote|anywhere|work from home|wfh/.test(jobLoc)) return 1;
  if (!candLoc) return 0;
  return jobLoc.includes(candLoc) || candLoc.includes(jobLoc) ? 1 : 0;
}

function salaryFit(job, candidate) {
  const max = Number(job.salaryMaxLpa) || 0;
  const min = Number(job.salaryMinLpa) || 0;
  const expected = Number(candidate.expectedSalaryLpa) || 0;
  if (max <= 0 || expected <= 0) return 1; // unknown on either side: don't penalise
  if (expected <= max) return 1;
  if (expected <= max * 1.2) return 0.5;
  return min > 0 && expected <= min ? 1 : 0;
}

/**
 * @param job       { skillsNormalized, minExperienceYears, location, salaryMinLpa, salaryMaxLpa }
 * @param candidate { skillsNormalized, experienceYears, location, expectedSalaryLpa }
 * @returns { score: 0-100 integer, reasons: string[] }
 */
function matchScore(job, candidate) {
  const skills = skillsFit(job, candidate);
  const parts = {
    experience: experienceFit(job, candidate),
    location: locationFit(job, candidate),
    salary: salaryFit(job, candidate),
  };

  let weightSum = WEIGHTS.experience + WEIGHTS.location + WEIGHTS.salary;
  let total = parts.experience * WEIGHTS.experience + parts.location * WEIGHTS.location + parts.salary * WEIGHTS.salary;
  if (skills) {
    weightSum += WEIGHTS.skills;
    total += skills.value * WEIGHTS.skills;
  }

  const score = Math.round((total / weightSum) * 100);

  const reasons = [];
  if (skills && skills.matched.length) reasons.push(`${skills.matched.length} of ${toList(job.skillsNormalized).length} skills match`);
  if (parts.location === 1 && String(job.location || "").trim()) reasons.push("location fits");
  if (parts.experience === 1 && Number(job.minExperienceYears) > 0) reasons.push("meets the experience requirement");
  if (parts.salary === 1 && Number(job.salaryMaxLpa) > 0) reasons.push("expectation is within budget");

  return { score: Math.max(0, Math.min(100, score)), reasons };
}

/** The recruiter's best-matching open posting for a candidate. */
function bestMatch(jobs, candidate) {
  let best = null;
  for (const job of jobs) {
    const { score, reasons } = matchScore(job, candidate);
    if (!best || score > best.score) best = { score, reasons, jobId: job.id, jobTitle: job.title };
  }
  return best;
}

module.exports = { matchScore, bestMatch, WEIGHTS };
