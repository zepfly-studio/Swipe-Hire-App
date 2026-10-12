import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/candidate_profile.dart';

/// Firestore-backed storage for a candidate account's own profile details
/// (`candidate_profiles/{uid}`), filled in once on [CompleteProfileScreen],
/// plus Firebase Storage uploads for the photo/resume/intro video a
/// candidate attaches to that profile -- the same fields recruiters see
/// (double-tap for resume, swipe for video) on the swipe-deck [Candidate]
/// card.
class CandidateProfileService {
  CandidateProfileService._internal();
  static final CandidateProfileService instance = CandidateProfileService._internal();

  final CollectionReference<Map<String, dynamic>> _profiles =
      FirebaseFirestore.instance.collection('candidate_profiles');
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<void> save(String uid, CandidateProfile profile) {
    return _profiles.doc(uid).set(profile.toMap());
  }

  Future<CandidateProfile?> fetch(String uid) async {
    final doc = await _profiles.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return CandidateProfile.fromMap(doc.data()!);
  }

  Future<String> uploadPhoto(String uid, PlatformFile file) => _upload(uid, file, 'photo');
  Future<String> uploadResume(String uid, PlatformFile file) => _upload(uid, file, 'resume');
  Future<String> uploadIntroVideo(String uid, PlatformFile file) => _upload(uid, file, 'intro_video');

  Future<String> _upload(String uid, PlatformFile file, String slot) async {
    final ext = file.extension ?? 'dat';
    final ref = _storage.ref('candidate_media/$uid/$slot.$ext');
    final bytes = await file.readAsBytes();
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }
}
