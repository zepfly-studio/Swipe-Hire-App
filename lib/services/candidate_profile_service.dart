import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/candidate_profile.dart';
import '../models/candidate_stats.dart';
import 'api_client.dart';
import 'cloudinary_service.dart';
import 'polling.dart';

/// What `POST /candidates/me/resume/autofill` found in the PDF -- only the
/// keys it could read: phone, skills[], degree, qualification, graduationYear,
/// college, desiredRole, location, experienceYears, currentCompany,
/// currentPost.
class ResumeAutofill {
  final Map<String, dynamic> fields;
  const ResumeAutofill(this.fields);

  factory ResumeAutofill.fromResponse(Map<String, dynamic> res) {
    final f = res['fields'];
    return ResumeAutofill(f is Map ? Map<String, dynamic>.from(f) : const {});
  }
}

/// Backend storage for a candidate account's own profile details
/// (`GET/PUT /candidates/me/profile`), the preferences / "I'm active" /
/// stats endpoints behind the candidate home, and the photo/resume/intro
/// video uploads (those go to Cloudinary, see [CloudinaryService]; the
/// backend only stores the URLs).
class CandidateProfileService {
  CandidateProfileService._internal({ApiClient? api})
    : _api = api ?? ApiClient.instance;
  static final CandidateProfileService instance =
      CandidateProfileService._internal();

  /// A service wired to an injected (fake) API -- tests only.
  @visibleForTesting
  factory CandidateProfileService.test(ApiClient api) =>
      CandidateProfileService._internal(api: api);

  final ApiClient _api;

  /// [uid] is kept for call-site compatibility; the backend always writes
  /// the signed-in candidate's own profile. Returns the profile as saved.
  Future<CandidateProfile> save(String uid, CandidateProfile profile) async {
    final res = await _api.put('/candidates/me/profile', body: profile.toMap());
    DataRefresh.instance.bump();
    return res.isEmpty ? profile : CandidateProfile.fromMap(res);
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

  /// Reads the PDF on the server and returns what it could fill in.
  Future<ResumeAutofill> autofillFromResume(
    String path, {
    String? filename,
    void Function(double progress)? onProgress,
  }) async {
    final res = await _api.postMultipart(
      '/candidates/me/resume/autofill',
      fileField: 'resume',
      filePath: path,
      filename: filename,
      onProgress: onProgress,
    );
    return ResumeAutofill.fromResponse(res);
  }

  /// Confirms the candidate is still looking (`POST /candidates/me/active`).
  Future<CandidateProfile> markActive() async {
    final res = await _api.post('/candidates/me/active');
    DataRefresh.instance.bump();
    return CandidateProfile.fromMap(res);
  }

  /// `PUT /candidates/me/preferences`.
  Future<CandidateProfile> savePreferences({
    required bool openToWork,
    required List<String> workModes,
    required List<String> jobTypes,
    required List<String> preferredLocations,
  }) async {
    final res = await _api.put(
      '/candidates/me/preferences',
      body: {
        'openToWork': openToWork,
        'workModes': workModes,
        'jobTypes': jobTypes,
        'preferredLocations': preferredLocations,
      },
    );
    DataRefresh.instance.bump();
    return CandidateProfile.fromMap(res);
  }

  Future<CandidateStats> fetchStats() async {
    final res = await _api.get('/candidates/me/stats');
    return CandidateStats.fromMap(res);
  }

  Future<String> uploadPhoto(String uid, PlatformFile file) =>
      CloudinaryService.instance.uploadPhoto(file);
  Future<String> uploadResume(String uid, PlatformFile file) =>
      CloudinaryService.instance.uploadResume(file);
  Future<String> uploadIntroVideo(String uid, PlatformFile file) =>
      CloudinaryService.instance.uploadIntroVideo(file);
}
