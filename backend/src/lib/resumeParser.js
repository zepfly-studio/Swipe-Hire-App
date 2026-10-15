// Pulls profile fields out of a resume PDF so the onboarding form can be
// pre-filled. `extractProfile(text)` is a pure function over the PDF's text;
// `parseResumePdf(buffer)` does the PDF -> text step with pdf-parse.
//
// It only returns fields it actually found, so a scanned (image-only) PDF
// gives {} rather than guesses. Every field is a *suggestion* the candidate
// reviews in the form before saving.

const { ROLES, SKILLS, DEGREES, CITIES } = require("./taxonomy");

const MAX_SKILLS = 15;

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

// A name matches as a whole token: not glued to letters/digits on either
// side ("Java" must not match inside "JavaScript", "C" inside "CSS").
function tokenRegex(name, flags = "i") {
  const body = escapeRegex(name).replace(/\s+/g, "\\s+");
  return new RegExp(`(?<![A-Za-z0-9+#])${body}(?![A-Za-z0-9+#]|\\.[A-Za-z])`, flags);
}

function cleanText(text) {
  return String(text || "")
    .replace(/\r\n?/g, "\n")
    .replace(/[   ]/g, " ")
    .replace(/[•●▪■◦·►➢✓]/g, " ")
    .replace(/[ \t]+/g, " ")
    .replace(/\bjava\s+script\b/gi, "JavaScript")
    .replace(/\btype\s+script\b/gi, "TypeScript")
    .trim();
}

// ---------------------------------------------------------------- sections

const SECTION_HEADERS = [
  ["education", /^(education(al)?( qualifications?| background| details)?|academics?|academic (qualifications?|background|details)|qualifications?)\s*:?$/i],
  ["experience", /^(work |professional |employment )?(experience|history)( details)?\s*:?$|^(employment|career) (history|summary)\s*:?$|^internships?\s*:?$/i],
  ["skills", /^((key |core |technical |it |professional )?skills?( set| summary)?|technical (proficiency|expertise)|core competenc(y|ies)|tools( & technologies| and technologies)?|technologies)\s*:?$/i],
  ["languages", /^(languages?( known| proficiency)?|spoken languages|language skills)\s*:?$/i],
  ["projects", /^(academic |personal |key )?projects?( undertaken| work)?\s*:?$/i],
  ["other", /^(certifications?|courses?|achievements?|awards?( & honou?rs)?|honou?rs|hobbies|interests?|extra[- ]?curricular( activities)?|activities|personal (details|information|profile)|declaration|references?|summary|(career |professional )?objective|profile|about me|strengths)\s*:?$/i],
];

function sectionOf(line) {
  const t = line.trim().replace(/[:\-–—]+$/, "").trim();
  if (!t || t.length > 40) return null;
  for (const [name, re] of SECTION_HEADERS) if (re.test(t) || re.test(`${t}:`)) return name;
  return null;
}

// One section name per line ("" before the first header).
function labelSections(lines) {
  let current = "";
  return lines.map((line) => {
    const header = sectionOf(line);
    if (header) {
      current = header;
      return { section: header, header: true };
    }
    return { section: current, header: false };
  });
}

// ------------------------------------------------------------------- phone

function extractPhone(text) {
  const m = text.match(/(?<![\d])(\+?91[\s-]?)?([6-9]\d{4}[\s-]?\d{5})(?![\d])/);
  if (!m) return null;
  const digits = m[2].replace(/[\s-]/g, "");
  return m[1] ? `+91${digits}` : digits;
}

// ------------------------------------------------------------------ skills

function extractSkills(lines, labels) {
  // Spoken-language sections ("Languages: Hindi, English") are not skills.
  const usable = lines.filter((_, i) => labels[i].section !== "languages");
  const text = usable.join("\n");
  const skillsSection = lines.filter((_, i) => labels[i].section === "skills").join("\n");

  // Longest names first so "React Native" wins over "React" and "Java" never
  // steals the letters of "JavaScript". Matched text is blanked out. Names of
  // three characters or fewer ("Go", "SQL") must match case exactly, and
  // single letters ("R", "C") only count inside a Skills section.
  const names = [...SKILLS].sort((a, b) => b.length - a.length);
  let working = text;
  let workingSkills = skillsSection;
  const found = [];
  for (const name of names) {
    const flags = name.length <= 3 ? "" : "i";
    const haystack = name.length === 1 ? workingSkills : working;
    if (!tokenRegex(name, flags).test(haystack)) continue;
    const globalRe = tokenRegex(name, `${flags}g`);
    working = working.replace(globalRe, (m) => " ".repeat(m.length));
    workingSkills = workingSkills.replace(globalRe, (m) => " ".repeat(m.length));
    const at = text.search(tokenRegex(name, flags));
    found.push({ name, at: at < 0 ? Number.MAX_SAFE_INTEGER : at });
    if (found.length >= MAX_SKILLS) break;
  }
  return found.sort((a, b) => a.at - b.at).map((f) => f.name);
}

