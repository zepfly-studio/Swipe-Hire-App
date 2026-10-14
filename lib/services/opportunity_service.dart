import 'package:flutter/foundation.dart' show visibleForTesting;
import '../models/app_user.dart';
import '../models/opportunity.dart';
import 'api_client.dart';
import 'polling.dart';

/// A task the recruiter saved to reuse.
class TaskTemplate {
  final String id;
  final String title;
  final String description;
  final String link;
  const TaskTemplate({required this.id, required this.title, this.description = '', this.link = ''});

  factory TaskTemplate.fromMap(Map<String, dynamic> map) => TaskTemplate(
        id: map['id'] ?? '',
        title: map['title'] ?? '',
        description: map['description'] ?? '',
        link: map['link'] ?? '',
      );
}

/// Backend access for the recruiter <-> candidate hiring pipeline
/// (`opportunities` table, `/opportunities` routes): looking up a real
/// candidate account by email, and creating/streaming the [Opportunity]
/// rows that track status/interview/offer between a recruiter and that
/// candidate -- plus the assessment tasks and the candidate's answers
/// (withdraw, accept or decline an offer, confirm an interview).
class OpportunityService {
  OpportunityService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final OpportunityService instance = OpportunityService._internal();

  /// A service wired to an injected (fake) API -- tests only.
  @visibleForTesting
  factory OpportunityService.test(ApiClient api) => OpportunityService._internal(api: api);

  final ApiClient _api;

  Opportunity _parse(Map<String, dynamic> map) => Opportunity.fromMap(map['id'] as String, map);

  Opportunity _parseKey(Map<String, dynamic> res, String key) =>
      _parse(Map<String, dynamic>.from(res[key] as Map));

  /// Looks up a candidate account by exact email match, for a recruiter to
  /// start a pipeline entry with. Returns null if no candidate account
  /// uses that email.
  Future<AppUser?> findCandidateByEmail(String email) async {
    try {
      final res = await _api.get('/users/candidates/lookup', query: {'email': email.trim()});
      return AppUser.fromMap(res['uid'] as String, res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// The existing opportunity between this recruiter and this candidate,
  /// if any -- checked before creating a new one (e.g. from
  /// [ShortlistScreen]'s "Send to Pipeline" action) so a candidate who
  /// already has a pipeline entry (say, from applying to a job posting)
  /// gets that one moved to the new status instead of ending up with two
  /// separate entries for the same recruiter.
  Future<Opportunity?> findExistingBetween(String recruiterUid, String candidateUid) async {
    final res = await _api.get('/opportunities/with/$candidateUid');
    final row = res['opportunity'];
    if (row == null) return null;
    return _parse(Map<String, dynamic>.from(row as Map));
  }

  Future<String> save(Opportunity opportunity) async {
    final res = opportunity.id.isEmpty
        ? await _api.post('/opportunities', body: opportunity.toMap())
        : await _api.put('/opportunities/${opportunity.id}', body: opportunity.toMap());
    DataRefresh.instance.bump();
    return res['id'] as String;
  }

  // -- Assessment tasks ---------------------------------------------------

  /// Recruiter assigns a task; the entry moves to "Task assigned" and the
  /// candidate gets a chat message, a push and an email. With
  /// [saveAsTemplate] it is also kept for reuse.
  Future<Opportunity> assignTask(
    String opportunityId, {
    required String title,
    String description = '',
    String link = '',
    DateTime? dueDate,
    bool saveAsTemplate = false,
  }) async {
    final res = await _api.post('/opportunities/$opportunityId/tasks', body: {
      'title': title,
      'description': description,
      'link': link,
      'dueDate': dueDate?.toUtc().toIso8601String(),
      'saveAsTemplate': saveAsTemplate,
    });
    DataRefresh.instance.bump();
    return _parseKey(res, 'opportunity');
  }

  /// Candidate hands the task in (can be re-sent until it is reviewed).
  /// [fileUrl] is a Cloudinary link from [CloudinaryService.uploadTaskFile].
  Future<Opportunity> submitTask(
    String opportunityId,
    String taskId, {
    String answer = '',
    String link = '',
    String fileUrl = '',
    String fileName = '',
  }) async {
    final res = await _api.post(
      '/opportunities/$opportunityId/tasks/$taskId/submit',
      body: {'answer': answer, 'link': link, 'fileUrl': fileUrl, 'fileName': fileName},
    );
    DataRefresh.instance.bump();
    return _parseKey(res, 'opportunity');
  }

  /// [decision] is `approved`, `changes` or `rejected`.
  Future<Opportunity> reviewTask(String opportunityId, String taskId, {required String decision, String feedback = ''}) async {
    final res = await _api.post(
      '/opportunities/$opportunityId/tasks/$taskId/review',
      body: {'decision': decision, 'feedback': feedback},
    );
    DataRefresh.instance.bump();
    return _parseKey(res, 'opportunity');
  }

  // -- The candidate's answers --------------------------------------------

  Future<Opportunity> withdraw(String opportunityId, {String reason = ''}) async {
    final res = await _api.post('/opportunities/$opportunityId/withdraw', body: {'reason': reason});
    DataRefresh.instance.bump();
    return _parse(res);
  }

  /// `accepted` keeps the offer open for the recruiter to mark as hired;
  /// `declined` withdraws the application.
  Future<Opportunity> respondToOffer(String opportunityId, {required bool accept}) async {
    final res = await _api.post(
      '/opportunities/$opportunityId/offer-response',
      body: {'decision': accept ? 'accepted' : 'declined'},
    );
    DataRefresh.instance.bump();
    return _parse(res);
  }

  /// Confirms the interview, or asks the recruiter for another time (a
  /// preferred time in [note] is required for that).
  Future<Opportunity> respondToInterview(String opportunityId, {required bool confirm, String note = ''}) async {
    final res = await _api.post(
      '/opportunities/$opportunityId/interview-response',
      body: {'decision': confirm ? 'confirm' : 'reschedule', 'note': note},
    );
    DataRefresh.instance.bump();
    return _parse(res);
  }

  // -- Task templates -----------------------------------------------------

  Future<List<TaskTemplate>> fetchTemplates() async {
    final res = await _api.get('/templates');
    return (res['templates'] as List? ?? const [])
        .map((e) => TaskTemplate.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<void> deleteTemplate(String id) async {
    await _api.delete('/templates/$id');
  }

  // -- Lists --------------------------------------------------------------

  Future<List<Opportunity>> fetchMine() async {
    final res = await _api.get('/opportunities');
    return (res['opportunities'] as List? ?? const [])
        .map((e) => _parse(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Every opportunity for the signed-in candidate, newest update first --
  /// what their dashboard's "Hiring Activity" section shows.
  Stream<List<Opportunity>> streamForCandidate(String candidateUid) => pollingStream(fetchMine);

  /// Every opportunity the signed-in recruiter has created -- their
  /// "Pipeline" tab.
  Stream<List<Opportunity>> streamForRecruiter(String recruiterUid) => pollingStream(fetchMine);
}
