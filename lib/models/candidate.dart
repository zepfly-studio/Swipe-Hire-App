class Candidate {
  final String id;
  final String name;
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

  Candidate({
    required this.id,
    required this.name,
    required this.age,
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
  });

  factory Candidate.fromMap(String id, Map<String, dynamic> map) {
    return Candidate(
      id: id,
      name: map['name'] ?? 'Unknown',
      age: (map['age'] ?? 0) as int,
      qualification: map['qualification'] ?? '-',
      experience: map['experience'] ?? '-',
      role: map['role'] ?? '-',
      location: map['location'] ?? '-',
      currentCompany: map['currentCompany'] ?? '-',
      currentSalaryLpa: (map['currentSalaryLpa'] ?? 0).toDouble(),
      expectedSalaryLpa: (map['expectedSalaryLpa'] ?? 0).toDouble(),
      skills: List<String>.from(map['skills'] ?? const []),
      photoUrl: map['photoUrl'] ?? '',
      resumeUrl: map['resumeUrl'] ?? '',
      introVideoUrl: map['introVideoUrl'] ?? '',
      about: map['about'] ?? '',
      noticePeriod: map['noticePeriod'] ?? '-',
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
