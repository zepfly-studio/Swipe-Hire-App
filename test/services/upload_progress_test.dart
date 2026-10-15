import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/services/upload_progress.dart';
import 'package:http/http.dart' as http;

void main() {
  test('keeps the multipart content-type (with its boundary) on the wrapped request', () async {
    final request = http.MultipartRequest('POST', Uri.parse('https://example.test/upload'))
      ..fields['upload_preset'] = 'preset'
      ..files.add(http.MultipartFile.fromBytes('file', utf8.encode('%PDF-1.1 hello'), filename: 'cv.pdf'));

    final wrapped = withUploadProgress(request, (_) {});

    final contentType = wrapped.headers['content-type'] ?? '';
    expect(contentType, startsWith('multipart/form-data; boundary='));
    expect(wrapped.contentLength, request.contentLength);
  });

  test('reports progress up to 1.0 and forwards the whole body', () async {
    final request = http.MultipartRequest('POST', Uri.parse('https://example.test/upload'))
      ..files.add(http.MultipartFile.fromBytes('file', List<int>.filled(5000, 65), filename: 'cv.pdf'));
    final reported = <double>[];

    final wrapped = withUploadProgress(request, reported.add) as http.StreamedRequest;
    final bytes = await wrapped.finalize().toBytes();

    expect(bytes.length, request.contentLength);
    expect(reported, isNotEmpty);
    expect(reported.last, 1.0);
  });

  test('returns the request untouched when nobody listens for progress', () {
    final request = http.MultipartRequest('POST', Uri.parse('https://example.test/upload'));
    expect(identical(withUploadProgress(request, null), request), isTrue);
  });
}
