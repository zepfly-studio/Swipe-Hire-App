import 'package:hiring_app/models/candidate.dart';
import 'package:hiring_app/models/hiring_company.dart';
import 'package:hiring_app/models/hiring_job.dart';
import 'package:hiring_app/models/swipe_filters.dart';
import 'package:hiring_app/models/swipe_models.dart';
import 'package:hiring_app/services/hiring_service.dart';

Candidate card(String id, {String name = 'Asha Rao', bool wishlisted = false}) =>
    Candidate.fromMap(id, {'name': name, 'wishlisted': wishlisted, 'skills': ['React']});

/// An in-memory stand-in for the backend, used by the controller tests.
class FakeHiringService extends HiringService {
  FakeHiringService() : super(prefs: MemoryHiringPrefs());

  HiringCompany? companyResult = const HiringCompany(id: 'c1', name: 'Acme');
  List<HiringJob> jobs = [const HiringJob(id: 'j1', title: 'Frontend Dev', location: 'Jaipur')];
  List<SavedSearch> searches = [];

  /// Pages returned by successive [fetchFeed] calls (empty after that).
  final List<List<Candidate>> pages = [];
  final List<({String? jobId, List<String> exclude, int limit, SwipeFilters filters})> feedCalls = [];
  Object? feedError;

  /// The server's balance, decremented by [swipe].
  int serverSwipes = 5;
  Object? swipeError;
  final List<({String id, String action, String? jobId})> swipeCalls = [];
  String contactEmail = 'asha@example.com';

  Object? undoError;
  UndoResult? undoResult;
  int undoCalls = 0;

  Object? wishlistError;
  final List<({String id, bool value})> wishlistCalls = [];

  @override
  Future<({HiringCompany? company, String suggestedName})> fetchCompany() async {
    HiringService.swipesLeft.value = serverSwipes;
    return (company: companyResult, suggestedName: '');
  }

  @override
  Future<List<HiringJob>> fetchJobs() async => jobs;

  @override
  Future<List<SavedSearch>> fetchSearches() async => searches;

  @override
  Future<FeedPage> fetchFeed({
    String? jobId,
    List<String> exclude = const [],
    int limit = 10,
    SwipeFilters filters = const SwipeFilters(),
    String? cursor,
  }) async {
    feedCalls.add((jobId: jobId, exclude: exclude, limit: limit, filters: filters));
    if (feedError != null) throw feedError!;
    final next = pages.isEmpty ? <Candidate>[] : pages.removeAt(0);
    return FeedPage(candidates: next.take(limit).toList(), swipesLeft: serverSwipes);
  }

  @override
  Future<SwipeResult> swipe({required String candidateId, required String action, String? jobId}) async {
    swipeCalls.add((id: candidateId, action: action, jobId: jobId));
    if (swipeError != null) throw swipeError!;
    serverSwipes -= 1;
    return SwipeResult(swipesLeft: serverSwipes, contactEmail: action == 'right' ? contactEmail : '');
  }

  @override
  Future<UndoResult> undo() async {
    undoCalls++;
    if (undoError != null) throw undoError!;
    return undoResult!;
  }

  @override
  Future<bool> setWishlisted(String candidateId, bool wishlisted) async {
    wishlistCalls.add((id: candidateId, value: wishlisted));
    if (wishlistError != null) throw wishlistError!;
    return wishlisted;
  }

  // Saved searches
  Object? searchError;
  final List<({String id, bool alerts})> alertCalls = [];
  final List<String> deletedSearches = [];

  @override
  Future<SavedSearch> createSearch({required String name, required SwipeFilters filters, bool alerts = true}) async {
    if (searchError != null) throw searchError!;
    return SavedSearch(id: 'new', name: name, filters: filters, alerts: alerts);
  }

  @override
  Future<void> setSearchAlerts(String id, bool alerts) async {
    alertCalls.add((id: id, alerts: alerts));
    if (searchError != null) throw searchError!;
  }

  @override
  Future<void> deleteSearch(String id) async {
    if (searchError != null) throw searchError!;
    deletedSearches.add(id);
  }

  // Purchases
  PaymentOrder? order;
  Object? orderError;
  final List<({String orderId, String? paymentId, String? signature})> verifyCalls = [];
  Object? verifyError;
  int verifyAdded = 150;

  @override
  Future<PaymentOrder> createOrder(String planId) async {
    if (orderError != null) throw orderError!;
    return order!;
  }

  @override
  Future<VerifyResult> verifyPayment({required String orderId, String? paymentId, String? signature}) async {
    verifyCalls.add((orderId: orderId, paymentId: paymentId, signature: signature));
    if (verifyError != null) throw verifyError!;
    serverSwipes += verifyAdded;
    updateSwipes(serverSwipes);
    return VerifyResult(swipesLeft: serverSwipes, added: verifyAdded);
  }
}
