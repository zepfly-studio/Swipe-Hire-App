const { isAdminUser } = require("./admin");
// JSON shapes the Flutter models (lib/models/*.dart) parse with fromMap().
// Dates go out as ISO-8601 strings; names/companies are joined from users so
// a rename shows up everywhere without denormalised copies to keep in sync.

function iso(date) {
  return date ? date.toISOString() : null;
}

function toProfile(user) {
  return {
    uid: user.id,
    email: user.email,
    name: user.name,
    role: user.role,
    company: user.company,
    designation: user.designation,
    phone: user.phone,
    profileComplete: user.profileComplete,
    emailVerified: user.emailVerified,
    emailNotifications: user.emailNotifications,
    // Team + admin (phase 4). companyId is the hiring account's id: the owner
    // for a team member, the recruiter's own id otherwise.
    isAdmin: isAdminUser(user),
    isOwner: user.role === "recruiter" && !user.companyOwnerId,
    companyId: user.role === "recruiter" ? user.companyOwnerId || user.id : "",
  };
}

// The candidate's own profile (they see everything, including age, gender
// and phone). Recruiters never get this shape -- see toCandidate below.
function toCandidateProfile(p) {
  return {
    age: p.age,
    gender: p.gender ?? "",
    phone: p.phone ?? "",
    qualification: p.qualification,
    degree: p.degree ?? "",
    college: p.college ?? "",
    graduationYear: p.graduationYear ?? null,
    experience: p.experience,
    desiredRole: p.desiredRole,
    location: p.location,
    skills: p.skills,
    expectedSalaryLpa: p.expectedSalaryLpa,
    expectedSalaryMaxLpa: p.expectedSalaryMaxLpa ?? null,
    salaryNegotiable: p.salaryNegotiable ?? false,
    noticePeriod: p.noticePeriod,
    about: p.about,
    currentCompany: p.currentCompany,
    currentPost: p.currentPost ?? "",
    currentSalaryLpa: p.currentSalaryLpa,
    workModes: p.workModes ?? [],
    jobTypes: p.jobTypes ?? [],
    preferredLocations: p.preferredLocations ?? [],
    openToWork: p.openToWork ?? true,
    activeAt: iso(p.activeAt),
    photoUrl: p.photoUrl,
    resumeUrl: p.resumeUrl,
    introVideoUrl: p.introVideoUrl,
  };
}

// The swipe-deck card: users row joined with its candidate_profiles row.
// `match` is { score, jobTitle, reasons } from lib/matching.js, when known.
// Cards are what a recruiter sees BEFORE contacting anyone, so they never
// carry age, gender, phone or email.
function toCandidate(user, profile, match = null) {
  const p = profile || {};
  return {
    id: user.id,
    name: user.name,
    qualification: p.qualification ?? "",
    degree: p.degree ?? "",
    college: p.college ?? "",
    graduationYear: p.graduationYear ?? null,
    experience: p.experience ?? "",
    role: p.desiredRole ?? "",
    location: p.location ?? "",
    currentCompany: p.currentCompany ?? "",
    currentPost: p.currentPost ?? "",
    currentSalaryLpa: p.currentSalaryLpa ?? 0,
    expectedSalaryLpa: p.expectedSalaryLpa ?? 0,
    expectedSalaryMaxLpa: p.expectedSalaryMaxLpa ?? null,
    salaryNegotiable: p.salaryNegotiable ?? false,
    skills: p.skills ?? [],
    workModes: p.workModes ?? [],
    jobTypes: p.jobTypes ?? [],
    preferredLocations: p.preferredLocations ?? [],
    photoUrl: p.photoUrl ?? "",
    resumeUrl: p.resumeUrl ?? "",
    introVideoUrl: p.introVideoUrl ?? "",
    about: p.about ?? "",
    noticePeriod: p.noticePeriod ?? "",
    activeAt: iso(p.activeAt),
    matchScore: match ? match.score : null,
    matchJobTitle: match ? match.jobTitle ?? "" : "",
    matchReasons: match ? match.reasons ?? [] : [],
  };
}

// `own: true` is the recruiter looking at their own company: it adds the
// credit balance and the private contact fields. The public company page
// (any signed-in account) never gets those.
function toCompany(c, { own = false } = {}) {
  const base = {
    id: c.id,
    name: c.name,
    website: c.website,
    about: c.about,
    industry: c.industry,
    size: c.size,
    location: c.location,
    logoUrl: c.logoUrl,
    address: c.address ?? "",
    linkedin: c.linkedin ?? "",
    foundedYear: c.foundedYear ?? null,
    // Raw value: unverified | pending | verified | rejected. `verified` is
    // true only for "verified" (what candidates see as the badge).
    verificationStatus: c.verificationStatus,
    verified: c.verificationStatus === "verified",
    verifiedAt: iso(c.verifiedAt),
  };
  if (!own) return base;
  return {
    ...base,
    // "email" | "gst" | "" and the GSTIN last submitted: the owner's view only.
    verificationMethod: c.verificationMethod || (c.verificationStatus === "verified" && c.verificationNote === "domain" ? "email" : ""),
    gstin: c.gstin ?? "",
    phone: c.phone ?? "",
    contactEmail: c.contactEmail ?? "",
    swipesLeft: c.swipesLeft ?? 0,
    swipesPurchased: c.swipesPurchased ?? 0,
  };
}

// open | paused | closed. `isOpen` is authoritative for "open"; rows that
// predate the status column (isOpen=false, status left at its default) are
// shown as paused.
function jobStatus(posting) {
  if (posting.isOpen) return "open";
  return posting.status === "closed" ? "closed" : "paused";
}

