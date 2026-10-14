import 'package:flutter/foundation.dart';
import '../models/candidate.dart';
import 'api_client.dart';
import 'error_reporter.dart';

/// The recruiter's two-stage funnel, stored on the backend (`swipes` table,
/// `/swipes` routes) so it is the same on every device and survives a
/// reinstall:
///   1. Wishlist -- candidates saved via the card's Wishlist button.
///   2. Shortlist -- candidates promoted from the wishlist for final hire
///      consideration (via [moveToShortlist]).
/// Right-swipe rejections are tracked too so they don't reappear in the
/// swipe deck. Everything is cached in memory after [loadForUser] so the
/// screens stay synchronous; every mutation updates the cache first and
/// then the backend.
class WishlistService {
  WishlistService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final WishlistService instance = WishlistService._internal();

  final ApiClient _api;

  final ValueNotifier<List<Candidate>> _wishlist = ValueNotifier(const []);
  final ValueNotifier<List<Candidate>> _shortlist = ValueNotifier(const []);
  final Set<String> _rejectedIds = {};

  String? _loadedForUid;
  Future<void>? _loading;

  /// Called by [AuthGate] when a recruiter signs in. Idempotent per uid.
  Future<void> loadForUser(String uid) {
    if (_loadedForUid == uid && _loading != null) return _loading!;
    _loadedForUid = uid;
    return _loading = _refresh();
  }

  /// Waits for the sign-in load (if one is in flight) -- the swipe deck
  /// awaits this before filtering out already-swiped candidates.
  Future<void> ensureLoaded() => _loading ?? Future.value();

  Future<void> _refresh() async {
    try {
      final res = await _api.get('/swipes');
      List<Candidate> parse(String key) => (res[key] as List? ?? const [])
          .map((e) => Candidate.fromMap(e['id'] as String, Map<String, dynamic>.from(e as Map)))
          .toList();
      _wishlist.value = parse('wishlist');
      _shortlist.value = parse('shortlist');
      _rejectedIds
        ..clear()
        ..addAll((res['rejectedIds'] as List? ?? const []).map((e) => e.toString()));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'WishlistService: load failed');
    }
  }

  /// Forgets the cached funnel on sign-out so the next account starts clean.
  void clear() {
    _loadedForUid = null;
    _loading = null;
    _wishlist.value = const [];
    _shortlist.value = const [];
    _rejectedIds.clear();
  }

  bool hasBeenSwiped(String candidateId) =>
      _rejectedIds.contains(candidateId) || _has(_wishlist, candidateId) || _has(_shortlist, candidateId);

  bool _has(ValueNotifier<List<Candidate>> list, String id) => list.value.any((c) => c.id == id);

  void _remove(ValueNotifier<List<Candidate>> list, String id) {
    if (_has(list, id)) list.value = list.value.where((c) => c.id != id).toList();
  }

  void _add(ValueNotifier<List<Candidate>> list, Candidate candidate) {
    _remove(list, candidate.id);
    list.value = [candidate, ...list.value];
  }

  Future<void> _put(String candidateId, String state) async {
    try {
      await _api.put('/swipes/$candidateId', body: {'state': state});
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'WishlistService: save swipe failed');
    }
  }

  /// Card's Wishlist button: save a candidate for later review.
  Future<void> shortlist(Candidate candidate) async {
    _rejectedIds.remove(candidate.id);
    _remove(_shortlist, candidate.id);
    _add(_wishlist, candidate);
    await _put(candidate.id, 'wishlist');
  }

  Future<void> reject(Candidate candidate) async {
    _remove(_wishlist, candidate.id);
    _remove(_shortlist, candidate.id);
    _rejectedIds.add(candidate.id);
    await _put(candidate.id, 'rejected');
  }

  /// Promotes a wishlisted candidate to the final shortlist.
  Future<void> moveToShortlist(Candidate candidate) async {
    _remove(_wishlist, candidate.id);
    _add(_shortlist, candidate);
    await _put(candidate.id, 'shortlist');
  }

  /// Sends a shortlisted candidate back to the wishlist for reconsideration.
  Future<void> demoteToWishlist(Candidate candidate) async {
    _remove(_shortlist, candidate.id);
    _add(_wishlist, candidate);
    await _put(candidate.id, 'wishlist');
  }

  /// Fully removes a candidate from the shortlist (they stay marked as seen
  /// so they won't reappear in the swipe deck).
  Future<void> removeFromShortlist(String candidateId) async {
    _remove(_shortlist, candidateId);
    _rejectedIds.add(candidateId);
    await _put(candidateId, 'rejected');
  }

  /// Reverses a wishlist/reject decision entirely -- the candidate becomes
  /// unseen again and can reappear in the swipe deck.
  Future<void> undoLast(String candidateId) async {
    _remove(_wishlist, candidateId);
    _remove(_shortlist, candidateId);
    _rejectedIds.remove(candidateId);
    try {
      await _api.delete('/swipes/$candidateId');
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'WishlistService: undo failed');
    }
  }

  List<Candidate> getShortlisted() => _wishlist.value;

  List<Candidate> getFinalShortlist() => _shortlist.value;

  ValueListenable<List<Candidate>> listenableShortlist() => _wishlist;
  ValueListenable<List<Candidate>> listenableFinalShortlist() => _shortlist;

  int get shortlistCount => _wishlist.value.length;
  int get finalShortlistCount => _shortlist.value.length;
}
