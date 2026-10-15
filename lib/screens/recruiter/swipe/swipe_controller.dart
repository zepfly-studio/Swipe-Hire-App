import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../models/candidate.dart';
import '../../../models/hiring_job.dart';
import '../../../models/swipe_filters.dart';
import '../../../services/api_client.dart';
import '../../../services/hiring_service.dart';
import 'swipe_decision.dart';

/// What the card area shows (spec C2 "Empty and other states").
enum SwipeViewState { loading, ready, noJobs, error, outOfSwipes, noFilterMatch, seenEveryone }

enum SwipeEventType { paywall, toast, errorToast, shortlisted, undone }

/// A one-off thing the UI should react to (toast, paywall, flash...).
class SwipeEvent {
  final SwipeEventType type;
  final String message;
  final Candidate? candidate;
  final String email;
  final String action;
  final Duration duration;

  const SwipeEvent(
    this.type, {
    this.message = '',
    this.candidate,
    this.email = '',
    this.action = '',
    this.duration = const Duration(milliseconds: 3500),
  });
}

/// All the swipe-screen logic that is not drawing: job + filter selection,
/// the card stack and feed paging, optimistic swipes with credit
/// reconciliation, undo, wishlist and saved searches. The widget only
/// renders [viewState] and forwards gestures, so this is unit-testable
/// with a fake [HiringService].
class SwipeController extends ChangeNotifier {
  SwipeController({required this.service, this.pageSize = 10});

  final HiringService service;
  final int pageSize;

  /// Receives toasts, paywall requests and the shortlist flash.
  void Function(SwipeEvent event)? onEvent;

  // -- state --------------------------------------------------------------

  String companyId = '';
  List<HiringJob> jobs = [];
  HiringJob? job;
  SwipeFilters filters = const SwipeFilters();
  List<SavedSearch> searches = [];
  final List<Candidate> stack = [];

  bool loadingJobs = true;
  bool loadingFeed = false;
  String? feedError;
  bool noJob = false;
  bool exhausted = false;
  bool undoing = false;

  /// Swipes made on this job that can still be undone (server: last 10 min).
  int undoCount = 0;

  final Set<String> _pending = {};
  String? _cursor;
  int _feedGen = 0;
  int _jobGen = 0;
  int _lastBalance = HiringService.swipesLeft.value;
  bool _disposed = false;

  // -- derived ------------------------------------------------------------

  List<HiringJob> get openJobs => jobs.where((j) => j.isOpen).toList();
  int get balance => HiringService.swipesLeft.value;
  int get pendingCount => _pending.length;
  Candidate? get top => stack.isEmpty ? null : stack.first;
  bool get canUndo => undoCount > 0 && !undoing && _pending.isEmpty;

  SwipeViewState get viewState {
    if (loadingJobs) return SwipeViewState.loading;
    if (noJob || openJobs.isEmpty) return SwipeViewState.noJobs;
    if (stack.isNotEmpty) return SwipeViewState.ready;
    if (feedError != null) return SwipeViewState.error;
    if (loadingFeed) return SwipeViewState.loading;
    if (balance == 0) return SwipeViewState.outOfSwipes;
    if (exhausted) {
      return filters.isEmpty ? SwipeViewState.seenEveryone : SwipeViewState.noFilterMatch;
    }
    return SwipeViewState.loading;
  }

  // -- lifecycle ----------------------------------------------------------