// `posting.recruiter` (with its `companyProfile`) must be included.
// `extra` can carry { matchScore, matchReasons, applicantsCount }.
function toJobPosting(posting, extra = {}) {
  const profile = posting.recruiter?.companyProfile;
  return {
    id: posting.id,
    recruiterUid: posting.recruiterId,
    recruiterName: posting.recruiter?.name ?? "",
    companyName: profile?.name || posting.recruiter?.company || "",
    companyId: profile?.id ?? "",
    companyVerified: profile?.verificationStatus === "verified",
    companyLogoUrl: profile?.logoUrl ?? "",
    title: posting.title,
    description: posting.description,
    skills: posting.skills,
    location: posting.location,
    employmentType: posting.employmentType,
    workMode: posting.workMode ?? "onsite",
    openings: posting.openings ?? 1,
    salaryMinLpa: posting.salaryMinLpa,
    salaryMaxLpa: posting.salaryMaxLpa,
    minExperienceYears: posting.minExperienceYears ?? 0,
    maxExperienceYears: posting.maxExperienceYears ?? null,
    status: jobStatus(posting),
    isOpen: posting.isOpen,
    createdAt: iso(posting.createdAt),
    matchScore: extra.matchScore ?? null,
    matchReasons: extra.matchReasons ?? [],
    applicantsCount: extra.applicantsCount ?? null,
    stats: extra.stats ?? null,
  };
}

function toTask(t) {
  return {
    id: t.id,
    opportunityId: t.opportunityId,
    title: t.title,
    description: t.description,
    link: t.link,
    dueDate: iso(t.dueDate),
    status: t.status,
    answer: t.answer,
    submissionLink: t.submissionLink,
    submissionFileUrl: t.submissionFileUrl,
    submissionFileName: t.submissionFileName,
    submittedAt: iso(t.submittedAt),
    feedback: t.feedback,
    reviewedAt: iso(t.reviewedAt),
    createdAt: iso(t.createdAt),
  };
}

// The task that needs attention first: one waiting on the candidate, then
// one waiting on the recruiter, then the newest. The app uses the same rule
// (Opportunity.task) so both ends agree on which one to show on a tile.
function primaryTask(tasks) {
  if (!tasks || tasks.length === 0) return null;
  const byNewest = [...tasks].sort((a, b) => b.createdAt - a.createdAt);
  return (
    byNewest.find((t) => t.status === "assigned") ||
    byNewest.find((t) => t.status === "submitted") ||
    byNewest[0]
  );
}

// `opportunity.candidate` and `.recruiter` must be included in the query;
// `.tasks` (newest first) is optional. `extra.unreadCount` is how many chat
// messages from the other side the viewer hasn't opened yet.
function toOpportunity(o, extra = {}) {
  const tasks = o.tasks || [];
  const primary = primaryTask(tasks);
  const profile = o.recruiter?.companyProfile;
  return {
    id: o.id,
    candidateUid: o.candidateId,
    candidateName: o.candidate?.name ?? "",
    recruiterUid: o.recruiterId,
    recruiterName: o.recruiter?.name ?? "",
    companyName: profile?.name || o.recruiter?.company || "Hiring company",
    companyVerified: profile?.verificationStatus === "verified",
    role: o.role,
    jobPostingId: o.jobPostingId ?? "",
    status: o.status,
    interviewDate: iso(o.interviewDate),
    interviewMode: o.interviewMode,
    interviewDetails: o.interviewDetails,
    interviewResponse: o.interviewResponse ?? "",
    interviewResponseNote: o.interviewResponseNote ?? "",
    offerSalaryLpa: o.offerSalaryLpa,
    offerJoiningDate: iso(o.offerJoiningDate),
    offerNotes: o.offerNotes,
    offerResponse: o.offerResponse ?? "",
    updatedAt: iso(o.updatedAt),
    task: primary ? toTask(primary) : null,
    tasks: tasks.map(toTask),
    unreadCount: extra.unreadCount ?? 0,
  };
}

// `message.sender` must be included in the query.
function toMessage(m) {
  return {
    id: m.id,
    senderUid: m.senderId,
    senderName: m.sender?.name ?? "",
    text: m.text,
    kind: m.kind || "text",
    sentAt: iso(m.sentAt),
  };
}

function toNotification(n) {
  return {
    id: n.id,
    type: n.type,
    title: n.title,
    body: n.body,
    opportunityId: n.opportunityId ?? "",
    link: n.link ?? "",
    read: Boolean(n.readAt),
    createdAt: iso(n.createdAt),
  };
}

const COMPANY_SELECT = { select: { id: true, name: true, logoUrl: true, verificationStatus: true } };

const OPPORTUNITY_INCLUDE = {
  candidate: { select: { name: true } },
  recruiter: { select: { name: true, company: true, companyProfile: COMPANY_SELECT } },
  tasks: { orderBy: { createdAt: "desc" }, take: 10 },
};

const POSTING_INCLUDE = {
  recruiter: { select: { name: true, company: true, companyProfile: COMPANY_SELECT } },
};

module.exports = {
  toProfile,
  toCandidateProfile,
  toCandidate,
  toCompany,
  jobStatus,
  toJobPosting,
  toOpportunity,
  toTask,
  toMessage,
  toNotification,
  primaryTask,
  OPPORTUNITY_INCLUDE,
  POSTING_INCLUDE,
};
