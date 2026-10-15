import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/swipe_models.dart';
import 'package:hiring_app/screens/recruiter/plans/plan_purchase.dart';
import 'package:hiring_app/services/api_client.dart';
import 'package:hiring_app/services/hiring_service.dart';

import 'fake_hiring_service.dart';

class FakeLauncher implements CheckoutLauncher {
  FakeLauncher(this.outcome);
  final CheckoutOutcome outcome;
  CheckoutRequest? request;

  @override
  Future<CheckoutOutcome> open(CheckoutRequest r) async {
    request = r;
    return outcome;
  }
}

void main() {
  const plan = Plan(id: 'starter', name: 'Starter', price: 399, swipes: 150);
  late FakeHiringService service;

  setUp(() {
    HiringService.swipesLeft.value = 0;
    service = FakeHiringService()..serverSwipes = 0;
  });

  test('demo mode: waits, verifies with only the order id and updates the counter', () async {
    service.order = const PaymentOrder(mode: 'demo', orderId: 'order_1', amount: 39900);
    final launcher = FakeLauncher(const CheckoutOutcome.cancelled());
    final purchase = PlanPurchase(service: service, launcher: launcher, demoDelay: Duration.zero);

    final r = await purchase.buy(plan);

    expect(r.ok, isTrue);
    expect(r.added, 150);
    expect(launcher.request, isNull);
    expect(service.verifyCalls.single, (orderId: 'order_1', paymentId: null, signature: null));
    expect(HiringService.swipesLeft.value, 150);
    expect(PlanPurchase.successMessage(r.added), '150 swipes added. Happy hiring!');
  });

  test('razorpay: opens checkout with the order and verifies payment id + signature', () async {
    service.order = const PaymentOrder(
      mode: 'razorpay',
      orderId: 'order_2',
      amount: 39900,
      keyId: 'rzp_test_key',
    );
    final launcher = FakeLauncher(const CheckoutOutcome.success(paymentId: 'pay_9', signature: 'sig_9'));
    final purchase = PlanPurchase(service: service, launcher: launcher, email: 'hr@acme.com');

    final r = await purchase.buy(plan);

    expect(r.ok, isTrue);
    final req = launcher.request!;
    expect(req.keyId, 'rzp_test_key');
    expect(req.orderId, 'order_2');
    expect(req.amountPaise, 39900);
    expect(req.name, 'Swipe Hire');
    expect(req.description, 'Starter plan · 150 swipes');
    expect(req.email, 'hr@acme.com');
    expect(service.verifyCalls.single, (orderId: 'order_2', paymentId: 'pay_9', signature: 'sig_9'));
    expect(HiringService.swipesLeft.value, 150);
  });

  test('closing the checkout window does nothing', () async {
    service.order = const PaymentOrder(mode: 'razorpay', orderId: 'order_3', keyId: 'k');
    final purchase = PlanPurchase(service: service, launcher: FakeLauncher(const CheckoutOutcome.cancelled()));
    final r = await purchase.buy(plan);
    expect(r.cancelled, isTrue);
    expect(r.ok, isFalse);
    expect(r.error, isNull);
    expect(service.verifyCalls, isEmpty);
    expect(HiringService.swipesLeft.value, 0);
  });

  test('a failed payment reports the gateway message and credits nothing', () async {
    service.order = const PaymentOrder(mode: 'razorpay', orderId: 'order_4', keyId: 'k');
    final purchase = PlanPurchase(
      service: service,
      launcher: FakeLauncher(const CheckoutOutcome.failed('Card declined')),
    );
    final r = await purchase.buy(plan);
    expect(r.error, 'Card declined');
    expect(service.verifyCalls, isEmpty);
  });

  test('order errors (503) are returned as the message', () async {
    service.orderError = ApiException(503, 'Payments are not available right now');
    final r = await PlanPurchase(service: service, demoDelay: Duration.zero).buy(plan);
    expect(r.error, 'Payments are not available right now');
  });

  test('verify errors are returned as the message', () async {
    service.order = const PaymentOrder(mode: 'demo', orderId: 'order_5');
    service.verifyError = ApiException(400, 'Payment verification failed');
    final r = await PlanPurchase(service: service, demoDelay: Duration.zero).buy(plan);
    expect(r.error, 'Payment verification failed');
    expect(HiringService.swipesLeft.value, 0);
  });

  test('plans parse the server shape', () {
    final info = PlansInfo.fromMap({
      'plans': [
        {'id': 'starter', 'name': 'Starter', 'price': 399, 'swipes': 150, 'perks': ['a', 'b']},
      ],
      'freeSwipes': 5,
      'demoMode': true,
    });
    expect(info.demoMode, isTrue);
    expect(info.freeSwipes, 5);
    expect(info.plans.single.swipes, 150);
    expect(info.plans.single.perSwipeLabel, '₹2.7');
    expect(info.plans.single.displayPerks, ['a', 'b']);
  });
}
