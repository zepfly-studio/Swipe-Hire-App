import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/candidate.dart';
import '../models/candidate_profile.dart';

/// Reads real candidate accounts for the recruiter's swipe deck -- joining
/// each `users/{uid}` doc (role == candidate, profile complete) with its
/// `candidate_profiles/{uid}` doc (age, skills, resume, intro video, ...)
/// into the [Candidate] shape the swipe deck/resume/video screens expect.
///
/// A candidate only appears here once they've finished
/// CompleteProfileScreen, so recruiters never see a half-filled profile.
class CandidateService {
  CandidateService._internal();
  static final CandidateService instance = CandidateService._internal();

  final CollectionReference<Map<String, dynamic>> _users = FirebaseFirestore.instance.collection('users');
  final CollectionReference<Map<String, dynamic>> _profiles =
      FirebaseFirestore.instance.collection('candidate_profiles');

  Future<List<Candidate>> fetchCandidates() async {
    final userDocs = await _users
        .where('role', isEqualTo: 'candidate')
        .where('profileComplete', isEqualTo: true)
        .get();
    if (userDocs.docs.isEmpty) return [];

    final candidates = await Future.wait(userDocs.docs.map((userDoc) async {
      final profileDoc = await _profiles.doc(userDoc.id).get();
      if (!profileDoc.exists || profileDoc.data() == null) return null;
      final profile = CandidateProfile.fromMap(profileDoc.data()!);
      return _toCandidate(userDoc.id, userDoc.data(), profile);
    }));

    return candidates.whereType<Candidate>().toList();
  }

  Candidate _toCandidate(String uid, Map<String, dynamic> userData, CandidateProfile profile) {
    return Candidate(
      id: uid,
      name: userData['name'] ?? 'Unknown',
      age: profile.age,
      qualification: profile.qualification,
      experience: profile.experience,
      role: profile.desiredRole,
      location: profile.location,
      currentCompany: profile.currentCompany,
      currentSalaryLpa: profile.currentSalaryLpa,
      expectedSalaryLpa: profile.expectedSalaryLpa,
      skills: profile.skills,
      photoUrl: profile.photoUrl,
      resumeUrl: profile.resumeUrl,
      introVideoUrl: profile.introVideoUrl,
      about: profile.about,
      noticePeriod: profile.noticePeriod,
    );
  }
}
