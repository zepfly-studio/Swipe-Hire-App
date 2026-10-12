import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../models/candidate_profile.dart';
import 'cloudinary_service.dart';

/// Firestore-backed storage for a candidate account's own profile details
/// (`candidate_profiles/{uid}`), filled in once on [CompleteProfileScreen],
/// plus the photo/resume/intro video a candidate attaches to that profile
/// -- the same fields recruiters see (double-tap for resume, swipe for
/// video) on the swipe-deck [Candidate] card. Those uploads go to
/// Cloudinary (see [CloudinaryService]), not Firebase Storage, since this
/// project stays on Firebase's free Spark plan, which Cloud Storage no
/// longer supports for new projects.
class CandidateProfileService {
  CandidateProfileService._internal();
  static final CandidateProfileService instance = CandidateProfileService._internal();

  final CollectionReference<Map<String, dynamic>> _profiles =
      FirebaseFirestore.instance.collection('candidate_profiles');

  Future<void> save(String uid, CandidateProfile profile) {
    return _profiles.doc(uid).set(profile.toMap());
  }

  Future<CandidateProfile?> fetch(String uid) async {
    final doc = await _profiles.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return CandidateProfile.fromMap(doc.data()!);
  }

  Future<String> uploadPhoto(String uid, PlatformFile file) => CloudinaryService.instance.uploadPhoto(file);
  Future<String> uploadResume(String uid, PlatformFile file) => CloudinaryService.instance.uploadResume(file);
  Future<String> uploadIntroVideo(String uid, PlatformFile file) => CloudinaryService.instance.uploadIntroVideo(file);
}
