import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/candidate.dart';
import '../models/hiring_company.dart';
import '../models/hiring_job.dart';
import '../models/swipe_filters.dart';
import '../models/swipe_models.dart';
import 'api_client.dart';
import 'polling.dart';

/// Where the company side keeps small per-device choices (last job per
/// company, remembered filters per user).
abstract class HiringPrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

/// In-memory store -- tests, and the fallback when Hive is unavailable.
class MemoryHiringPrefs implements HiringPrefsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// Hive-backed store (`hiring_prefs` box). Errors are swallowed: a choice
/// that cannot be remembered must never break a screen.
class HiveHiringPrefs implements HiringPrefsStore {
  static const _boxName = 'hiring_prefs';
  Box? _box;

  Future<Box?> _open() async {
    if (_box != null) return _box;
    try {
      _box = await Hive.openBox(_boxName);
    } catch (_) {
      _box = null;
    }
    return _box;
  }

  @override
  Future<String?> read(String key) async {
    try {
      return (await _open())?.get(key) as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String? value) async {
    try {
      final box = await _open();
      if (box == null) return;
      if (value == null) {
        await box.delete(key);
      } else {
        await box.put(key, value);
      }
    } catch (_) {}
  }
}

/// Everything the company (recruiter) side calls on our backend: company,
/// jobs, the candidate feed, swipe / undo, wishlist, saved searches, plans
/// and payments. Endpoint shapes are pinned in docs/PHASE23_CONTRACT.md.
///
/// Subclass and override in tests (the controllers only take this type).
class HiringService {
  HiringService({ApiClient? api, HiringPrefsStore? prefs})
      : _apiOverride = api,
        prefs = prefs ?? HiveHiringPrefs();

  static final HiringService instance = HiringService();

  final ApiClient? _apiOverride;
  ApiClient get _api => _apiOverride ?? ApiClient.instance;
  final HiringPrefsStore prefs;

  // -- shared state -------------------------------------------------------

  /// The company's swipe balance, shared by the header pill, the swipe
  /// screen, the plans screen and the paywall. -1 until first loaded.
  static final ValueNotifier<int> swipesLeft = ValueNotifier<int>(-1);

  /// The signed-in company, once loaded (also drives the header avatar).
  static final ValueNotifier<HiringCompany?> company = ValueNotifier<HiringCompany?>(null);

  /// A job id the Shortlisted tab should pre-select. Set by the Jobs screen
  /// ("Shortlisted" button) just before it switches to the tab
  /// (`AppNav.recruiterTab = 2`); the Shortlisted screen reads it and sets it
  /// back to null.
  static final ValueNotifier<String?> pendingShortlistedJobId = ValueNotifier<String?>(null);

  /// Bumped when the saved filters ("saved filters") change, so the
  /// Filters screen and a live swipe screen re-read them.
  static final ValueNotifier<int> savedFiltersChanged = ValueNotifier<int>(0);

  /// Bumped when a candidate goes back into the swipe deck (removed from the
  /// shortlist), so a live swipe screen restarts its feed from the top.
  static final ValueNotifier<int> deckRefresh = ValueNotifier<int>(0);

  void _setSwipes(Object? n) {
    if (n is num) swipesLeft.value = n.toInt() < 0 ? 0 : n.toInt();
  }

  /// Applies a balance learned outside this service (a purchase).
  void updateSwipes(int n) => _setSwipes(n);

  // -- company ------------------------------------------------------------

  /// GET /company/me. [company] is null before the recruiter has one.
  Future<({HiringCompany? company, String suggestedName})> fetchCompany() async {
    final res = await _api.get('/company/me');
    final raw = res['company'];
    final c = raw is Map ? HiringCompany.fromMap(Map<String, dynamic>.from(raw)) : null;
    if (c != null) {
      company.value = c;
      _setSwipes(c.swipesLeft);
    }
    return (company: c, suggestedName: (res['suggestedName'] ?? '').toString());
  }

  /// PUT /company/me with the given editable fields.
  Future<HiringCompany> saveCompany(Map<String, dynamic> fields) async {
    final res = await _api.put('/company/me', body: fields);
    final c = HiringCompany.fromMap(Map<String, dynamic>.from(res['company'] as Map));
    company.value = c;
    if (res['company'] is Map && (res['company'] as Map).containsKey('swipesLeft')) _setSwipes(c.swipesLeft);
    DataRefresh.instance.bump();
    return c;
  }

