import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

/// Uploads a candidate's photo/resume/intro video to Cloudinary instead of
/// Firebase Storage, which Google now requires the Blaze (paid) plan for
/// on new projects -- Cloudinary's free tier needs no billing account.
///
/// Uses an *unsigned* upload preset (configured in the Cloudinary
/// dashboard, not here) so the upload can be made directly from the app
/// without embedding the account's API secret -- the preset itself is the
/// only thing that authorizes the request.
class CloudinaryService {
  CloudinaryService._();
  static final CloudinaryService instance = CloudinaryService._();

  // Public identifiers by design (they ship in every client). Override per
  // environment with --dart-define=CLOUDINARY_CLOUD_NAME=... and
  // --dart-define=CLOUDINARY_UPLOAD_PRESET=...
  static const String cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME', defaultValue: 'osmuzyat');
  static const String uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET', defaultValue: 'twp0ykep');

  /// Videos can be large, so allow a few minutes before giving up.
  static const Duration _uploadTimeout = Duration(minutes: 4);

  // Defense-in-depth limits enforced here regardless of what a caller
  // already checked (today only CompleteProfileScreen calls this, and it
  // checks size/extension before calling in -- but the unsigned Cloudinary
  // preset itself has no server-side enforcement, so anyone decompiling
  // the app and hitting this endpoint directly bypasses that UI check
  // entirely. These limits don't close that hole by themselves -- the
  // preset ALSO needs format/size restrictions set in the Cloudinary
  // dashboard, see docs/cloudinary-setup.md -- but keep any future call
  // site honest even if it forgets to validate first.
  static const int _maxPhotoBytes = 5 * 1024 * 1024;
  static const int _maxResumeBytes = 8 * 1024 * 1024;
  static const int _maxVideoBytes = 60 * 1024 * 1024;
  static const List<String> _imageExtensions = ['jpg', 'jpeg', 'png', 'webp'];
  static const List<String> _videoExtensions = ['mp4', 'mov', 'm4v'];
  static const List<String> _resumeExtensions = ['pdf'];

  /// What a candidate can attach to a task submission.
  static const int _maxTaskFileBytes = 10 * 1024 * 1024;
  static const List<String> taskFileExtensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'zip', 'doc', 'docx', 'txt'];

  Future<String> uploadPhoto(PlatformFile file) =>
      _upload(file, resourceType: 'image', maxBytes: _maxPhotoBytes, allowedExtensions: _imageExtensions);
  Future<String> uploadResume(PlatformFile file) =>
      _upload(file, resourceType: 'raw', maxBytes: _maxResumeBytes, allowedExtensions: _resumeExtensions);
  Future<String> uploadIntroVideo(PlatformFile file) =>
      _upload(file, resourceType: 'video', maxBytes: _maxVideoBytes, allowedExtensions: _videoExtensions);

  /// A file attached to a task submission. Pictures go up as images (so
  /// they preview), everything else as a raw file. The unsigned preset has
  /// to allow these formats in the Cloudinary dashboard.
  Future<String> uploadTaskFile(PlatformFile file) {
    final isImage = _imageExtensions.contains(file.extension?.toLowerCase());
    return _upload(
      file,
      resourceType: isImage ? 'image' : 'raw',
      maxBytes: _maxTaskFileBytes,
      allowedExtensions: taskFileExtensions,
    );
  }

  Future<String> _upload(
    PlatformFile file, {
    required String resourceType,
    required int maxBytes,
    required List<String> allowedExtensions,
  }) async {
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > maxBytes) {
      throw StateError('${file.name} is too large (max ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB).');
    }
    final ext = file.extension?.toLowerCase();
    if (ext == null || !allowedExtensions.contains(ext)) {
      throw StateError('${file.name} has an unsupported file type.');
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)..fields['upload_preset'] = uploadPreset;

    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));

    final http.Response response;
    try {
      final streamedResponse = await request.send().timeout(_uploadTimeout);
      response = await http.Response.fromStream(streamedResponse).timeout(_uploadTimeout);
    } on TimeoutException {
      throw StateError('The upload took too long. Check your connection and try again.');
    }
    if (response.statusCode != 200) {
      throw StateError('The upload was rejected (${response.statusCode}). Please try a different file.');
    }

    final body = jsonDecode(response.body);
    final url = body is Map<String, dynamic> ? body['secure_url'] : null;
    if (url is! String || url.isEmpty) {
      throw StateError('The upload finished but no file link came back. Please try again.');
    }
    return url;
  }
}
