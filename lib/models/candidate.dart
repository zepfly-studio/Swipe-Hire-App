/// A candidate as a company sees them: on the swipe deck, wishlist and the
/// shortlisted pipeline. Age, gender, phone and email are never part of a
/// card; the phone/email appear only in [contactEmail]/[contactPhone] for a
/// candidate this company has shortlisted.
class Candidate {
  final String id;
  final String name;
  /// Not sent by the server on candidate cards any more; always 0 there and
  /// never shown to companies.
  final int age;
  final String qualification;
  final String experience;
  final String role;
  final String location;
  final String currentCompany;
  final double currentSalaryLpa;
  final double expectedSalaryLpa;
  final List<String> skills;
  final String photoUrl;
  final String resumeUrl;
  final String introVideoUrl;
  final String about;
  final String noticePeriod;

  // Website-parity profile fields (phase 1).
  final String degree;
  final String college;
  final int? graduationYear;
  final String currentPost;
  final double? expectedSalaryMaxLpa;
  final bool salaryNegotiable;
  final List<String> workModes;
  final List<String> jobTypes;
  final List<String> preferredLocations;

  /// How well this candidate fits the job being swiped on (0-100), which of
  /// the job's required skills they have, and which posting scored best.
  final int? matchScore;
  final String matchJobTitle;
  final List<String> matchReasons;
  final List<String> matchedSkills;

  /// In the company's wishlist.
  final bool wishlisted;

  // Present on shortlisted rows (GET /company/shortlisted) and on the wishlist
  // for candidates that were already shortlisted.
  /// The swipe row id (what PATCH /company/pipeline/:swipeId takes).
  final String swipeId;
  final String jobId;
  final String jobTitle;
  /// shortlisted | contacted | task | interview | hired | rejected
  final String stage;
  final String notes;
  final DateTime? shortlistedAt;
  final String contactEmail;
  final String contactPhone;

  Candidate({
    required this.id,
    required this.name,
    this.age = 0,
    required this.qualification,
    required this.experience,
    required this.role,
    required this.location,
    required this.currentCompany,
    required this.currentSalaryLpa,
    required this.expectedSalaryLpa,
    required this.skills,
    required this.photoUrl,
    required this.resumeUrl,
    required this.introVideoUrl,
    required this.about,
    required this.noticePeriod,
    this.degree = '',
    this.college = '',
    this.graduationYear,
    this.currentPost = '',
    this.expectedSalaryMaxLpa,
    this.salaryNegotiable = false,
    this.workModes = const [],
    this.jobTypes = const [],
    this.preferredLocations = const [],
    this.matchScore,
    this.matchJobTitle = '',
    this.matchReasons = const [],
    this.matchedSkills = const [],
    this.wishlisted = false,
    this.swipeId = '',
    this.jobId = '',
    this.jobTitle = '',
    this.stage = '',
    this.notes = '',
    this.shortlistedAt,
    this.contactEmail = '',
    this.contactPhone = '',
  });

  bool get hasContact => contactEmail.isNotEmpty || contactPhone.isNotEmpty;

  Candidate copyWith({bool? wishlisted, String? stage, String? notes}) {
    return Candidate(
      id: id,
      name: name,
      age: age,
      qualification: qualification,
      experience: experience,
      role: role,
      location: location,
      currentCompany: currentCompany,
      currentSalaryLpa: currentSalaryLpa,
      expectedSalaryLpa: expectedSalaryLpa,
      skills: skills,
      photoUrl: photoUrl,
      resumeUrl: resumeUrl,
      introVideoUrl: introVideoUrl,
      about: about,
      noticePeriod: noticePeriod,
      degree: degree,
      college: college,
      graduationYear: graduationYear,
      currentPost: currentPost,
      expectedSalaryMaxLpa: expectedSalaryMaxLpa,
      salaryNegotiable: salaryNegotiable,
      workModes: workModes,
      jobTypes: jobTypes,
      preferredLocations: preferredLocations,
      matchScore: matchScore,
      matchJobTitle: matchJobTitle,
      matchReasons: matchReasons,
      matchedSkills: matchedSkills,
      wishlisted: wishlisted ?? this.wishlisted,
      swipeId: swipeId,
      jobId: jobId,
      jobTitle: jobTitle,
      stage: stage ?? this.stage,
      notes: notes ?? this.notes,
      shortlistedAt: shortlistedAt,
      contactEmail: contactEmail,
      contactPhone: contactPhone,
    );
  }

  static List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

  factory Candidate.fromMap(String id, Map<String, dynamic> map) {
    final contact = map['contact'];
    final contactMap = contact is Map ? Map<String, dynamic>.from(contact) : const <String, dynamic>{};
    final job = map['job'];
    final jobMap = job is Map ? Map<String, dynamic>.from(job) : const <String, dynamic>{};
    return Candidate(
      id: id,
      name: map['name'] ?? 'Unknown',
      age: (map['age'] as num?)?.toInt() ?? 0, // the server no longer sends it on cards
      qualification: map['qualification'] ?? '-',
      experience: map['experience'] ?? '-',
      role: map['role'] ?? '-',
      location: map['location'] ?? '-',
      currentCompany: map['currentCompany'] ?? '-',
      currentSalaryLpa: (map['currentSalaryLpa'] ?? 0).toDouble(),
      expectedSalaryLpa: (map['expectedSalaryLpa'] ?? 0).toDouble(),
      skills: _strings(map['skills']),
      photoUrl: map['photoUrl'] ?? '',
      resumeUrl: map['resumeUrl'] ?? '',
      introVideoUrl: map['introVideoUrl'] ?? '',
      about: map['about'] ?? '',
      noticePeriod: map['noticePeriod'] ?? '-',
      degree: map['degree'] ?? '',
      college: map['college'] ?? '',
      graduationYear: (map['graduationYear'] as num?)?.toInt(),
      currentPost: map['currentPost'] ?? '',
      expectedSalaryMaxLpa: (map['expectedSalaryMaxLpa'] as num?)?.toDouble(),
      salaryNegotiable: map['salaryNegotiable'] == true,
      workModes: _strings(map['workModes']),
      jobTypes: _strings(map['jobTypes']),
      preferredLocations: _strings(map['preferredLocations']),
      matchScore: (map['matchScore'] as num?)?.toInt(),
      matchJobTitle: map['matchJobTitle'] ?? '',
      matchReasons: _strings(map['matchReasons']),
      matchedSkills: _strings(map['matchedSkills']),
      wishlisted: map['wishlisted'] == true,
      swipeId: (map['swipeId'] ?? '').toString(),
      jobId: (map['jobId'] ?? jobMap['id'] ?? '').toString(),
      jobTitle: (map['jobTitle'] ?? jobMap['title'] ?? '').toString(),
      stage: (map['stage'] ?? '').toString(),
      notes: (map['notes'] ?? '').toString(),
      shortlistedAt: DateTime.tryParse((map['shortlistedAt'] ?? '').toString()),
      contactEmail: (contactMap['email'] ?? '').toString(),
      contactPhone: (contactMap['phone'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'age': age,
      'qualification': qualification,
      'experience': experience,
      'role': role,
      'location': location,
      'currentCompany': currentCompany,
      'currentSalaryLpa': currentSalaryLpa,
      'expectedSalaryLpa': expectedSalaryLpa,
      'skills': skills,
      'photoUrl': photoUrl,
      'resumeUrl': resumeUrl,
      'introVideoUrl': introVideoUrl,
      'about': about,
      'noticePeriod': noticePeriod,
    };
  }
}