  /// POST /company/onboarding. Validation errors carry `field`.
  Future<({HiringCompany company, HiringJob? job})> onboard({
    required Map<String, dynamic> company,
    Map<String, dynamic>? job,
  }) async {
    final res = await _api.post('/company/onboarding', body: {'company': company, 'job': ?job});
    final c = HiringCompany.fromMap(Map<String, dynamic>.from(res['company'] as Map));
    HiringService.company.value = c;
    _setSwipes(c.swipesLeft);
    DataRefresh.instance.bump();
    return (
      company: c,
      job: res['job'] is Map ? HiringJob.fromMap(Map<String, dynamic>.from(res['job'] as Map)) : null,
    );
  }

  // -- jobs ---------------------------------------------------------------

  Future<List<HiringJob>> fetchJobs() async {
    final res = await _api.get('/jobs/mine');
    return [
      if (res['jobs'] is List)
        for (final j in res['jobs'] as List)
          if (j is Map) HiringJob.fromMap(Map<String, dynamic>.from(j)),
    ];
  }

  Future<HiringJob> createJob(Map<String, dynamic> body) async {
    final res = await _api.post('/jobs', body: body);
    DataRefresh.instance.bump();
    return HiringJob.fromMap(_unwrapJob(res));
  }

  Future<HiringJob> updateJob(String id, Map<String, dynamic> body) async {
    final res = await _api.put('/jobs/$id', body: body);
    DataRefresh.instance.bump();
    return HiringJob.fromMap(_unwrapJob(res, fallbackId: id));
  }

  /// PATCH /jobs/:id/status -- open | paused | closed.
  Future<HiringJob> setJobStatus(String id, String status) async {
    final res = await _api.patch('/jobs/$id/status', body: {'status': status});
    DataRefresh.instance.bump();
    return HiringJob.fromMap(_unwrapJob(res, fallbackId: id, fallbackStatus: status));
  }

  Map<String, dynamic> _unwrapJob(Map<String, dynamic> res, {String? fallbackId, String? fallbackStatus}) {
    final raw = res['job'] is Map ? Map<String, dynamic>.from(res['job'] as Map) : Map<String, dynamic>.from(res);
    if ((raw['id'] ?? '').toString().isEmpty && fallbackId != null) raw['id'] = fallbackId;
    if (raw['status'] == null && fallbackStatus != null) raw['status'] = fallbackStatus;
    return raw;
  }

  // -- feed ---------------------------------------------------------------

  /// GET /candidates for [jobId]. 409 = job paused/closed, 403 code NO_JOB.
  Future<FeedPage> fetchFeed({
    String? jobId,
    List<String> exclude = const [],
    int limit = 10,
    SwipeFilters filters = const SwipeFilters(),
    String? cursor,
  }) async {
    final res = await _api.get('/candidates', query: {
      'limit': '$limit',
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
      if (exclude.isNotEmpty) 'exclude': exclude.join(','),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      ...filters.toQuery(),
    });
    final cards = <Candidate>[
      if (res['candidates'] is List)
        for (final c in res['candidates'] as List)
          if (c is Map && c['id'] != null) Candidate.fromMap(c['id'].toString(), Map<String, dynamic>.from(c)),
    ];
    return FeedPage(
      candidates: cards,
      nextCursor: res['nextCursor'] as String?,
      hasMore: res['hasMore'] == true,
      swipesLeft: (res['swipesLeft'] as num?)?.toInt(),
      job: res['job'] is Map ? HiringJob.fromMap(Map<String, dynamic>.from(res['job'] as Map)) : null,
    );
  }

  // -- swipe / undo / wishlist --------------------------------------------

  /// POST /company/swipe. [action] is 'left' | 'right'. Does NOT touch the
  /// shared balance: the swipe controller reconciles it (optimistic swipes).
  Future<SwipeResult> swipe({required String candidateId, required String action, String? jobId}) async {
    final res = await _api.post('/company/swipe', body: {
      'candidateId': candidateId,
      'action': action,
      if (jobId != null && jobId.isNotEmpty) 'jobId': jobId,
    });
    final contact = res['contact'];
    final c = contact is Map ? contact : const {};
    return SwipeResult(
      swipesLeft: (res['swipesLeft'] as num?)?.toInt(),
      contactEmail: (c['email'] ?? '').toString(),
      contactPhone: (c['phone'] ?? '').toString(),
    );
  }

