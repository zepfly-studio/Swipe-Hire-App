import '../utils/derive.dart';

int _int(dynamic v) {
  if (v is num) return v.round();
  if (v is String) {
    return int.tryParse(v.trim()) ?? double.tryParse(v.trim())?.round() ?? 0;
  }
  return 0;
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

List<String> _strings(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e != null && e.toString().trim().isNotEmpty) e.toString(),
      ]
    : const [];

/// The details a candidate fills in during onboarding (and edits later) --
/// `GET/PUT /candidates/me/profile`. Mirrors every field companies see on a
/// candidate card, plus the candidate's own preferences. Parsing is lenient:
/// numbers may arrive as strings, lists may be missing.
class CandidateProfile {
  final int age;
  final String gender;
  final String qualification;
  final String degree;
  final String college;
  final int graduationYear; // 0 = not set
  final String experience; // free text: "Fresher" or "3 years"
  final String desiredRole; // "Role you are looking for"
  final String location;
  final List<String> skills;
  final String currentCompany;
  final String currentPost;
  final double currentSalaryLpa;
  final double expectedSalaryLpa; // minimum
  final double expectedSalaryMaxLpa; // 0 = not set
  final bool salaryNegotiable;
  final String noticePeriod;
  final List<String> workModes; // onsite | hybrid | remote
  final List<String> jobTypes; // full-time | part-time | internship | contract
  final String about;
  final String phone;
  final String photoUrl;
  final String resumeUrl;
  final String introVideoUrl;

  // Preferences / activity (written through their own endpoints).
  final bool openToWork;
  final List<String> preferredLocations;
  final DateTime? activeAt;

  const CandidateProfile({
    this.age = 0,
    this.gender = '',
    this.qualification = '',
    this.degree = '',
    this.college = '',
    this.graduationYear = 0,
    this.experience = '',
    this.desiredRole = '',
    this.location = '',
    this.skills = const [],
    this.currentCompany = '',
    this.currentPost = '',
    this.currentSalaryLpa = 0,
    this.expectedSalaryLpa = 0,
    this.expectedSalaryMaxLpa = 0,
    this.salaryNegotiable = false,
    this.noticePeriod = '',
    this.workModes = const [],
    this.jobTypes = const [],
    this.about = '',
    this.phone = '',
    this.photoUrl = '',
    this.resumeUrl = '',
    this.introVideoUrl = '',
    this.openToWork = true,
    this.preferredLocations = const [],
    this.activeAt,
  });

  /// Years of experience as a number (0 for "Fresher" or empty).
  double get experienceYears => parseExperienceYears(experience);

  factory CandidateProfile.fromMap(Map<String, dynamic> raw) {
    // Tolerate an envelope like {profile: {...}}.
    final map = raw['profile'] is Map
        ? Map<String, dynamic>.from(raw['profile'] as Map)
        : raw;

    var experience = _str(map['experience']).trim();
    if (experience.isEmpty && map['experienceYears'] != null) {
      final y = _double(map['experienceYears']);
      experience = y <= 0
          ? 'Fresher'
          : '${y == y.roundToDouble() ? y.round() : y} years';
    }
    final desiredRole = _str(map['desiredRole']).isNotEmpty
        ? _str(map['desiredRole'])
        : _str(map['headline']);
    final video = _str(map['introVideoUrl']).isNotEmpty
        ? _str(map['introVideoUrl'])
        : _str(map['videoUrl']);
    final photo = _str(map['photoUrl']).isNotEmpty
        ? _str(map['photoUrl'])
        : _str(map['avatarUrl']);
    final active = map['activeAt'] ?? map['updatedAt'];

    return CandidateProfile(
      age: _int(map['age']),
      gender: _str(map['gender']),
      qualification: _str(map['qualification']),
      degree: _str(map['degree']),
      college: _str(map['college']),
      graduationYear: _int(map['graduationYear']),
      experience: experience,
      desiredRole: desiredRole,
      location: _str(map['location']),
      skills: _strings(map['skills']),
      currentCompany: _str(map['currentCompany']),
      currentPost: _str(map['currentPost']),
      currentSalaryLpa: _double(map['currentSalaryLpa']),
      expectedSalaryLpa: _double(map['expectedSalaryLpa']),
      expectedSalaryMaxLpa: _double(map['expectedSalaryMaxLpa']),
      salaryNegotiable: map['salaryNegotiable'] == true,
      noticePeriod: _str(map['noticePeriod']),
      workModes: _strings(map['workModes']),
      jobTypes: _strings(map['jobTypes']),
      about: _str(map['about']),
      phone: _str(map['phone']),
      photoUrl: photo,
      resumeUrl: _str(map['resumeUrl']),
      introVideoUrl: video,
      openToWork: map['openToWork'] != false,
      preferredLocations: _strings(map['preferredLocations']),
      activeAt: active is String ? DateTime.tryParse(active)?.toLocal() : null,
    );
  }

  /// The body of `PUT /candidates/me/profile`. Preferences (openToWork,
  /// preferredLocations) and activeAt have their own endpoints.
  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'gender': gender,
      'qualification': qualification,
      'degree': degree,
      'college': college,
      'graduationYear': graduationYear > 0 ? graduationYear : null,
      'desiredRole': desiredRole,
      'location': location,
      'skills': skills,
      'experience': experience,
      'currentCompany': currentCompany,
      'currentPost': currentPost,
      'currentSalaryLpa': currentSalaryLpa,
      'expectedSalaryLpa': expectedSalaryLpa,
      'expectedSalaryMaxLpa': expectedSalaryMaxLpa,
      'salaryNegotiable': salaryNegotiable,
      'noticePeriod': noticePeriod,
      'workModes': workModes,
      'jobTypes': jobTypes,
      'about': about,
      'phone': phone,
      'photoUrl': photoUrl,
      'resumeUrl': resumeUrl,
      'introVideoUrl': introVideoUrl,
    };
  }

  CandidateProfile copyWith({
    String? photoUrl,
    String? resumeUrl,
    String? introVideoUrl,
    bool? openToWork,
    List<String>? workModes,
    List<String>? jobTypes,
    List<String>? preferredLocations,
    DateTime? activeAt,
  }) {
    return CandidateProfile(
      age: age,
      gender: gender,
      qualification: qualification,
      degree: degree,
      college: college,
      graduationYear: graduationYear,
      experience: experience,
      desiredRole: desiredRole,
      location: location,
      skills: skills,
      currentCompany: currentCompany,
      currentPost: currentPost,
      currentSalaryLpa: currentSalaryLpa,
      expectedSalaryLpa: expectedSalaryLpa,
      expectedSalaryMaxLpa: expectedSalaryMaxLpa,
      salaryNegotiable: salaryNegotiable,
      noticePeriod: noticePeriod,
      workModes: workModes ?? this.workModes,
      jobTypes: jobTypes ?? this.jobTypes,
      about: about,
      phone: phone,
      photoUrl: photoUrl ?? this.photoUrl,
      resumeUrl: resumeUrl ?? this.resumeUrl,
      introVideoUrl: introVideoUrl ?? this.introVideoUrl,
      openToWork: openToWork ?? this.openToWork,
      preferredLocations: preferredLocations ?? this.preferredLocations,
      activeAt: activeAt ?? this.activeAt,
    );
  }
}
