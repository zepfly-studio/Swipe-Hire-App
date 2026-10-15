import 'candidate.dart';
import 'hiring_job.dart';

/// One page of GET /candidates for the swipe stack.
class FeedPage {
  final List<Candidate> candidates;
  final String? nextCursor;
  final bool hasMore;

  /// Null when the server did not say.
  final int? swipesLeft;
  final HiringJob? job;

  const FeedPage({this.candidates = const [], this.nextCursor, this.hasMore = false, this.swipesLeft, this.job});
}

/// POST /company/swipe.
class SwipeResult {
  final int? swipesLeft;
  final String contactEmail;
  final String contactPhone;

  const SwipeResult({this.swipesLeft, this.contactEmail = '', this.contactPhone = ''});
}

/// POST /company/swipe/undo.
class UndoResult {
  final int? swipesLeft;

  /// The swipe that was undone: 'left' | 'right'.
  final String action;
  final String jobId;
  final Candidate? card;

  const UndoResult({this.swipesLeft, this.action = '', this.jobId = '', this.card});

  bool get wasRight => action == 'right';
}

/// A plan from GET /payment/plans.
class Plan {
  final String id;
  final String name;

  /// Rupees.
  final num price;
  final int swipes;
  final List<String> perks;

  const Plan({required this.id, required this.name, required this.price, required this.swipes, this.perks = const []});

  factory Plan.fromMap(Map<String, dynamic> m) => Plan(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        price: (m['price'] as num?) ?? 0,
        swipes: (m['swipes'] as num?)?.toInt() ?? 0,
        perks: m['perks'] is List ? (m['perks'] as List).map((e) => e.toString()).toList() : const [],
      );

  /// "₹2.7" per candidate; empty when it cannot be worked out.
  String get perSwipeLabel {
    if (swipes <= 0 || price <= 0) return '';
    return '₹${(price / swipes).toStringAsFixed(1)}';
  }

  /// Perks to show: the server's, or the spec's defaults.
  List<String> get displayPerks => perks.isNotEmpty
      ? perks
      : [
          '$swipes candidate swipes',
          'Full resume & intro video access',
          'Unlimited wishlist',
          'Contact details on shortlist',
        ];
}

class PlansInfo {
  final List<Plan> plans;
  final int freeSwipes;
  final bool demoMode;

  const PlansInfo({this.plans = const [], this.freeSwipes = 5, this.demoMode = false});

  factory PlansInfo.fromMap(Map<String, dynamic> m) => PlansInfo(
        plans: [
          if (m['plans'] is List)
            for (final p in m['plans'] as List)
              if (p is Map) Plan.fromMap(Map<String, dynamic>.from(p)),
        ],
        freeSwipes: (m['freeSwipes'] as num?)?.toInt() ?? 5,
        demoMode: m['demoMode'] == true,
      );
}

/// POST /payment/order.
class PaymentOrder {
  /// 'razorpay' | 'demo'
  final String mode;
  final String orderId;

  /// Paise.
  final int amount;
  final String currency;
  final String keyId;
  final Plan? plan;

  const PaymentOrder({
    required this.mode,
    required this.orderId,
    this.amount = 0,
    this.currency = 'INR',
    this.keyId = '',
    this.plan,
  });

  bool get isDemo => mode != 'razorpay';

  factory PaymentOrder.fromMap(Map<String, dynamic> m) => PaymentOrder(
        mode: (m['mode'] ?? 'demo').toString(),
        orderId: (m['orderId'] ?? '').toString(),
        amount: (m['amount'] as num?)?.toInt() ?? 0,
        currency: (m['currency'] ?? 'INR').toString(),
        keyId: (m['keyId'] ?? '').toString(),
        plan: m['plan'] is Map ? Plan.fromMap(Map<String, dynamic>.from(m['plan'] as Map)) : null,
      );
}

/// POST /payment/verify.
class VerifyResult {
  final int? swipesLeft;
  final int added;
  const VerifyResult({this.swipesLeft, this.added = 0});
}
