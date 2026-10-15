// Validation for the candidate's own profile (PUT /candidates/me/profile) and
// preferences (PUT /candidates/me/preferences). Every failure is reported as
// { error, field } so the app can highlight the offending input.

const { normalizeSkills, parseExperienceYears, parseNoticeDays } = require("./derive");
const { WORK_MODES, JOB_TYPES } = require("./taxonomy");

const PHONE_RE = /^\+?[\d\s-]{10,16}$/;
const MAX_SKILLS = 30;
const MAX_SKILL_LENGTH = 40;
const MAX_PREFERRED_LOCATIONS = 10;
const MAX_LOCATION_LENGTH = 40;

class FieldError extends Error {
  constructor(field, message) {
    super(message);
    this.field = field;
  }
}

// Strings are trimmed and cut to length (not rejected), like the website.
function text(value, max) {
  if (typeof value === "number" && Number.isFinite(value)) value = String(value);
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function isBlank(value) {
  return value === undefined || value === null || (typeof value === "string" && value.trim() === "");
}

// A salary in LPA. Anything >= 1000 is a full rupee amount (12,00,000 ->
// 12 LPA). Returns null when blank; throws FieldError for junk.
function salary(value, field, label) {
  if (isBlank(value)) return null;
  const n = typeof value === "number" ? value : Number(String(value).replace(/,/g, "").trim());
  if (!Number.isFinite(n) || n < 0) throw new FieldError(field, `Please enter a valid ${label}`);
  const lpa = n >= 1000 ? n / 100000 : n;
  const rounded = Math.round(lpa * 100) / 100;
  if (rounded > 1000) throw new FieldError(field, `Please enter a valid ${label}`);
  return rounded;
}

function number(value, field, label, min, max) {
  if (isBlank(value)) throw new FieldError(field, `${label} is required`);
  const n = typeof value === "number" ? value : Number(String(value).trim());
  if (!Number.isFinite(n) || n < min || n > max) throw new FieldError(field, `Please enter a valid ${label.toLowerCase()}`);
  return n;
}

function requiredText(value, max, field, label) {
  const s = text(value, max);
  if (!s) throw new FieldError(field, `${label} is required`);
  return s;
}

function skillList(value) {
  if (!Array.isArray(value)) throw new FieldError("skills", "Please add at least one skill");
  const seen = new Set();
  const out = [];
  for (const item of value) {
    const s = text(item, MAX_SKILL_LENGTH);
    const key = s.toLowerCase();
    if (!s || seen.has(key)) continue;
    seen.add(key);
    out.push(s);
  }
  if (out.length === 0) throw new FieldError("skills", "Please add at least one skill");
  if (out.length > MAX_SKILLS) throw new FieldError("skills", `You can add up to ${MAX_SKILLS} skills`);
  return out;
}

function enumList(value, allowed) {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((v) => String(v).trim().toLowerCase()).filter((v) => allowed.includes(v)))];
}

/**
 * Validates the whole profile form. Returns the Prisma data object.
 * Optional new fields that are *absent* from the body are left out of the
 * result, so an older app build that doesn't send them can't wipe them.
 * @throws {FieldError}
 */
