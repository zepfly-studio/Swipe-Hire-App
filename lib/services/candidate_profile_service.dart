import 'package:file_picker/file_picker.dart';
import '../models/candidate_profile.dart';
import 'api_client.dart';
import 'cloudinary_service.dart';
import 'polling.dart';

/// Backend storage for a candidate account's own profile details
/// (`candidate_profiles` table, `GET/PUT /candidates/me/profile`), filled in
/// once on [CompleteProfileScreen], plus the photo/resume/intro video a
/// candidate attaches to that profile -- the same fields recruiters see
/// (double-tap for resume, swipe for video) on the swipe-deck [Candidate]
/// card. Those uploads go to Cloudinary (see [CloudinaryService]).
class CandidateProfileService {
  CandidateProfileService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final CandidateProfileService instance = CandidateProfileService._internal();

  final ApiClient _api;

  /// [uid] is kept for call-site compatibility; the backend always writes
  /// the signed-in candidate's own profile.
  Future<void> save(String uid, CandidateProfile profile) async {
    await _api.put('/candidates/me/profile', body: profile.toMap());
    DataRefresh.instance.bump();
  }

  Future<CandidateProfile?> fetch(String uid) async {
    try {
      final res = await _api.get('/candidates/me/profile');
      return CandidateProfile.fromMap(res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<String> uploadPhoto(String uid, PlatformFile file) => CloudinaryService.instance.uploadPhoto(file);
  Future<String> uploadResume(String uid, PlatformFile file) => CloudinaryService.instance.uploadResume(file);
  Future<String> uploadIntroVideo(String uid, PlatformFile file) => CloudinaryService.instance.uploadIntroVideo(file);
}
