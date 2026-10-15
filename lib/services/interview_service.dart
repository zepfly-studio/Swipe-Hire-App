import 'package:flutter/foundation.dart';
import '../models/pair/interview.dart';
import '../models/pair/pair_person.dart';
import 'api_client.dart';
import 'polling.dart';

/// Interview invites (backend `/interviews`, both roles).
class InterviewService {
  InterviewService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final InterviewService instance = InterviewService._internal();

  @visibleForTesting
  factory InterviewService.test(ApiClient api) => InterviewService._internal(api: api);

  final ApiClient _api;

  Future<List<Interview>> list() async {
    final res = await _api.get('/interviews');
    return [
      for (final e in (res['interviews'] as List? ?? const []))
        if (e is Map) Interview.fromMap(Map<String, dynamic>.from(e)),
    ];
  }

  /// Company: invite a candidate. [slots] are ISO-8601 UTC strings.
  Future<String> create({
    required String candidateId,
    String? jobId,
    required List<String> slots,
    required int durationMins,
    required String mode,
    String location = '',
    String meetingLink = '',
    String note = '',
  }) async {
    final res = await _api.post('/interviews', body: {
      'candidateId': candidateId,
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
      'slots': slots,
      'durationMins': durationMins,
      'mode': mode,
      if (mode == 'in-person') 'location': location.trim(),
      if (mode == 'video' && meetingLink.trim().isNotEmpty) 'meetingLink': meetingLink.trim(),
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    DataRefresh.instance.bump();
    return pairStr(res['id']);
  }

  /// Candidate: pick one of the offered slots.
  Future<void> accept(String id, DateTime slot) async {
    await _api.post('/interviews/${Uri.encodeComponent(id)}/accept', body: {'slot': slot.toUtc().toIso8601String()});
    DataRefresh.instance.bump();
  }

  /// Either side; idempotent.
  Future<void> cancel(String id, {String reason = ''}) async {
    await _api.post('/interviews/${Uri.encodeComponent(id)}/cancel', body: {
      if (reason.trim().isNotEmpty) 'reason': reason.trim(),
    });
    DataRefresh.instance.bump();
  }
}
