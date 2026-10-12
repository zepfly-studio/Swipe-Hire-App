import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/candidate.dart';

/// Local persistence for the recruiter's two-stage funnel, using Hive so it
/// survives app restarts without needing a backend:
///   1. Wishlist -- candidates saved via the card's Wishlist button.
///   2. Shortlist -- candidates promoted from the wishlist for final hire
///      consideration (via [moveToShortlist]).
/// Left-swipe rejections are tracked separately so they don't reappear in
/// the swipe deck.
class WishlistService {
  WishlistService._internal();
  static final WishlistService instance = WishlistService._internal();

  static const String _wishlistBox = 'shortlisted_candidates';
  static const String _shortlistBox = 'final_shortlist_candidates';
  static const String _rejectedBox = 'rejected_candidates';
  static const String _seenBox = 'seen_candidate_ids';

  late Box<Map> _wishlist;
  late Box<Map> _shortlist;
  late Box<Map> _rejected;
  late Box<bool> _seen;

  Future<void> init() async {
    await Hive.initFlutter();
    _wishlist = await Hive.openBox<Map>(_wishlistBox);
    _shortlist = await Hive.openBox<Map>(_shortlistBox);
    _rejected = await Hive.openBox<Map>(_rejectedBox);
    _seen = await Hive.openBox<bool>(_seenBox);
  }

  bool hasBeenSwiped(String candidateId) => _seen.containsKey(candidateId);

  /// Card's Wishlist button: save a candidate for later review.
  Future<void> shortlist(Candidate candidate) async {
    await _rejected.delete(candidate.id);
    await _wishlist.put(candidate.id, candidate.toMap());
    await _seen.put(candidate.id, true);
  }

  Future<void> reject(Candidate candidate) async {
    await _wishlist.delete(candidate.id);
    await _shortlist.delete(candidate.id);
    await _rejected.put(candidate.id, candidate.toMap());
    await _seen.put(candidate.id, true);
  }

  /// Promotes a wishlisted candidate to the final shortlist.
  Future<void> moveToShortlist(Candidate candidate) async {
    await _wishlist.delete(candidate.id);
    await _shortlist.put(candidate.id, candidate.toMap());
  }

  /// Sends a shortlisted candidate back to the wishlist for reconsideration.
  Future<void> demoteToWishlist(Candidate candidate) async {
    await _shortlist.delete(candidate.id);
    await _wishlist.put(candidate.id, candidate.toMap());
  }

  /// Fully removes a candidate from the shortlist (they stay marked as seen
  /// so they won't reappear in the swipe deck).
  Future<void> removeFromShortlist(String candidateId) async {
    await _shortlist.delete(candidateId);
  }

  /// Reverses a wishlist/reject decision entirely -- the candidate becomes
  /// unseen again and can reappear in the swipe deck.
  Future<void> undoLast(String candidateId) async {
    await _wishlist.delete(candidateId);
    await _shortlist.delete(candidateId);
    await _rejected.delete(candidateId);
    await _seen.delete(candidateId);
  }

  List<Candidate> getShortlisted() => _readAll(_wishlist);

  List<Candidate> getFinalShortlist() => _readAll(_shortlist);

  List<Candidate> _readAll(Box<Map> box) {
    return box.keys.map((key) {
      final map = Map<String, dynamic>.from(box.get(key) as Map);
      return Candidate.fromMap(key as String, map);
    }).toList();
  }

  ValueListenable<Box<Map>> listenableShortlist() => _wishlist.listenable();
  ValueListenable<Box<Map>> listenableFinalShortlist() => _shortlist.listenable();

  int get shortlistCount => _wishlist.length;
  int get finalShortlistCount => _shortlist.length;
  int get rejectedCount => _rejected.length;
}
