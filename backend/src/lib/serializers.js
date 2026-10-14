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
  };
}

function toCandidateProfile(p) {
  return {
    age: p.age,
    qualification: p.qualification,
    experience: p.experience,
    desiredRole: p.desiredRole,
    location: p.location,
    skills: p.skills,
    expectedSalaryLpa: p.expectedSalaryLpa,
    noticePeriod: p.noticePeriod,
    about: p.about,
    currentCompany: p.currentCompany,
    currentSalaryLpa: p.currentSalaryLpa,
    photoUrl: p.photoUrl,
    resumeUrl: p.resumeUrl,
    introVideoUrl: p.introVideoUrl,
  };
}

// The swipe-deck card: users row joined with its candidate_profiles row.
// `match` is { score, jobTitle, reasons } from lib/matching.js, when known.
function toCandidate(user, profile, match = null) {
  const p = profile || {};
  return {
    id: user.id,
    name: user.name,
    age: p.age ?? 0,
    qualification: p.qualification ?? "",
    experience: p.experience ?? "",
    role: p.desiredRole ?? "",
    location: p.location ?? "",
    currentCompany: p.currentCompany ?? "",
    currentSalaryLpa: p.currentSalaryLpa ?? 0,
    expectedSalaryLpa: p.expectedSalaryLpa ?? 0,
    skills: p.skills ?? [],
    photoUrl: p.photoUrl ?? "",
    resumeUrl: p.resumeUrl ?? "",
    introVideoUrl: p.introVideoUrl ?? "",
    about: p.about ?? "",
    noticePeriod: p.noticePeriod ?? "",
    matchScore: match ? match.score : null,
    matchJobTitle: match ? match.jobTitle ?? "" : "",
    matchReasons: match ? match.reasons ?? [] : [],
  };
}

function toCompany(c) {
  return {
    id: c.id,
    name: c.name,
    website: c.website,
    about: c.about,
    industry: c.industry,
    size: c.size,
    location: c.location,
    logoUrl: c.logoUrl,
    verificationStatus: c.verificationStatus,
    verified: c.verificationStatus === "verified",
    verifiedAt: iso(c.verifiedAt),
  };
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
    salaryMinLpa: posting.salaryMinLpa,
    salaryMaxLpa: posting.salaryMaxLpa,
    minExperienceYears: posting.minExperienceYears ?? 0,
    isOpen: posting.isOpen,
    createdAt: iso(posting.createdAt),
    matchScore: extra.matchScore ?? null,
    matchReasons: extra.matchReasons ?? [],
    applicantsCount: extra.applicantsCount ?? null,
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
  toJobPosting,
  toOpportunity,
  toTask,
  toMessage,
  toNotification,
  primaryTask,
  OPPORTUNITY_INCLUDE,
  POSTING_INCLUDE,
};
