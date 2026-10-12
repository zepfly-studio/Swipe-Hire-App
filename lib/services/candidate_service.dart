import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/candidate.dart';
import '../models/candidate_profile.dart';

/// One page of [fetchCandidatesPage] -- the candidates themselves, plus
/// the cursor ([lastDoc]) to pass back in for the next page and whether
/// there's likely more behind it.
class CandidatePage {
  final List<Candidate> candidates;
  final DocumentSnapshot<Map<String, dynamic>>? lastDoc;
  final bool hasMore;

  const CandidatePage({required this.candidates, required this.lastDoc, required this.hasMore});
}

/// Reads real candidate accounts for the recruiter's swipe deck -- joining
/// each `users/{uid}` doc (role == candidate, profile complete) with its
/// `candidate_profiles/{uid}` doc (age, skills, resume, intro video, ...)
/// into the [Candidate] shape the swipe deck/resume/video screens expect.
///
/// Paginated ([fetchCandidatesPage]) rather than one big `.get()`, so the
/// swipe deck stays fast and cheap even with thousands of candidates --
/// [HomeSwipeScreen] fetches the next page only once it's running low on
/// un-swiped cards.
///
/// A candidate only appears here once they've finished
/// CompleteProfileScreen, so recruiters never see a half-filled profile.
class CandidateService {
  CandidateService._internal();
  static final CandidateService instance = CandidateService._internal();

  static const int defaultPageSize = 20;

  final CollectionReference<Map<String, dynamic>> _users = FirebaseFirestore.instance.collection('users');
  final CollectionReference<Map<String, dynamic>> _profiles =
      FirebaseFirestore.instance.collection('candidate_profiles');

  Future<CandidatePage> fetchCandidatesPage({
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = defaultPageSize,
  }) async {
    Query<Map<String, dynamic>> query = _users
        .where('role', isEqualTo: 'candidate')
        .where('profileComplete', isEqualTo: true)
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final userDocs = await query.get();
    if (userDocs.docs.isEmpty) {
      return const CandidatePage(candidates: [], lastDoc: null, hasMore: false);
    }

    final candidates = await Future.wait(userDocs.docs.map((userDoc) async {
      final profileDoc = await _profiles.doc(userDoc.id).get();
      if (!profileDoc.exists || profileDoc.data() == null) return null;
      final profile = CandidateProfile.fromMap(profileDoc.data()!);
      return _toCandidate(userDoc.id, userDoc.data(), profile);
    }));

    return CandidatePage(
      candidates: candidates.whereType<Candidate>().toList(),
      lastDoc: userDocs.docs.last,
      hasMore: userDocs.docs.length == pageSize,
    );
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
