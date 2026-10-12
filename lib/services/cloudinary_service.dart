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

  // TODO: fill in from the Cloudinary dashboard (Settings > Upload for the
  // preset; the cloud name is shown at the top of the dashboard itself).
  static const String cloudName = 'osmuzyat';
  static const String uploadPreset = 'twp0ykep';

  Future<String> uploadPhoto(PlatformFile file) => _upload(file, resourceType: 'image');
  Future<String> uploadResume(PlatformFile file) => _upload(file, resourceType: 'raw');
  Future<String> uploadIntroVideo(PlatformFile file) => _upload(file, resourceType: 'video');

  Future<String> _upload(PlatformFile file, {required String resourceType}) async {
    if (cloudName == 'YOUR_CLOUD_NAME' || uploadPreset == 'YOUR_UPLOAD_PRESET') {
      throw StateError(
        'Cloudinary is not configured yet -- set cloudName/uploadPreset in lib/services/cloudinary_service.dart.',
      );
    }

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/$resourceType/upload');
    final request = http.MultipartRequest('POST', uri)..fields['upload_preset'] = uploadPreset;

    final bytes = await file.readAsBytes();
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode != 200) {
      throw StateError('Cloudinary upload failed (${response.statusCode}): ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return body['secure_url'] as String;
  }
}
