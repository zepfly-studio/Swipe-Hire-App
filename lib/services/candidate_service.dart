import 'package:flutter/foundation.dart';
import '../models/candidate.dart';
import 'api_client.dart';

/// One page of [fetchCandidatesPage] -- the candidates themselves, plus
/// the cursor ([nextCursor]) to pass back in for the next page and whether
/// there's likely more behind it.
class CandidatePage {
  final List<Candidate> candidates;
  final String? nextCursor;
  final bool hasMore;

  const CandidatePage({required this.candidates, required this.nextCursor, required this.hasMore});
}

/// What a recruiter narrows the swipe deck down with. Applied by the
/// backend, so it covers every candidate, not just the ones loaded.
@immutable
class CandidateFilters {
  final String query;
  final List<String> skills;
  final String location;
  final double? expMin;
  final double? expMax;
  final double? ctcMin;
  final double? ctcMax;

  /// Longest acceptable notice period, in days.
  final int? noticeMaxDays;

  /// Score against this posting only (default: the best of all open ones).
  final String jobId;

  /// Best match first instead of the default order.
  final bool sortByMatch;

  const CandidateFilters({
    this.query = '',
    this.skills = const [],
    this.location = '',
    this.expMin,
    this.expMax,
    this.ctcMin,
    this.ctcMax,
    this.noticeMaxDays,
    this.jobId = '',
    this.sortByMatch = false,
  });

  bool get isEmpty => this == const CandidateFilters();

  /// How many individual filters are on (search text, posting and sort
  /// order don't count) -- for the badge on the filter button.
  int get activeCount =>
      (skills.isNotEmpty ? 1 : 0) +
      (location.isNotEmpty ? 1 : 0) +
      (expMin != null || expMax != null ? 1 : 0) +
      (ctcMin != null || ctcMax != null ? 1 : 0) +
      (noticeMaxDays != null ? 1 : 0);

  Map<String, String> toQuery() => {
        if (query.trim().isNotEmpty) 'q': query.trim(),
        if (skills.isNotEmpty) 'skills': skills.join(','),
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (expMin != null) 'expMin': '$expMin',
        if (expMax != null) 'expMax': '$expMax',
        if (ctcMin != null) 'ctcMin': '$ctcMin',
        if (ctcMax != null) 'ctcMax': '$ctcMax',
        if (noticeMaxDays != null) 'noticeMax': '$noticeMaxDays',
        if (jobId.isNotEmpty) 'jobId': jobId,
        if (sortByMatch) 'sort': 'match',
      };

  CandidateFilters copyWith({
    String? query,
    List<String>? skills,
    String? location,
    double? expMin,
    double? expMax,
    double? ctcMin,
    double? ctcMax,
    int? noticeMaxDays,
    String? jobId,
    bool? sortByMatch,
    bool clearExperience = false,
    bool clearCtc = false,
    bool clearNotice = false,
  }) {
    return CandidateFilters(
      query: query ?? this.query,
      skills: skills ?? this.skills,
      location: location ?? this.location,
      expMin: clearExperience ? null : (expMin ?? this.expMin),
      expMax: clearExperience ? null : (expMax ?? this.expMax),
      ctcMin: clearCtc ? null : (ctcMin ?? this.ctcMin),
      ctcMax: clearCtc ? null : (ctcMax ?? this.ctcMax),
      noticeMaxDays: clearNotice ? null : (noticeMaxDays ?? this.noticeMaxDays),
      jobId: jobId ?? this.jobId,
      sortByMatch: sortByMatch ?? this.sortByMatch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CandidateFilters &&
      other.query == query &&
      listEquals(other.skills, skills) &&
      other.location == location &&
      other.expMin == expMin &&
      other.expMax == expMax &&
      other.ctcMin == ctcMin &&
      other.ctcMax == ctcMax &&
      other.noticeMaxDays == noticeMaxDays &&
      other.jobId == jobId &&
      other.sortByMatch == sortByMatch;

  @override
  int get hashCode =>
      Object.hash(query, Object.hashAll(skills), location, expMin, expMax, ctcMin, ctcMax, noticeMaxDays, jobId, sortByMatch);
}

/// Reads real candidate accounts for the recruiter's swipe deck from the
/// backend (`GET /candidates`), which joins each user with their candidate
/// profile and already excludes anyone this recruiter has swiped on -- so
/// the deck is the same on every device the recruiter signs into.
///
/// Paginated rather than one big fetch, so the swipe deck stays fast even
/// with thousands of candidates -- [HomeSwipeScreen] fetches the next page
/// only once it's running low on un-swiped cards. A candidate only appears
/// once they've finished CompleteProfileScreen.
class CandidateService {
  CandidateService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final CandidateService instance = CandidateService._internal();

  static const int defaultPageSize = 20;

  final ApiClient _api;

  Future<CandidatePage> fetchCandidatesPage({
    String? startAfter,
    int pageSize = defaultPageSize,
    CandidateFilters filters = const CandidateFilters(),
  }) async {
    final res = await _api.get('/candidates', query: {
      'limit': '$pageSize',
      if (startAfter != null && startAfter.isNotEmpty) 'cursor': startAfter,
      ...filters.toQuery(),
    });
    final items = (res['candidates'] as List? ?? const [])
        .map((e) => Candidate.fromMap(e['id'] as String, Map<String, dynamic>.from(e as Map)))
        .toList();
    return CandidatePage(
      candidates: items,
      nextCursor: res['nextCursor'] as String?,
      hasMore: res['hasMore'] == true,
    );
  }
}
