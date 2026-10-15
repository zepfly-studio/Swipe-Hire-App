
import 'package:http/http.dart' as http;

/// Wraps a ready-to-send request so [onProgress] (0..1) fires as its body
/// goes out. `package:http` has no upload progress of its own, so the
/// finalized body stream is replayed into a [http.StreamedRequest] while
/// counting bytes. With no [onProgress] the request is returned unchanged.
http.BaseRequest withUploadProgress(
  http.BaseRequest request,
  void Function(double progress)? onProgress,
) {
  if (onProgress == null) return request;
  final total = request.contentLength ?? 0;
  final streamed = http.StreamedRequest(request.method, request.url)
    ..headers.addAll(request.headers)
    ..contentLength = request.contentLength
    ..followRedirects = request.followRedirects
    ..maxRedirects = request.maxRedirects
    ..persistentConnection = request.persistentConnection;

  var sent = 0;
  var lastReported = -1;
  request.finalize().listen(
    (chunk) {
      streamed.sink.add(chunk);
      sent += chunk.length;
      if (total > 0) {
        final pct = (sent * 100 ~/ total).clamp(0, 100);
        if (pct != lastReported) {
          lastReported = pct;
          onProgress(pct / 100);
        }
      }
    },
    onError: streamed.sink.addError,
    onDone: streamed.sink.close,
    cancelOnError: true,
  );
  return streamed;
}
