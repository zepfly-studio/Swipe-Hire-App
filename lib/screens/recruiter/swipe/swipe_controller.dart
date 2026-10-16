import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../models/candidate.dart';
import '../../../models/swipe_filters.dart';
import '../../../services/api_client.dart';
import '../../../services/hiring_service.dart';
import 'swipe_decision.dart';

/// What the card area shows (spec C2 "Empty and other states").
enum SwipeViewState { loading, ready, needsFilter, error, outOfSwipes, noFilterMatch }

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

/// The private job every swipe of this screen is filed under: recruiters do
/// not post jobs, they filter candidates (the backend creates it on first use).
const String kGeneralJob = 'general';

/// All the swipe-screen logic that is not drawing: the filter, the card stack and feed paging, optimistic swipes with credit
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
  SwipeFilters filters = const SwipeFilters();
  List<SavedSearch> searches = [];
  final List<Candidate> stack = [];

  bool loadingSetup = true;
  bool loadingFeed = false;
  String? feedError;
  bool exhausted = false;
  bool undoing = false;

  /// Swipes that can still be undone (server: last 10 min).
  int undoCount = 0;

  final Set<String> _pending = {};
  String? _cursor;
  int _feedGen = 0;
  int _lastBalance = HiringService.swipesLeft.value;
  bool _disposed = false;

  // -- derived ------------------------------------------------------------

  int get balance => HiringService.swipesLeft.value;
  int get pendingCount => _pending.length;
  Candidate? get top => stack.isEmpty ? null : stack.first;

  bool get canUndo => undoCount > 0 && !undoing && _pending.isEmpty;

  SwipeViewState get viewState {
    if (loadingSetup) return SwipeViewState.loading;
    // No filter, no candidates: nothing is shown until one is applied.
    if (filters.isEmpty) return SwipeViewState.needsFilter;
    if (stack.isNotEmpty) return SwipeViewState.ready;
    if (feedError != null) return SwipeViewState.error;
    if (loadingFeed) return SwipeViewState.loading;
    if (balance == 0) return SwipeViewState.outOfSwipes;
    if (exhausted) return SwipeViewState.noFilterMatch;
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
    if (_disposed || loadingSetup) return;
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
    if (grew && !loadingSetup && stack.length < 3) {
      exhausted = false;
      feedError = null;
      notifyListeners();
      _maybeLoadMore();
    }
  }

  /// Loads the company, the remembered filter and the saved filters, then
  /// fetches the first cards (none while no filter is applied).
  Future<void> init({String? searchId}) async {
    HiringService.swipesLeft.removeListener(_onBalance);
    loadingSetup = true;
    feedError = null;
    notifyListeners();
    try {
      final res = await service.fetchCompany();
      companyId = res.company?.id ?? '';
      _lastBalance = HiringService.swipesLeft.value;
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
      loadingSetup = false;
      HiringService.swipesLeft.addListener(_onBalance);
      HiringService.deckRefresh.addListener(_onDeckRefresh);
      notifyListeners();
      await _maybeLoadMore();
    } on ApiException catch (e) {
      loadingSetup = false;
      feedError = e.message;
      notifyListeners();
    } catch (_) {
      loadingSetup = false;
      feedError = 'Could not load candidates';
      notifyListeners();
    }
  }

  // -- filters ------------------------------------------------------------

  void _resetFeed() {
    _feedGen++;
    stack.clear();
    _cursor = null;
    exhausted = false;
    feedError = null;
    loadingFeed = false;
  }

  /// Re-reads the filter last applied (it can be cleared from the Filters
  /// screen) and restarts the feed when it differs.
  Future<void> reloadActiveFilter() async {
    if (loadingSetup || companyId.isEmpty) return;
    final saved = await service.loadFilters(companyId);
    if (_disposed || saved == filters) return;
    filters = saved;
    _resetFeed();
    notifyListeners();
    await _maybeLoadMore();
  }

  /// Re-reads the saved filters (changed on the Filters screen).
  Future<void> reloadSearches() async {
    try {
      final next = await service.fetchSearches();
      searches = next;
      notifyListeners();
    } catch (_) {}
  }

  /// Applies [next], remembers it and saves it as a filter (shown on the
  /// Filters screen). An empty filter hides all candidates again.
  Future<void> setFilters(SwipeFilters next) async {
    if (next == filters) return;
    filters = next;
    if (companyId.isNotEmpty) await service.saveFilters(companyId, next);
    if (_disposed) return;
    _resetFeed();
    notifyListeners();
    unawaited(_saveAsFilter(next));
    await _maybeLoadMore();
  }

  bool _savingFilter = false;

  /// A filter the recruiter applies becomes a saved filter (alerts off
  /// until they switch them on). Already saved or over the limit: nothing.
  Future<void> _saveAsFilter(SwipeFilters f) async {
    if (f.isEmpty || _savingFilter) return;
    if (searches.any((s) => s.filters == f)) {
      HiringService.savedFiltersChanged.value++; // the Filters screen marks it active
      return;
    }
    _savingFilter = true;
    try {
      final s = await service.createSearch(name: f.label, filters: f, alerts: false);
      searches = [s, ...searches];
      notifyListeners();
      HiringService.savedFiltersChanged.value++;
    } catch (_) {
      // Limit reached or offline: the filter still works, it is just not listed.
    } finally {
      _savingFilter = false;
    }
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
    if (companyId.isEmpty) {
      await init();
    } else {
      await _maybeLoadMore();
    }
  }

  // -- feed ---------------------------------------------------------------

  /// Fetches more cards when fewer than 3 remain. Never asks for more than
  /// the swipes left (minus the cards already in the stack).
  Future<void> _maybeLoadMore() async {
    if (filters.isEmpty || loadingFeed || exhausted || feedError != null || stack.length >= 3) return;
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
        jobId: kGeneralJob,
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
      feedError = e.message;
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
    if (stack.isEmpty || filters.isEmpty) return;
    if (balance <= 0) {
      _emit(const SwipeEvent(SwipeEventType.paywall));
      return;
    }
    final card = stack.removeAt(0);
    _pending.add(card.id);
    _setBalance(balance - 1);
    notifyListeners();
    _maybeLoadMore();

    try {
      final res = await service.swipe(candidateId: card.id, action: dir.action, jobId: kGeneralJob);
      _pending.remove(card.id);
      if (res.swipesLeft != null) _setBalance(res.swipesLeft! - _pending.length);
      undoCount++;
      if (dir == SwipeDir.right) {
        _emit(SwipeEvent(SwipeEventType.shortlisted, candidate: card, email: res.contactEmail));
      }
    } on ApiException catch (e) {
      _pending.remove(card.id);
      _setBalance(balance + 1); // the credit comes back first
      final code = e.body['code'];
      if (code == 'NO_SWIPES' || e.statusCode == 402) {
        _setBalance(0);
        stack.insert(0, card);
        _emit(const SwipeEvent(SwipeEventType.paywall));
      } else if (code == 'SALARY_MISMATCH') {
        _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message, duration: const Duration(seconds: 6)));
      } else if (e.statusCode == 409) {
        // Already swiped: nothing to say.
      } else {
        stack.insert(0, card);
        _emit(SwipeEvent(SwipeEventType.errorToast, message: e.message));
      }
    } catch (_) {
      _pending.remove(card.id);
      _setBalance(balance + 1);
      stack.insert(0, card);
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
      if (card != null && !stack.any((c) => c.id == card.id)) {
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