  void _emit(SwipeEvent e) => onEvent?.call(e);

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    HiringService.swipesLeft.removeListener(_onBalance);
    HiringService.deckRefresh.removeListener(_onDeckRefresh);
    super.dispose();
  }

  /// A candidate was taken out of the shortlist and is unswiped again:
  /// restart the feed from the top so they can show up, and top the stack up.
  void _onDeckRefresh() {
    if (_disposed || job == null) return;
    _cursor = null;
    exhausted = false;
    feedError = null;
    notifyListeners();
    unawaited(_maybeLoadMore());
  }

  void _setBalance(int v) {
    final next = v < 0 ? 0 : v;
    _lastBalance = next;
    HiringService.swipesLeft.value = next;
  }

  /// The balance went up outside this controller (a purchase from the
  /// header pill or the plans screen): the feed may have more to give.
  void _onBalance() {
    final now = HiringService.swipesLeft.value;
    final grew = now > _lastBalance;
    _lastBalance = now;
    if (grew && !loadingJobs && stack.length < 3) {
      exhausted = false;
      feedError = null;
      notifyListeners();
      _maybeLoadMore();
    }
  }

  /// Loads company, jobs, remembered filters and saved searches, picks the
  /// job (preferred -> last used -> first open) and fetches the first cards.
  Future<void> init({String? preferJobId, String? searchId}) async {
    HiringService.swipesLeft.removeListener(_onBalance);
    loadingJobs = true;
    feedError = null;
    notifyListeners();
    try {
      final res = await service.fetchCompany();
      companyId = res.company?.id ?? '';
      _lastBalance = HiringService.swipesLeft.value;
      jobs = await service.fetchJobs();
      if (companyId.isNotEmpty) filters = await service.loadFilters(companyId);
      try {
        searches = await service.fetchSearches();
      } catch (_) {
        searches = [];
      }
      if (searchId != null) {
        final s = searches.where((e) => e.id == searchId);
        if (s.isNotEmpty) filters = s.first.filters;
      }
      final open = openJobs;
      HiringJob? pick;
      if (preferJobId != null) pick = open.where((j) => j.id == preferJobId).firstOrNull;
      if (pick == null && companyId.isNotEmpty) {
        final last = await service.lastJobId(companyId);
        if (last != null) pick = open.where((j) => j.id == last).firstOrNull;
      }
      pick ??= open.isEmpty ? null : open.first;
      job = pick;
      noJob = pick == null;
      loadingJobs = false;
      HiringService.swipesLeft.addListener(_onBalance);
      HiringService.deckRefresh.addListener(_onDeckRefresh);
      notifyListeners();
      if (pick != null) {
        if (companyId.isNotEmpty) service.rememberJob(companyId, pick.id);
        await _maybeLoadMore();
      }
    } on ApiException catch (e) {
      loadingJobs = false;
      feedError = e.message;
      notifyListeners();
    } catch (_) {
      loadingJobs = false;
      feedError = 'Could not load candidates';
      notifyListeners();
    }
  }

  /// Re-reads the jobs (after a job was posted, paused or reopened).
  Future<void> reloadJobs() async {
    if (loadingJobs) return;
    try {
      jobs = await service.fetchJobs();
    } catch (_) {
      return;
    }
    final open = openJobs;
    final current = job;
    if (current != null && open.any((j) => j.id == current.id)) {
      job = open.firstWhere((j) => j.id == current.id);
      notifyListeners();
      return;
    }
    if (open.isEmpty) {
      job = null;
      noJob = true;
      _resetFeed();
      notifyListeners();
    } else {
      await selectJob(open.first.id);
    }
  }

  // -- job & filters ------------------------------------------------------

  void _resetFeed() {
    _feedGen++;
    stack.clear();
    _cursor = null;
    exhausted = false;
    feedError = null;
    loadingFeed = false;
  }

  Future<void> selectJob(String id) async {
    final next = openJobs.where((j) => j.id == id).firstOrNull;
    if (next == null || next.id == job?.id) return;
    job = next;
    noJob = false;
    _jobGen++;
    undoCount = 0;
    _pending.clear();
    _resetFeed();
    notifyListeners();
    if (companyId.isNotEmpty) service.rememberJob(companyId, next.id);
    await _maybeLoadMore();
  }

  Future<void> setFilters(SwipeFilters next) async {
    if (next == filters) return;
    filters = next;
    if (companyId.isNotEmpty) service.saveFilters(companyId, next);
    _resetFeed();
    notifyListeners();
    await _maybeLoadMore();
  }

  Future<void> clearFilters() => setFilters(const SwipeFilters());

  Future<void> applySavedSearch(SavedSearch s) => setFilters(s.filters);

  /// Applies a saved search by id (an alert notification link). Reloads the
  /// list once when the id is not known yet; unknown ids are ignored.
  Future<void> applySearchById(String id) async {
    var match = searches.where((s) => s.id == id).firstOrNull;
    if (match == null) {
      try {
        searches = await service.fetchSearches();
        notifyListeners();
      } catch (_) {
        return;
      }
      match = searches.where((s) => s.id == id).firstOrNull;
    }
    if (match != null) await applySavedSearch(match);
  }

  /// Try again after a feed error.
  Future<void> retry() async {
    feedError = null;
    exhausted = false;
    notifyListeners();
    if (jobs.isEmpty && job == null) {
      await init();
    } else {
      await _maybeLoadMore();
    }
  }

  // -- feed ---------------------------------------------------------------

  /// Fetches more cards when fewer than 3 remain. Never asks for more than
  /// the swipes left (minus the cards already in the stack).
  Future<void> _maybeLoadMore() async {
    final current = job;
    if (current == null || loadingFeed || exhausted || feedError != null || stack.length >= 3) return;
    final wanted = balance - stack.length;
    if (wanted <= 0) {
      notifyListeners();
      return;
    }
    final gen = ++_feedGen;
    loadingFeed = true;
    notifyListeners();
    try {
      final page = await service.fetchFeed(
        jobId: current.id,
        exclude: [...stack.map((c) => c.id), ..._pending],
        limit: math.min(pageSize, wanted),
        filters: filters,
        cursor: _cursor,
      );
      if (gen != _feedGen) return;
      final known = {...stack.map((c) => c.id), ..._pending};
      final fresh = page.candidates.where((c) => !known.contains(c.id)).toList();
      // Never show more cards than the swipes that can pay for them.
      final room = math.max(0, balance - stack.length);
      stack.addAll(fresh.take(room));
      _cursor = page.nextCursor;
      if (page.swipesLeft != null) _setBalance(page.swipesLeft! - _pending.length);
      if (fresh.isEmpty) exhausted = true;
      loadingFeed = false;
      notifyListeners();
    } on ApiException catch (e) {
      if (gen != _feedGen) return;
      loadingFeed = false;
      if (e.statusCode == 403 && e.body['code'] == 'NO_JOB') {
        noJob = true;
        jobs = [];
        job = null;
      } else {
        feedError = e.message;
      }
      notifyListeners();
    } catch (_) {
      if (gen != _feedGen) return;
      loadingFeed = false;
      feedError = 'Could not load candidates';
      notifyListeners();
    }
  }

  // -- swipe --------------------------------------------------------------

  /// Swipes the top card. The stack and the balance change synchronously
  /// (optimistic); the returned future completes when the server answered.
  Future<void> swipe(SwipeDir dir) async {
    if (stack.isEmpty || job == null) return;
    if (balance <= 0) {
      _emit(const SwipeEvent(SwipeEventType.paywall));
      return;
    }
    final card = stack.removeAt(0);
    final gen = _jobGen;
    final jobId = job!.id;
    _pending.add(card.id);
    _setBalance(balance - 1);
    notifyListeners();
    _maybeLoadMore();

    try {
      final res = await service.swipe(candidateId: card.id, action: dir.action, jobId: jobId);
      _pending.remove(card.id);
      if (res.swipesLeft != null) _setBalance(res.swipesLeft! - _pending.length);
      if (gen == _jobGen) undoCount++;
      if (dir == SwipeDir.right) {
        _emit(SwipeEvent(SwipeEventType.shortlisted, candidate: card, email: res.contactEmail));
      }
    } on ApiException catch (e) {
      _pending.remove(card.id);
      _setBalance(balance + 1); // the credit comes back first
      final code = e.body['code'];
      if (code == 'NO_SWIPES' || e.statusCode == 402) {
        _setBalance(0);
        if (gen == _jobGen) stack.insert(0, card);
        _emit(const SwipeEvent(SwipeEventType.paywall));
      } else if (code == 'SALARY_MISMATCH') {
        _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message, duration: const Duration(seconds: 6)));
      } else if (e.statusCode == 409) {
        // Already swiped for this job: nothing to say.
      } else {
        if (gen == _jobGen) stack.insert(0, card);
        _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message));
      }
    } catch (_) {
      _pending.remove(card.id);
      _setBalance(balance + 1);
      if (gen == _jobGen) stack.insert(0, card);
      _emit(const SwipeEvent(SwipeEventType.errorToast, message: 'Could not save that swipe. Please try again.'));
    }
    notifyListeners();
    _maybeLoadMore();
  }

  // -- undo ---------------------------------------------------------------

  Future<void> undo() async {
    if (!canUndo) return;
    undoing = true;
    notifyListeners();
    try {
      final r = await service.undo();
      final left = r.swipesLeft ?? (r.wasRight ? balance : balance + 1);
      _setBalance(left - _pending.length);
      if (undoCount > 0) undoCount--;
      final card = r.card;
      final sameJob = r.jobId.isEmpty || r.jobId == job?.id;
      if (card != null && sameJob && !stack.any((c) => c.id == card.id)) {
        stack.insert(0, card);
        exhausted = false;
      }
      _emit(SwipeEvent(
        SwipeEventType.undone,
        candidate: card,
        action: r.action,
        message: r.wasRight
            ? 'Shortlist undone. Its swipe is not refunded, as contact details were shown.'
            : 'Pass undone, swipe refunded',
      ));
    } on ApiException catch (e) {
      if (e.statusCode == 404) undoCount = 0;
      _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message));
    } catch (_) {
      _emit(const SwipeEvent(SwipeEventType.errorToast, message: 'Could not undo. Please try again.'));
    } finally {
      undoing = false;
    }
    notifyListeners();
  }

  // -- wishlist -----------------------------------------------------------

  void _replace(Candidate c) {
    final i = stack.indexWhere((e) => e.id == c.id);
    if (i >= 0) stack[i] = c;
  }

  Future<void> toggleWishlist([Candidate? target]) async {
    final card = target ?? top;
    if (card == null) return;
    final next = !card.wishlisted;
    _replace(card.copyWith(wishlisted: next));
    notifyListeners();
    try {
      await service.setWishlisted(card.id, next);
      _emit(SwipeEvent(SwipeEventType.toast, message: next ? 'Added to wishlist' : 'Removed from wishlist'));
    } on ApiException catch (e) {
      _replace(card.copyWith(wishlisted: !next));
      _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message));
      notifyListeners();
    } catch (_) {
      _replace(card.copyWith(wishlisted: !next));
      _emit(const SwipeEvent(SwipeEventType.errorToast, message: 'Could not update your wishlist.'));
      notifyListeners();
    }
  }

  // -- saved searches -----------------------------------------------------

  /// Returns an error message, or null on success.
  Future<String?> saveSearch(String name, SwipeFilters f) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Give this search a name';
    if (f.isEmpty) return 'Set at least one filter before saving the search';
    try {
      final s = await service.createSearch(name: trimmed, filters: f, alerts: true);
      searches = [s, ...searches];
      notifyListeners();
      _emit(SwipeEvent(
        SwipeEventType.toast,
        message: 'Saved "$trimmed". We\'ll alert you about new matches.',
      ));
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not save the search. Please try again.';
    }
  }

  Future<void> toggleSearchAlerts(SavedSearch s) async {
    final next = !s.alerts;
    searches = [for (final e in searches) e.id == s.id ? e.copyWith(alerts: next) : e];
    notifyListeners();
    try {
      await service.setSearchAlerts(s.id, next);
    } catch (e) {
      searches = [for (final x in searches) x.id == s.id ? x.copyWith(alerts: s.alerts) : x];
      notifyListeners();
      _emit(SwipeEvent(
        SwipeEventType.errorToast,
        message: e is ApiException ? e.message : 'Could not change the alert.',
      ));
    }
  }

  Future<void> deleteSearch(SavedSearch s) async {
    final before = searches;
    searches = searches.where((e) => e.id != s.id).toList();
    notifyListeners();
    try {
      await service.deleteSearch(s.id);
    } catch (_) {
      searches = before;
      notifyListeners();
    }
  }
}
