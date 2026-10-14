import 'package:flutter/foundation.dart';
import '../models/candidate.dart';
import '../models/job_posting.dart';
import '../models/opportunity.dart';
import 'api_client.dart';
import 'polling.dart';

/// What a candidate narrows the job list down with. Everything is applied
/// by the backend, so it works over the whole list, not just what's loaded.
@immutable
class JobFilters {
  final String query;
  final String location;
  final String employmentType;
  final double? salaryMin;
  final List<String> skills;
  final bool remoteOnly;

  /// The candidate's own years of experience; hides roles that ask for more.
  final double? myExperienceYears;
  final bool sortByMatch;

  const JobFilters({
    this.query = '',
    this.location = '',
    this.employmentType = '',
    this.salaryMin,
    this.skills = const [],
    this.remoteOnly = false,
    this.myExperienceYears,
    this.sortByMatch = false,
  });

  bool get isEmpty => this == const JobFilters();

  /// How many individual filters are on, for the badge on the filter button
  /// (the search text and the sort order don't count).
  int get activeCount =>
      (location.isNotEmpty ? 1 : 0) +
      (employmentType.isNotEmpty ? 1 : 0) +
      (salaryMin != null ? 1 : 0) +
      (skills.isNotEmpty ? 1 : 0) +
      (remoteOnly ? 1 : 0) +
      (myExperienceYears != null ? 1 : 0);

  JobFilters copyWith({
    String? query,
    String? location,
    String? employmentType,
    double? salaryMin,
    bool clearSalaryMin = false,
    List<String>? skills,
    bool? remoteOnly,
    double? myExperienceYears,
    bool clearExperience = false,
    bool? sortByMatch,
  }) {
    return JobFilters(
      query: query ?? this.query,
      location: location ?? this.location,
      employmentType: employmentType ?? this.employmentType,
      salaryMin: clearSalaryMin ? null : (salaryMin ?? this.salaryMin),
      skills: skills ?? this.skills,
      remoteOnly: remoteOnly ?? this.remoteOnly,
      myExperienceYears: clearExperience ? null : (myExperienceYears ?? this.myExperienceYears),
      sortByMatch: sortByMatch ?? this.sortByMatch,
    );
  }

  Map<String, String> toQuery() => {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (employmentType.isNotEmpty) 'type': employmentType,
        if (salaryMin != null) 'salaryMin': '$salaryMin',
        if (skills.isNotEmpty) 'skills': skills.join(','),
        if (remoteOnly) 'remote': '1',
        if (myExperienceYears != null) 'experience': '$myExperienceYears',
        if (sortByMatch) 'sort': 'match',
      };

  @override
  bool operator ==(Object other) =>
      other is JobFilters &&
      other.query == query &&
      other.location == location &&
      other.employmentType == employmentType &&
      other.salaryMin == salaryMin &&
      listEquals(other.skills, skills) &&
      other.remoteOnly == remoteOnly &&
      other.myExperienceYears == myExperienceYears &&
      other.sortByMatch == sortByMatch;

  @override
  int get hashCode => Object.hash(query, location, employmentType, salaryMin, Object.hashAll(skills), remoteOnly, myExperienceYears, sortByMatch);
}

/// One person who applied to a posting, with their pipeline entry.
class Applicant {
  final Opportunity opportunity;
  final Candidate? candidate;
  const Applicant({required this.opportunity, required this.candidate});
}

/// Backend access for job postings (`job_postings` table, `/jobs` routes):
/// a recruiter creating/closing their own, candidates browsing the open
/// ones, applying to one (which creates an [Opportunity] the recruiter then
/// manages on their Pipeline tab), and saving/un-saving postings for later.
class JobPostingService {
  JobPostingService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final JobPostingService instance = JobPostingService._internal();

  /// Builds an instance wired to an injected (fake) API -- used only by
  /// tests, never by app code, which should always go through [instance].
  @visibleForTesting
  factory JobPostingService.test(ApiClient api) => JobPostingService._internal(api: api);

  final ApiClient _api;