function parseProfileBody(b) {
  const body = b && typeof b === "object" ? b : {};

  const desiredRole = requiredText(body.desiredRole, 80, "desiredRole", "Job title / role");

  const phone = requiredText(body.phone, 20, "phone", "Phone number");
  if (!PHONE_RE.test(phone)) throw new FieldError("phone", "Please enter a valid phone number");

  const age = number(body.age, "age", "Age", 16, 75);
  if (!Number.isInteger(age)) throw new FieldError("age", "Please enter a valid age");

  const gender = requiredText(body.gender, 30, "gender", "Gender");
  const location = requiredText(body.location, 80, "location", "Location");
  const qualification = requiredText(body.qualification, 40, "qualification", "Qualification");
  const degree = requiredText(body.degree, 80, "degree", "Degree");
  const skills = skillList(body.skills);

  const experience = requiredText(body.experience, 100, "experience", "Experience");
  const experienceYears = parseExperienceYears(experience);
  if (experienceYears < 0 || experienceYears > 50) throw new FieldError("experience", "Please enter a valid experience");

  const expectedSalaryLpa = salary(body.expectedSalaryLpa, "expectedSalaryLpa", "expected salary");
  if (expectedSalaryLpa === null || expectedSalaryLpa <= 0) {
    throw new FieldError("expectedSalaryLpa", "Expected salary is required");
  }
  const currentSalaryLpa = salary(body.currentSalaryLpa, "currentSalaryLpa", "current salary") ?? 0;

  const noticePeriod = text(body.noticePeriod, 30);

  const data = {
    desiredRole,
    phone,
    age,
    gender,
    location,
    qualification,
    degree,
    skills,
    skillsNormalized: normalizeSkills(skills),
    experience,
    experienceYears,
    expectedSalaryLpa,
    currentSalaryLpa,
    noticePeriod,
    noticeDays: parseNoticeDays(noticePeriod),
    currentCompany: text(body.currentCompany, 80),
    about: text(body.about, 600),
    photoUrl: text(body.photoUrl, 1000),
    resumeUrl: text(body.resumeUrl, 1000),
    introVideoUrl: text(body.introVideoUrl, 1000),
  };

  // Optional new fields: present -> validate and set, absent -> untouched.
  if (body.college !== undefined) data.college = text(body.college, 120);
  if (body.currentPost !== undefined) data.currentPost = text(body.currentPost, 80);

  if (body.graduationYear !== undefined) {
    if (isBlank(body.graduationYear)) {
      data.graduationYear = null;
    } else {
      const year = Number(body.graduationYear);
      if (!Number.isInteger(year) || year < 1960 || year > 2040) {
        throw new FieldError("graduationYear", "Please enter a valid graduation year");
      }
      data.graduationYear = year;
    }
  }

  if (body.expectedSalaryMaxLpa !== undefined) {
    const max = salary(body.expectedSalaryMaxLpa, "expectedSalaryMaxLpa", "maximum salary");
    if (max !== null && max > 0 && max < expectedSalaryLpa) {
      throw new FieldError("expectedSalaryMaxLpa", "Maximum salary can't be lower than the minimum");
    }
    data.expectedSalaryMaxLpa = max !== null && max > 0 ? max : null;
  }

  if (body.salaryNegotiable !== undefined) data.salaryNegotiable = body.salaryNegotiable === true;
  if (body.workModes !== undefined) data.workModes = enumList(body.workModes, WORK_MODES);
  if (body.jobTypes !== undefined) data.jobTypes = enumList(body.jobTypes, JOB_TYPES);

  return data;
}

/**
 * Preferences: only what is present is changed.
 * @throws {FieldError}
 */
function parsePreferencesBody(b) {
  const body = b && typeof b === "object" ? b : {};
  const data = {};

  if (body.openToWork !== undefined) {
    if (typeof body.openToWork !== "boolean") throw new FieldError("openToWork", "openToWork must be true or false");
    data.openToWork = body.openToWork;
  }
  if (body.workModes !== undefined) data.workModes = enumList(body.workModes, WORK_MODES);
  if (body.jobTypes !== undefined) data.jobTypes = enumList(body.jobTypes, JOB_TYPES);

  if (body.preferredLocations !== undefined) {
    if (!Array.isArray(body.preferredLocations)) {
      throw new FieldError("preferredLocations", "preferredLocations must be a list");
    }
    const seen = new Set();
    const out = [];
    for (const item of body.preferredLocations) {
      const s = text(item, MAX_LOCATION_LENGTH);
      const key = s.toLowerCase();
      if (!s || seen.has(key)) continue;
      seen.add(key);
      out.push(s);
    }
    data.preferredLocations = out.slice(0, MAX_PREFERRED_LOCATIONS);
  }
  return data;
}

module.exports = { FieldError, parseProfileBody, parsePreferencesBody, PHONE_RE };
