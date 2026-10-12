import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_user.dart';
import '../models/opportunity.dart';

/// Firestore access for the recruiter <-> candidate hiring pipeline:
/// looking up a real candidate account by email, and creating/streaming
/// the [Opportunity] docs that track status/interview/offer between a
/// recruiter and that candidate.
class OpportunityService {
  OpportunityService._internal();
  static final OpportunityService instance = OpportunityService._internal();

  final CollectionReference<Map<String, dynamic>> _opportunities =
      FirebaseFirestore.instance.collection('opportunities');
  final CollectionReference<Map<String, dynamic>> _users = FirebaseFirestore.instance.collection('users');

  /// Looks up a candidate account by exact email match, for a recruiter to
  /// start a pipeline entry with. Returns null if no candidate account
  /// uses that email.
  Future<AppUser?> findCandidateByEmail(String email) async {
    final query = await _users
        .where('email', isEqualTo: email.trim())
        .where('role', isEqualTo: 'candidate')
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return AppUser.fromMap(query.docs.first.id, query.docs.first.data());
  }

  Future<String> save(Opportunity opportunity) async {
    if (opportunity.id.isEmpty) {
      final doc = await _opportunities.add(opportunity.toMap());
      return doc.id;
    }
    await _opportunities.doc(opportunity.id).set(opportunity.toMap());
    return opportunity.id;
  }

  /// Every opportunity for a candidate, newest update first -- what their
  /// dashboard's "Hiring Activity" section shows.
  Stream<List<Opportunity>> streamForCandidate(String candidateUid) {
    return _opportunities
        .where('candidateUid', isEqualTo: candidateUid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Opportunity.fromMap(d.id, d.data())).toList());
  }

  /// Every opportunity a recruiter has created -- their "Pipeline" tab.
  Stream<List<Opportunity>> streamForRecruiter(String recruiterUid) {
    return _opportunities
        .where('recruiterUid', isEqualTo: recruiterUid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Opportunity.fromMap(d.id, d.data())).toList());
  }
}
