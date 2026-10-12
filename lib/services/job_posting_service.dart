import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/job_posting.dart';
import '../models/opportunity.dart';

/// Firestore access for job postings: a recruiter creating/closing their
/// own, candidates browsing the open ones, applying to one (which creates
/// an [Opportunity] the recruiter then manages on their Pipeline tab), and
/// saving/un-saving postings for later.
class JobPostingService {
  JobPostingService._internal();
  static final JobPostingService instance = JobPostingService._internal();

  final CollectionReference<Map<String, dynamic>> _postings =
      FirebaseFirestore.instance.collection('job_postings');
  final CollectionReference<Map<String, dynamic>> _opportunities =
      FirebaseFirestore.instance.collection('opportunities');

  Future<String> create(JobPosting posting) async {
    final doc = await _postings.add(posting.toMap());
    return doc.id;
  }

  /// Full edit of an already-published posting -- keeps its id and
  /// original `createdAt` (passed through on [posting]) rather than
  /// bumping it to "now" like [create] would.
  Future<void> update(JobPosting posting) {
    return _postings.doc(posting.id).set(posting.toMap());
  }

  Future<void> setOpen(String postingId, bool isOpen) {
    return _postings.doc(postingId).update({'isOpen': isOpen});
  }

  Stream<List<JobPosting>> streamMyPostings(String recruiterUid) {
    return _postings
        .where('recruiterUid', isEqualTo: recruiterUid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => JobPosting.fromMap(d.id, d.data())).toList());
  }

  /// Every open posting, newest first -- the candidate's "Browse Jobs" tab.
  /// Not paginated: postings are a small, slow-growing collection compared
  /// to candidate accounts, so one bounded fetch is fine for now.
  Stream<List<JobPosting>> streamOpenPostings({int limit = 100}) {
    return _postings
        .where('isOpen', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map((d) => JobPosting.fromMap(d.id, d.data())).toList());
  }

  /// Whether this candidate already has an application (or any recruiter
  /// interaction) tied to this posting -- guards the Apply button against
  /// duplicate applications.
  Future<bool> hasApplied(String candidateUid, String jobPostingId) async {
    final query = await _opportunities
        .where('candidateUid', isEqualTo: candidateUid)
        .where('jobPostingId', isEqualTo: jobPostingId)
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<void> apply({
    required JobPosting posting,
    required String candidateUid,
    required String candidateName,
  }) async {
    final opportunity = Opportunity(
      candidateUid: candidateUid,
      candidateName: candidateName,
      recruiterUid: posting.recruiterUid,
      companyName: posting.companyName,
      recruiterName: posting.recruiterName,
      role: posting.title,
      jobPostingId: posting.id,
      status: OpportunityStatus.applied,
    );
    await _opportunities.add(opportunity.toMap());
  }

  // -- Saved jobs: candidate_profiles/{uid}/saved_jobs/{jobPostingId} --

  CollectionReference<Map<String, dynamic>> _savedJobsOf(String candidateUid) {
    return FirebaseFirestore.instance.collection('candidate_profiles').doc(candidateUid).collection('saved_jobs');
  }

  Future<void> saveJob(String candidateUid, String jobPostingId) {
    return _savedJobsOf(candidateUid).doc(jobPostingId).set({'savedAt': FieldValue.serverTimestamp()});
  }

  Future<void> unsaveJob(String candidateUid, String jobPostingId) {
    return _savedJobsOf(candidateUid).doc(jobPostingId).delete();
  }

  Stream<Set<String>> streamSavedJobIds(String candidateUid) {
    return _savedJobsOf(candidateUid).snapshots().map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  Future<JobPosting?> fetchById(String jobPostingId) async {
    final doc = await _postings.doc(jobPostingId).get();
    if (!doc.exists || doc.data() == null) return null;
    return JobPosting.fromMap(doc.id, doc.data()!);
  }
}
