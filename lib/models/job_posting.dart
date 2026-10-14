/// A role a recruiter is hiring for (backend: `job_postings` table),
/// browsable by every candidate account. Candidates apply to it
/// (JobPostingService.apply), which creates an [Opportunity] the recruiter
/// then manages on their Pipeline tab exactly like a recruiter-initiated
/// contact.
class JobPosting {
  final String id;
  final String recruiterUid;
  final String recruiterName;
  final String companyName;
  final String companyId;
  final bool companyVerified;
  final String companyLogoUrl;
  final String title;
  final String description;
  final List<String> skills;
  final String location;
  final String employmentType;
  final double salaryMinLpa;
  final double salaryMaxLpa;

  /// Years of experience the role asks for; 0 means open to freshers.
  final double minExperienceYears;
  final bool isOpen;
  final DateTime? createdAt;

  /// How well the signed-in candidate fits (0-100), when the backend knows
  /// their profile. Null for recruiters and for candidates with no profile.
  final int? matchScore;
  final List<String> matchReasons;

  /// How many people applied, on the recruiter's own listing only.
  final int? applicantsCount;

  const JobPosting({
    this.id = '',
    required this.recruiterUid,
    required this.recruiterName,
    required this.companyName,
    this.companyId = '',
    this.companyVerified = false,
    this.companyLogoUrl = '',
    required this.title,
    required this.description,
    required this.skills,
    required this.location,
    required this.employmentType,
    this.salaryMinLpa = 0,
    this.salaryMaxLpa = 0,
    this.minExperienceYears = 0,
    this.isOpen = true,
    this.createdAt,
    this.matchScore,
    this.matchReasons = const [],
    this.applicantsCount,
  });

  factory JobPosting.fromMap(String id, Map<String, dynamic> map) {
    return JobPosting(
      id: id,
      recruiterUid: map['recruiterUid'] ?? '',
      recruiterName: map['recruiterName'] ?? '',
      companyName: map['companyName'] ?? '',
      companyId: map['companyId'] ?? '',
      companyVerified: map['companyVerified'] == true,
      companyLogoUrl: map['companyLogoUrl'] ?? '',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      skills: List<String>.from(map['skills'] ?? const []),
      location: map['location'] ?? '',
      employmentType: map['employmentType'] ?? '',
      salaryMinLpa: (map['salaryMinLpa'] ?? 0).toDouble(),
      salaryMaxLpa: (map['salaryMaxLpa'] ?? 0).toDouble(),
      minExperienceYears: (map['minExperienceYears'] ?? 0).toDouble(),
      isOpen: map['isOpen'] ?? true,
      createdAt: DateTime.tryParse(map['createdAt']?.toString() ?? '')?.toLocal(),
      matchScore: (map['matchScore'] as num?)?.toInt(),
      matchReasons: List<String>.from(map['matchReasons'] ?? const []),
      applicantsCount: (map['applicantsCount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'recruiterUid': recruiterUid,
      'recruiterName': recruiterName,
      'companyName': companyName,
      'title': title,
      'description': description,
      'skills': skills,
      'location': location,
      'employmentType': employmentType,
      'salaryMinLpa': salaryMinLpa,
      'salaryMaxLpa': salaryMaxLpa,
      'minExperienceYears': minExperienceYears,
      'isOpen': isOpen,
      'createdAt': createdAt?.toUtc().toIso8601String(),
    };
  }
}