// ----------------------------------------------------------------- degrees

// Highest first. `name` must be in DEGREES to be returned.
const DEGREE_RULES = [
  { re: /\b(ph\.?\s?d|doctorate|doctor of philosophy)\b/i, name: "PhD", qualification: "PhD" },
  { re: /\bm\.?\s?tech\b|\bmaster of technology\b/i, name: "M.Tech", qualification: "Post Graduate" },
  { re: /\bmaster of engineering\b|\bM\.?\s?E\.?(?=\s*[(\-,]|\s+(in|degree)\b|\s*$)/, name: "M.E.", qualification: "Post Graduate", strict: true },
  { re: /\bmca\b|\bmaster of computer applications?\b/i, name: "MCA", qualification: "Post Graduate" },
  { re: /\bm\.?\s?b\.?\s?a\b|\bmaster of business administration\b/i, name: "MBA", qualification: "Post Graduate" },
  { re: /\bpgdm\b|\bpgp\b|\bpost graduate diploma in management\b/i, name: "PGDM", qualification: "Post Graduate" },
  { re: /\bm\.?\s?sc\b|\bmaster of science\b/i, name: "M.Sc", qualification: "Post Graduate" },
  { re: /\bm\.?\s?com\b|\bmaster of commerce\b/i, name: "M.Com", qualification: "Post Graduate" },
  { re: /\bllm\b|\bmaster of laws\b/i, name: "LLM", qualification: "Post Graduate" },
  { re: /\bm\.?\s?pharm\b/i, name: "M.Pharm", qualification: "Post Graduate" },
  { re: /\bm\.?\s?des\b/i, name: "M.Des", qualification: "Post Graduate" },
  { re: /\bmaster of arts\b|\bM\.?\s?A\.?(?=\s*[(\-,]|\s+(in|degree)\b|\s*$)/, name: "MA", qualification: "Post Graduate", strict: true },
  { re: /\bb\.?\s?tech\b|\bbachelor of technology\b/i, name: "B.Tech", qualification: "Graduate", specialise: true },
  { re: /\bbachelor of engineering\b|\bB\.?\s?E\.?(?=\s*[(\-,]|\s+(in|degree)\b|\s*$)/, name: "B.E.", qualification: "Graduate", strict: true },
  { re: /\bbca\b|\bbachelor of computer applications?\b/i, name: "BCA", qualification: "Graduate" },
  { re: /\bb\.?\s?sc\b|\bbachelor of science\b/i, name: "B.Sc", qualification: "Graduate" },
  { re: /\bb\.?\s?com\b|\bbachelor of commerce\b/i, name: "B.Com", qualification: "Graduate" },
  { re: /\bb\.?\s?b\.?\s?a\b|\bbachelor of business administration\b/i, name: "BBA", qualification: "Graduate" },
  { re: /\bb\.?\s?pharm\b/i, name: "B.Pharm", qualification: "Graduate" },
  { re: /\bb\.?\s?arch\b/i, name: "B.Arch", qualification: "Graduate" },
  { re: /\bb\.?\s?des\b/i, name: "B.Des", qualification: "Graduate" },
  { re: /\bmbbs\b/i, name: "MBBS", qualification: "Graduate" },
  { re: /\bllb\b|\bbachelor of laws\b/i, name: "LLB", qualification: "Graduate" },
  { re: /\bbachelor of arts\b|\bB\.?\s?A\.?(?=\s*[(\-,]|\s+(in|degree)\b|\s*$)/, name: "BA", qualification: "Graduate", strict: true },
  { re: /\bchartered accountan(t|cy)\b|\bca\s+(final|inter)\b/i, name: "CA", qualification: "Graduate" },
  { re: /\bdiploma\b.*\b(engineering|polytechnic|mechanical|civil|electrical|electronics|computer)\b|\b(engineering|polytechnic)\b.*\bdiploma\b/i, name: "Diploma (Engineering)", qualification: "Diploma" },
  { re: /\bdiploma\b|\bpolytechnic\b/i, name: "Diploma", qualification: "Diploma" },
  { re: /\bI\.?T\.?I\.?(?![\w])|\bindustrial training institute\b/, name: "ITI", qualification: "Diploma" },
  { re: /\b(12th|xii|hsc|higher secondary|intermediate|senior secondary|class 12|10\s?\+\s?2)\b/i, name: "12th", qualification: "12th" },
  { re: /\b(10th|ssc|matriculation|secondary school|class 10|high school|x std)\b/i, name: "10th", qualification: "10th" },
];

// "B.Tech in Computer Science" -> "B.Tech (CSE)" when the specialisation is
// one the DEGREES list knows about.
const SPECIALISATIONS = [
  { re: /computer science|\bcse\b|\bcs\b|computer engineering/i, short: "CSE" },
  { re: /information technology|\bit\b/i, short: "IT" },
  { re: /electronics|\becs?e?\b|communication/i, short: "ECE" },
  { re: /mechanical|\bme\b/i, short: "Mechanical" },
  { re: /civil/i, short: "Civil" },
  { re: /electrical|\bee\b|\beee\b/i, short: "Electrical" },
];

function degreeVariant(base, lineText) {
  for (const s of SPECIALISATIONS) {
    if (s.re.test(lineText)) {
      const candidate = `${base} (${s.short})`;
      if (DEGREES.includes(candidate)) return candidate;
    }
  }
  return base;
}

function twelfthStream(lineText) {
  if (/science|pcm|pcb|maths/i.test(lineText)) return "12th (Science)";
  if (/commerce/i.test(lineText)) return "12th (Commerce)";
  if (/\barts?\b|humanities/i.test(lineText)) return "12th (Arts)";
  return "12th";
}

function degreeOnLine(line) {
  for (let rank = 0; rank < DEGREE_RULES.length; rank++) {
    const rule = DEGREE_RULES[rank];
    if (!rule.re.test(line)) continue;
    // Bare "BA"/"ME"/"MA" are ordinary words or initials; they only count in
    // a line that also looks like an education line.
    if (rule.strict && !/(degree|bachelor|master|university|college|institute|graduat|cgpa)/i.test(line)) continue;
    let name = rule.name;
    if (rule.specialise) name = degreeVariant(name, line);
    if (rule.name === "12th") name = twelfthStream(line);
    return { rank, rule, name, line };
  }
  return null;
}

const EDU_HINT = /(university|college|institute|school|degree|bachelor|master|b\.?\s?tech|m\.?\s?tech|diploma|graduat|cgpa|percentage|\d{4}\s*[-–—to]+\s*\d{2,4})/i;

function findDegree(lines, labels) {
  let best = null;
  const hasEducationSection = labels.some((l) => l.section === "education");
  for (let i = 0; i < lines.length; i++) {
    if (hasEducationSection && labels[i].section !== "education") continue;
    if (!hasEducationSection && !EDU_HINT.test(lines[i])) continue;
    const hit = degreeOnLine(lines[i]);
    if (!hit) continue;
    if (!best || hit.rank < best.rank) best = { ...hit, index: i };
  }
  if (!best && hasEducationSection) {
    // The section header exists but its lines didn't hit; try the whole text.
    for (let i = 0; i < lines.length; i++) {
      if (!EDU_HINT.test(lines[i])) continue;
      const hit = degreeOnLine(lines[i]);
      if (hit && (!best || hit.rank < best.rank)) best = { ...hit, index: i };
    }
  }
  return best;
}

function extractGraduationYear(lines, index) {
  const maxYear = new Date().getFullYear() + 6;
  let latest = null;
  for (let i = index; i <= Math.min(lines.length - 1, index + 3); i++) {
    for (const m of lines[i].matchAll(/(?<!\d)(19[6-9]\d|20[0-3]\d)(?!\d)/g)) {
      const y = Number(m[1]);
      if (y >= 1960 && y <= 2039 && y <= maxYear && (latest === null || y > latest)) latest = y;
    }
  }
  return latest;
}

const COLLEGE_RE = /\b(universit(y|ies)|college|institute|institution|\biit\b|\bnit\b|\biiit\b|\biim\b|\bbits\b|polytechnic|vidyalaya|vidyapeeth|mahavidyalaya|academy|school of)\b/i;
const SCHOOL_RE = /\b(school|board|cbse|icse|isc|state board|senior secondary|higher secondary|matriculation|high school|vidyalaya|public school|convent)\b/i;

function cleanCollege(line) {
  let s = line
    .replace(/\(?\b(19|20)\d{2}\s*[-–—to]+\s*((19|20)\d{2}|\d{2}|present)\)?/gi, " ")
    .replace(/\b(19|20)\d{2}\b/g, " ")
    .replace(/\b(cgpa|gpa|percentage|score)\b.*$/i, " ")
    .replace(/\b\d+(\.\d+)?\s*(%|cgpa|gpa)\b.*$/i, " ")
    .replace(/\s+/g, " ")
    .trim();
  // "B.Tech in CSE | XYZ University" -> keep the segment that names the college.
  const parts = s.split(/\s*[|•]\s*|\s+[-–—]\s+|,\s+(?=[A-Z])/).map((p) => p.trim()).filter(Boolean);
  const hit = parts.find((p) => COLLEGE_RE.test(p));
  s = (hit || s).replace(/^[\s:,\-–—|]+|[\s:,\-–—|]+$/g, "");
  return s.slice(0, 120);
}

function findCollege(lines, degree) {
  const ok = (line) => COLLEGE_RE.test(line) && !SCHOOL_RE.test(line.replace(COLLEGE_RE, "")) && line.length <= 200;
  if (degree) {
    for (let d = 0; d <= 3; d++) {
      for (const i of d === 0 ? [degree.index] : [degree.index + d, degree.index - d]) {
        if (i >= 0 && i < lines.length && ok(lines[i])) return cleanCollege(lines[i]);
      }
    }
  }
  const any = lines.find((l) => ok(l) && !/\b(pvt|ltd|llp|technologies|solutions)\b/i.test(l));
  return any ? cleanCollege(any) : null;
}

// ------------------------------------------------- role, location, summary

function earliest(text, names, { skip = [] } = {}) {
  let best = null;
  for (const name of names) {
    if (skip.includes(name)) continue;
    const m = tokenRegex(name).exec(text);
    if (!m) continue;
    if (!best || m.index < best.at || (m.index === best.at && name.length > best.name.length)) {
      best = { name, at: m.index };
    }
  }
  return best ? best.name : null;
}

// ---------------------------------------------------------------- experience

const MONTHS = { jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8, oct: 9, nov: 10, dec: 11 };
const MONTH_RE = "(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)";
const PRESENT_RE = "(present|current|currently|till date|to date|till now|now|ongoing|date)";
// "Jan 2020", "Jan'20", "03/2020" or a bare year.
const POINT = `(?:${MONTH_RE}\\.?[\\s,'’-]*(\\d{4}|\\d{2})|(\\d{1,2})[/.](\\d{4})|(\\d{4}))`;
const RANGE_RE = new RegExp(`${POINT}\\s*(?:-|–|—|to|till|until)\\s*(?:${POINT}|${PRESENT_RE})`, "gi");

function pointToMonths(monthName, yearText, numMonth, numYear, bareYear) {
  let year;
  let month;
  if (monthName) {
    month = MONTHS[monthName.toLowerCase().slice(0, 3)];
    year = Number(yearText);
    if (year < 100) year += 2000;
  } else if (numMonth) {
    month = Math.max(1, Math.min(12, Number(numMonth))) - 1;
    year = Number(numYear);
  } else {
    year = Number(bareYear);
    month = 0; // a bare year counts from January to January
  }
  return year * 12 + month;
}

function parseRanges(line, nowMonths) {
  const ranges = [];
  for (const m of line.matchAll(RANGE_RE)) {
    const start = pointToMonths(m[1], m[2], m[3], m[4], m[5]);
    // Groups 1-5 are the start point, 6-10 the end point, 11 "Present".
    const hasEndPoint = Boolean(m[6] || m[8] || m[10]);
    // Both ends are inclusive: "Jan 2020 - Dec 2021" is 24 months.
    const end = (hasEndPoint ? pointToMonths(m[6], m[7], m[8], m[9], m[10]) : nowMonths) + 1;
    const isPresent = !hasEndPoint;
    if (!Number.isFinite(start) || !Number.isFinite(end)) continue;
    const startYear = Math.floor(start / 12);
    if (startYear < 1970 || startYear > 2100 || end < start) continue;
    ranges.push({ start, end: Math.min(end, nowMonths + 1), present: isPresent, index: m.index, length: m[0].length });
  }
  return ranges;
}

function mergedMonths(ranges) {
  const sorted = [...ranges].sort((a, b) => a.start - b.start);
  let total = 0;
  let curStart = null;
  let curEnd = null;
  for (const r of sorted) {
    if (curStart === null) {
      curStart = r.start;
      curEnd = r.end;
    } else if (r.start <= curEnd) {
      curEnd = Math.max(curEnd, r.end);
    } else {
      total += curEnd - curStart;
      curStart = r.start;
      curEnd = r.end;
    }
  }
  if (curStart !== null) total += curEnd - curStart;
  return total;
}

function statedExperience(text) {
  const nums = [];
  const patterns = [
    /(\d{1,2}(?:\.\d+)?)\s*\+?\s*(?:years?|yrs?)\.?\s*(?:and\s+\d+\s*months?\s*)?(?:of\s+)?(?:(?:total|professional|work|relevant|industry|overall|hands[- ]on|working|it)\s+)*experience/gi,
    /experience\s*(?:of|:|-|–|is|for|around|over)?\s*(?:around|over|about|nearly|more than)?\s*(\d{1,2}(?:\.\d+)?)\s*\+?\s*(?:years?|yrs?)/gi,
    /(?:over|around|more than|nearly|having|with)\s+(\d{1,2}(?:\.\d+)?)\s*\+?\s*(?:years?|yrs?)\b/gi,
  ];
  for (const re of patterns) {
    for (const m of text.matchAll(re)) {
      const n = Number(m[1]);
      if (Number.isFinite(n) && n <= 45) nums.push(n);
    }
  }
  return nums.length ? Math.max(...nums) : null;
}

// ------------------------------------------------- current company / post

const POST_WORDS =
  /\b(engineer|developer|manager|executive|analyst|designer|intern|trainee|lead|associate|consultant|officer|specialist|administrator|architect|head|director|coordinator|tester|recruiter|scientist|programmer|accountant|assistant|supervisor|representative|advisor|adviser|editor|writer|technician|strategist|operator|agent|telecaller|apprentice|founder|president|vp)\b/i;
const COMPANY_WORDS =
  /\b(pvt|private|ltd|limited|inc|llp|llc|corp|corporation|technologies|technology|solutions|systems|software|infotech|labs|services|consulting|consultancy|enterprises|group|industries|company|co\.|softech|digital|networks|ventures|studio|studios|global|international|bank|hospital|motors|pharma)\b/i;

const STRONG_COMPANY = /\b(pvt|private|ltd|limited|inc|llp|llc|corp|corporation)\b/i;
function isPost(part) {
  return POST_WORDS.test(part) && !STRONG_COMPANY.test(part);
}
function isCompany(part) {
  return STRONG_COMPANY.test(part) || (COMPANY_WORDS.test(part) && !POST_WORDS.test(part));
}

function splitParts(text) {
  return text
    .split(/\s*[|•]\s*|\s+[-–—]\s+|\s*@\s*|\s+at\s+|,\s+/i)
    .map((p) => p.replace(/^[\s:,\-–—|]+|[\s:,\-–—|]+$/g, "").trim())
    .filter((p) => p && p.length <= 80);
}

function currentRoleFromSentence(text) {
  const m = text.match(/currently\s+working\s+as\s+(?:an?\s+)?([^.\n,]{3,60}?)\s+(?:at|with|in)\s+([^.\n,]{2,60})/i);
  if (!m) return null;
  return { post: m[1].trim(), company: m[2].trim() };
}

function extractCurrentJob(lines, labels, ranges) {
  if (!ranges.length) return null;
  // The latest range: still running ranks above any finished one.
  const latest = [...ranges].sort((a, b) => (b.present - a.present) || (b.end - a.end) || (b.start - a.start))[0];
  const around = [lines[latest.line], lines[latest.line - 1], lines[latest.line + 1], lines[latest.line - 2]].filter((s) => typeof s === "string");
  const sameLine = lines[latest.line];
  const stripped = (sameLine.slice(0, latest.index) + " " + sameLine.slice(latest.index + latest.length)).replace(/[()[\]]/g, " ");
  const candidates = [stripped, ...around.slice(1)];

  let post = null;
  let company = null;
  for (const text of candidates) {
    if (SECTION_HEADERS.some(([, re]) => re.test(text.trim()))) continue;
    const parts = splitParts(text);
    for (const part of parts) {
      if (!company && isCompany(part)) company = part;
      else if (!post && isPost(part)) post = part;
    }
    // "Software Engineer" alone on a line with the company on the next one.
    if (post && company) break;
  }
  if (!company) {
    // Fall back to the first non-post part of the same/neighbouring line.
    for (const text of candidates) {
      const part = splitParts(text).find((p) => !isPost(p) && !/\d/.test(p) && p.split(/\s+/).length <= 5 && /^[A-Z]/.test(p));
      if (part) {
        company = part;
        break;
      }
    }
  }
  if (!post && !company) return null;
  return { post: post ? post.slice(0, 80) : null, company: company ? company.slice(0, 80) : null };
}

// --------------------------------------------------------------------- main

/**
 * @param {string} rawText the text of the resume
 * @param {{ now?: Date }} [options]
 * @returns {Object} only the fields found: phone, skills, degree,
 *   qualification, graduationYear, college, desiredRole, location,
 *   experienceYears, currentCompany, currentPost
 */
function extractProfile(rawText, { now = new Date() } = {}) {
  const text = cleanText(rawText);
  if (!text) return {};
  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const labels = labelSections(lines);
  const out = {};

  const phone = extractPhone(text);
  if (phone) out.phone = phone;

  const skills = extractSkills(lines, labels);
  if (skills.length) out.skills = skills;

  const degree = findDegree(lines, labels);
  if (degree) {
    if (DEGREES.includes(degree.name)) out.degree = degree.name;
    out.qualification = degree.rule.qualification;
    const year = extractGraduationYear(lines, degree.index);
    if (year) out.graduationYear = year;
  }
  const college = findCollege(lines, degree);
  if (college) out.college = college;

  const role = earliest(text, ROLES);
  if (role) out.desiredRole = role;

  const city = earliest(text, CITIES, { skip: ["Remote"] });
  if (city) out.location = city;

  // Experience: stated > summed date ranges > "fresher".
  const nowMonths = now.getFullYear() * 12 + now.getMonth();
  const jobRanges = [];
  lines.forEach((line, i) => {
    const { section } = labels[i];
    if (section === "education" || section === "projects" || section === "other" || section === "skills" || section === "languages") return;
    if (!section && degreeOnLine(line) && EDU_HINT.test(line)) return;
    for (const r of parseRanges(line, nowMonths)) jobRanges.push({ ...r, line: i });
  });

  const stated = statedExperience(text);
  if (stated !== null) {
    out.experienceYears = stated;
  } else if (jobRanges.length) {
    const years = Math.floor((mergedMonths(jobRanges) / 12) * 2) / 2;
    out.experienceYears = Math.min(years, 50);
  } else if (/\bfresher\b/i.test(text)) {
    out.experienceYears = 0;
  }

  const sentence = currentRoleFromSentence(text);
  const job = sentence ? { post: sentence.post.slice(0, 80), company: sentence.company.slice(0, 80) } : extractCurrentJob(lines, labels, jobRanges);
  if (job) {
    if (job.company) out.currentCompany = job.company;
    if (job.post) out.currentPost = job.post;
  }

  return out;
}

// --------------------------------------------------------------------- PDF

async function pdfToText(buffer) {
  // pdf-parse v2 exposes a class; it is loaded lazily so tests of the pure
  // extractor never need the PDF engine.
  const { PDFParse } = require("pdf-parse");
  const parser = new PDFParse({ data: new Uint8Array(buffer) });
  try {
    const result = await parser.getText();
    return result.text || "";
  } finally {
    await parser.destroy().catch(() => {});
  }
}

/** PDF bytes -> found fields. A scanned PDF (no text layer) gives {}. */
async function parseResumePdf(buffer) {
  const text = await pdfToText(buffer);
  return extractProfile(text);
}

module.exports = { extractProfile, parseResumePdf, pdfToText };