  List<JobPosting> _parseList(Map<String, dynamic> res) {
    return (res['jobs'] as List? ?? const [])
        .map((e) => JobPosting.fromMap(e['id'] as String, Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<String> create(JobPosting posting) async {
    final res = await _api.post('/jobs', body: posting.toMap());
    DataRefresh.instance.bump();
    return res['id'] as String;
  }

  /// Full edit of an already-published posting -- keeps its id and
  /// original `createdAt`.
  Future<void> update(JobPosting posting) async {
    await _api.put('/jobs/${posting.id}', body: posting.toMap());
    DataRefresh.instance.bump();
  }

  Future<void> setOpen(String postingId, bool isOpen) async {
    await _api.patch('/jobs/$postingId', body: {'isOpen': isOpen});
    DataRefresh.instance.bump();
  }

  /// The recruiter's own postings, each with its applicant count.
  Future<List<JobPosting>> fetchMyPostings() async => _parseList(await _api.get('/jobs/mine'));

  /// [recruiterUid] is kept for call-site compatibility; the backend scopes
  /// to the signed-in recruiter.
  Stream<List<JobPosting>> streamMyPostings(String recruiterUid) => pollingStream(fetchMyPostings);

  /// Everyone who applied to [jobId], best match first.
  Future<List<Applicant>> fetchApplicants(String jobId) async {
    final res = await _api.get('/jobs/$jobId/applicants');
    return (res['applicants'] as List? ?? const []).map((raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      final opportunityMap = Map<String, dynamic>.from(map['opportunity'] as Map);
      final candidateMap = map['candidate'] is Map ? Map<String, dynamic>.from(map['candidate'] as Map) : null;
      return Applicant(
        opportunity: Opportunity.fromMap(opportunityMap['id'] as String, opportunityMap),
        candidate: candidateMap == null ? null : Candidate.fromMap(candidateMap['id'] as String, candidateMap),
      );
    }).toList();
  }

  /// Open postings, newest first (or best match first), narrowed by
  /// [filters] on the server. For a candidate each carries a match score.
  Future<List<JobPosting>> fetchOpenPostings({int limit = 100, JobFilters filters = const JobFilters()}) async {
    return _parseList(await _api.get('/jobs', query: {'limit': '$limit', ...filters.toQuery()}));
  }

  Stream<List<JobPosting>> streamOpenPostings({int limit = 100, JobFilters filters = const JobFilters()}) =>
      pollingStream(() => fetchOpenPostings(limit: limit, filters: filters), interval: const Duration(seconds: 15));

  /// The roles that fit the signed-in candidate best.
  Future<List<JobPosting>> fetchRecommended() async => _parseList(await _api.get('/jobs/recommended'));

  /// Whether this candidate already has an application tied to this
  /// posting -- guards the Apply button against duplicate applications.
  Future<bool> hasApplied(String candidateUid, String jobPostingId) async {
    final res = await _api.get('/jobs/$jobPostingId/application');
    return res['applied'] == true;
  }

  Future<void> apply({
    required JobPosting posting,
    required String candidateUid,
    required String candidateName,
  }) async {
    await _api.post('/jobs/${posting.id}/apply');
    DataRefresh.instance.bump();
  }

  // -- Saved jobs: saved_jobs table ---------------------------------------

  Future<void> saveJob(String candidateUid, String jobPostingId) async {
    await _api.put('/jobs/saved/$jobPostingId');
    DataRefresh.instance.bump();
  }

  Future<void> unsaveJob(String candidateUid, String jobPostingId) async {
    await _api.delete('/jobs/saved/$jobPostingId');
    DataRefresh.instance.bump();
  }

  Future<Set<String>> fetchSavedJobIds() async {
    final res = await _api.get('/jobs/saved');
    return (res['ids'] as List? ?? const []).map((e) => e.toString()).toSet();
  }

  Stream<Set<String>> streamSavedJobIds(String candidateUid) => pollingStream(fetchSavedJobIds);

  /// The bookmarked postings themselves, newest save first, in one request.
  Future<List<JobPosting>> fetchSavedPostings() async => _parseList(await _api.get('/jobs/saved'));

  Stream<List<JobPosting>> streamSavedPostings() => pollingStream(fetchSavedPostings);

  Future<JobPosting?> fetchById(String jobPostingId) async {
    try {
      final res = await _api.get('/jobs/$jobPostingId');
      return JobPosting.fromMap(res['id'] as String, res);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }
}
