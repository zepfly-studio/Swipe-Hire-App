/// The details a candidate account fills in on [CompleteProfileScreen] --
/// stored in `candidate_profiles/{uid}`, separate from the `users/{uid}`
/// account doc. Mirrors every field recruiters see on a [Candidate] card
/// (photo, resume, intro video, current company/CTC) so a candidate's own
/// upload is exactly what shows up on the recruiter's swipe deck.
class CandidateProfile {
  final int age;
  final String qualification;
  final String experience;
  final String desiredRole;
  final String location;
  final List<String> skills;
  final double expectedSalaryLpa;
  final String noticePeriod;
  final String about;
  final String currentCompany;
  final double currentSalaryLpa;
  final String photoUrl;
  final String resumeUrl;
  final String introVideoUrl;

  const CandidateProfile({
    required this.age,
    required this.qualification,
    required this.experience,
    required this.desiredRole,
    required this.location,
    required this.skills,
    required this.expectedSalaryLpa,
    required this.noticePeriod,
    this.about = '',
    this.currentCompany = '',
    this.currentSalaryLpa = 0,
    this.photoUrl = '',
    this.resumeUrl = '',
    this.introVideoUrl = '',
  });

  factory CandidateProfile.fromMap(Map<String, dynamic> map) {
    return CandidateProfile(
      age: (map['age'] ?? 0) as int,
      qualification: map['qualification'] ?? '',
      experience: map['experience'] ?? '',
      desiredRole: map['desiredRole'] ?? '',
      location: map['location'] ?? '',
      skills: List<String>.from(map['skills'] ?? const []),
      expectedSalaryLpa: (map['expectedSalaryLpa'] ?? 0).toDouble(),
      noticePeriod: map['noticePeriod'] ?? '',
      about: map['about'] ?? '',
      currentCompany: map['currentCompany'] ?? '',
      currentSalaryLpa: (map['currentSalaryLpa'] ?? 0).toDouble(),
      photoUrl: map['photoUrl'] ?? '',
      resumeUrl: map['resumeUrl'] ?? '',
      introVideoUrl: map['introVideoUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'age': age,
      'qualification': qualification,
      'experience': experience,
      'desiredRole': desiredRole,
      'location': location,
      'skills': skills,
      'expectedSalaryLpa': expectedSalaryLpa,
      'noticePeriod': noticePeriod,
      'about': about,
      'currentCompany': currentCompany,
      'currentSalaryLpa': currentSalaryLpa,
      'photoUrl': photoUrl,
      'resumeUrl': resumeUrl,
      'introVideoUrl': introVideoUrl,
    };
  }

  CandidateProfile copyWith({String? photoUrl, String? resumeUrl, String? introVideoUrl}) {
    return CandidateProfile(
      age: age,
      qualification: qualification,
      experience: experience,
      desiredRole: desiredRole,
      location: location,
      skills: skills,
      expectedSalaryLpa: expectedSalaryLpa,
      noticePeriod: noticePeriod,
      about: about,
      currentCompany: currentCompany,
      currentSalaryLpa: currentSalaryLpa,
      photoUrl: photoUrl ?? this.photoUrl,
      resumeUrl: resumeUrl ?? this.resumeUrl,
      introVideoUrl: introVideoUrl ?? this.introVideoUrl,
    );
  }
}