  Future<UndoResult> undo() async {
    final res = await _api.post('/company/swipe/undo');
    final card = res['card'];
    return UndoResult(
      swipesLeft: (res['swipesLeft'] as num?)?.toInt(),
      action: (res['action'] ?? '').toString(),
      jobId: (res['jobId'] ?? '').toString(),
      card: card is Map && card['id'] != null
          ? Candidate.fromMap(card['id'].toString(), Map<String, dynamic>.from(card))
          : null,
    );
  }

  Future<bool> setWishlisted(String candidateId, bool wishlisted) async {
    final res = await _api.put('/company/wishlist/$candidateId', body: {'wishlisted': wishlisted});
    return res['wishlisted'] != false && wishlisted;
  }

  Future<List<Candidate>> fetchWishlist() async {
    final res = await _api.get('/company/wishlist');
    return [
      if (res['candidates'] is List)
        for (final c in res['candidates'] as List)
          if (c is Map && c['id'] != null) Candidate.fromMap(c['id'].toString(), Map<String, dynamic>.from(c)),
    ];
  }

  // -- saved searches -----------------------------------------------------

  Future<List<SavedSearch>> fetchSearches() async {
    final res = await _api.get('/company/searches');
    return [
      if (res['searches'] is List)
        for (final s in res['searches'] as List)
          if (s is Map) SavedSearch.fromMap(Map<String, dynamic>.from(s)),
    ];
  }

  Future<SavedSearch> createSearch({required String name, required SwipeFilters filters, bool alerts = true}) async {
    final res = await _api.post('/company/searches', body: {
      'name': name,
      'filters': filters.toJson(),
      'alerts': alerts,
    });
    final raw = res['search'];
    if (raw is Map) return SavedSearch.fromMap(Map<String, dynamic>.from(raw));
    return SavedSearch(id: '', name: name, filters: filters, alerts: alerts);
  }

  Future<void> setSearchAlerts(String id, bool alerts) async {
    await _api.patch('/company/searches/$id', body: {'alerts': alerts});
  }

  Future<void> deleteSearch(String id) async {
    await _api.delete('/company/searches/$id');
  }

  // -- plans & payment ----------------------------------------------------

  Future<PlansInfo> fetchPlans() async => PlansInfo.fromMap(await _api.get('/payment/plans'));

  Future<PaymentOrder> createOrder(String planId) async =>
      PaymentOrder.fromMap(await _api.post('/payment/order', body: {'planId': planId}));

  /// POST /payment/verify. Demo mode sends only [orderId]. Updates the
  /// shared balance.
  Future<VerifyResult> verifyPayment({required String orderId, String? paymentId, String? signature}) async {
    final res = await _api.post('/payment/verify', body: {
      'orderId': orderId,
      'paymentId': ?paymentId,
      'signature': ?signature,
    });
    final left = (res['swipesLeft'] as num?)?.toInt();
    _setSwipes(left);
    DataRefresh.instance.bump();
    return VerifyResult(swipesLeft: left, added: (res['added'] as num?)?.toInt() ?? 0);
  }

  // -- unread messages ----------------------------------------------------

  Future<int> unreadMessageCount() async {
    final res = await _api.get('/chats/unread-count');
    return (res['count'] as num?)?.toInt() ?? 0;
  }

  // -- remembered choices -------------------------------------------------

  String _jobKey(String companyId) => 'job_$companyId';
  String _filtersKey(String userId) => 'filters_$userId';

  Future<String?> lastJobId(String companyId) => prefs.read(_jobKey(companyId));

  Future<void> rememberJob(String companyId, String jobId) => prefs.write(_jobKey(companyId), jobId);

  /// The filter last applied on the swipe screen. Empty until the recruiter
  /// sets one -- swiping stays locked until then.
  Future<SwipeFilters> loadFilters(String userId) async {
    final raw = await prefs.read(_filtersKey(userId));
    if (raw == null || raw.isEmpty) return const SwipeFilters();
    try {
      return SwipeFilters.fromJson(jsonDecode(raw));
    } catch (_) {
      return const SwipeFilters();
    }
  }

  Future<void> saveFilters(String userId, SwipeFilters filters) =>
      prefs.write(_filtersKey(userId), filters.isEmpty ? null : jsonEncode(filters.toJson()));
}
