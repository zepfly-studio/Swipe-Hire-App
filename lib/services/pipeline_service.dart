import 'package:flutter/foundation.dart';
import '../models/candidate.dart';
import '../models/pair/pair_person.dart';
import '../models/pair/pipeline_models.dart';
import 'api_client.dart';
import 'hiring_service.dart';
import 'polling.dart';

/// The company's shortlisted pipeline (`/company/shortlisted`,
/// `/company/pipeline/:swipeId`) and its job filter (`/jobs/mine`).
class PipelineService {
  PipelineService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final PipelineService instance = PipelineService._internal();

  @visibleForTesting
  factory PipelineService.test(ApiClient api) => PipelineService._internal(api: api);

  final ApiClient _api;

  /// One row per right swipe (candidate + job), newest first.
  Future<List<Candidate>> shortlisted({String? jobId}) async {
    final res = await _api.get('/company/shortlisted', query: {
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
    });
    final out = <Candidate>[];
    for (final e in (res['candidates'] as List? ?? const [])) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final id = pairStr(m['id'], pairStr(m['candidateId']));
      if (id.isEmpty) continue;
      out.add(Candidate.fromMap(id, m));
    }
    return out;
  }

  Future<List<PipelineJob>> myJobs() async {
    final res = await _api.get('/jobs/mine');
    return [
      for (final e in (res['jobs'] as List? ?? const []))
        if (e is Map) PipelineJob.fromMap(Map<String, dynamic>.from(e)),
    ];
  }

  Future<void> setStage(String swipeId, String stage) async {
    await _api.patch('/company/pipeline/${Uri.encodeComponent(swipeId)}', body: {'stage': stage});
    DataRefresh.instance.bump();
  }

  /// Takes the candidate out of the shortlist. The swipe is deleted on the
  /// server, so they are unswiped for that job and return to the swipe deck
  /// (the swipe that shortlisted them is not refunded).
  Future<void> removeFromShortlist(String swipeId) async {
    await _api.delete('/company/shortlisted/${Uri.encodeComponent(swipeId)}');
    DataRefresh.instance.bump();
    HiringService.deckRefresh.value++;
  }

  Future<void> setNotes(String swipeId, String notes) async {
    await _api.patch('/company/pipeline/${Uri.encodeComponent(swipeId)}', body: {'notes': notes});
  }
}
