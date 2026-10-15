import 'package:flutter/foundation.dart';
import '../models/pair/hiring_task.dart';
import '../models/pair/pair_person.dart';
import 'api_client.dart';
import 'polling.dart';

/// Take-home tasks (backend `/tasks`, both roles).
class HiringTaskService {
  HiringTaskService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final HiringTaskService instance = HiringTaskService._internal();

  @visibleForTesting
  factory HiringTaskService.test(ApiClient api) => HiringTaskService._internal(api: api);

  final ApiClient _api;

  static String _enc(String id) => Uri.encodeComponent(id);

  /// A company may filter by [candidateId].
  Future<List<HiringTask>> list({String? candidateId}) async {
    final res = await _api.get('/tasks', query: {
      if (candidateId != null && candidateId.isNotEmpty) 'candidateId': candidateId,
    });
    return [
      for (final e in (res['tasks'] as List? ?? const []))
        if (e is Map) HiringTask.fromMap(Map<String, dynamic>.from(e)),
    ];
  }

  Future<String> create({
    required String candidateId,
    String? jobId,
    required String title,
    required String description,
    String briefUrl = '',
    required DateTime dueAt,
  }) async {
    final res = await _api.post('/tasks', body: {
      'candidateId': candidateId,
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
      'title': title.trim(),
      'description': description.trim(),
      if (briefUrl.trim().isNotEmpty) 'briefUrl': briefUrl.trim(),
      'dueAt': dueAt.toUtc().toIso8601String(),
    });
    DataRefresh.instance.bump();
    return pairStr(res['id']);
  }

  Future<void> submit(String id, {String liveUrl = '', String repoUrl = '', String note = ''}) async {
    await _api.post('/tasks/${_enc(id)}/submit', body: {
      if (liveUrl.isNotEmpty) 'liveUrl': liveUrl,
      if (repoUrl.isNotEmpty) 'repoUrl': repoUrl,
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
    DataRefresh.instance.bump();
  }

  Future<void> changeDeadline(String id, DateTime dueAt) async {
    await _api.patch('/tasks/${_enc(id)}', body: {'dueAt': dueAt.toUtc().toIso8601String()});
    DataRefresh.instance.bump();
  }

  Future<void> cancel(String id) async {
    await _api.post('/tasks/${_enc(id)}/cancel');
    DataRefresh.instance.bump();
  }
}
