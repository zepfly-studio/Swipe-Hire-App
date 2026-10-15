import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../models/swipe_models.dart';
import '../../../services/api_client.dart';
import '../../../services/hiring_service.dart';
import '../../../theme/app_theme.dart';

/// What the Razorpay checkout window needs.
class CheckoutRequest {
  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;
  final String name;
  final String description;
  final String email;
  final String contact;

  const CheckoutRequest({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    this.currency = 'INR',
    this.name = 'Swipe Hire',
    this.description = '',
    this.email = '',
    this.contact = '',
  });
}

/// How a checkout window ended.
class CheckoutOutcome {
  final String? paymentId;
  final String? signature;
  final bool cancelled;
  final String? error;

  const CheckoutOutcome.success({required String this.paymentId, required String this.signature})
      : cancelled = false,
        error = null;
  const CheckoutOutcome.cancelled()
      : paymentId = null,
        signature = null,
        cancelled = true,
        error = null;
  const CheckoutOutcome.failed(String this.error)
      : paymentId = null,
        signature = null,
        cancelled = false;
}

/// Opens a real payment window. A fake in tests.
abstract class CheckoutLauncher {
  Future<CheckoutOutcome> open(CheckoutRequest request);
}

/// Razorpay's Android/iOS SDK.
class RazorpayCheckout implements CheckoutLauncher {
  @override
  Future<CheckoutOutcome> open(CheckoutRequest request) {
    final completer = Completer<CheckoutOutcome>();
    final razorpay = Razorpay();

    void finish(CheckoutOutcome outcome) {
      if (completer.isCompleted) return;
      razorpay.clear();
      completer.complete(outcome);
    }

    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      final paymentId = r.paymentId;
      final signature = r.signature;
      if (paymentId == null || signature == null) {
        finish(const CheckoutOutcome.failed('Payment failed'));
      } else {
        finish(CheckoutOutcome.success(paymentId: paymentId, signature: signature));
      }
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      // Closing the window is not a failure.
      if (r.code == Razorpay.PAYMENT_CANCELLED) {
        finish(const CheckoutOutcome.cancelled());
      } else {
        final text = (r.message ?? '').trim();
        finish(CheckoutOutcome.failed(text.isEmpty ? 'Payment failed' : text));
      }
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {});

    try {
      razorpay.open({
        'key': request.keyId,
        'order_id': request.orderId,
        'amount': request.amountPaise,
        'currency': request.currency,
        'name': request.name,
        'description': request.description,
        'prefill': {
          if (request.email.isNotEmpty) 'email': request.email,
          if (request.contact.isNotEmpty) 'contact': request.contact,
        },
        'theme': {'color': '#${(AppColors.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'},
      });
    } catch (_) {
      finish(const CheckoutOutcome.failed('Could not open payment window, check your internet'));
    }
    return completer.future;
  }
}

/// The result of [PlanPurchase.buy].
class PurchaseResult {
  final bool cancelled;
  final int added;
  final int? swipesLeft;
  final String? error;

  const PurchaseResult({this.cancelled = false, this.added = 0, this.swipesLeft, this.error});

  bool get ok => error == null && !cancelled;
}

/// Order -> (demo wait | checkout) -> verify. UI-free so it can be tested
/// with a fake service and launcher.
class PlanPurchase {
  PlanPurchase({
    required this.service,
    CheckoutLauncher? launcher,
    this.demoDelay = const Duration(milliseconds: 900),
    this.email = '',
    this.contact = '',
  }) : launcher = launcher ?? RazorpayCheckout();

  final HiringService service;
  final CheckoutLauncher launcher;
  final Duration demoDelay;
  final String email;
  final String contact;

  Future<PurchaseResult> buy(Plan plan) async {
    try {
      final order = await service.createOrder(plan.id);
      if (order.orderId.isEmpty) {
        return const PurchaseResult(error: 'Please choose a valid plan');
      }
      if (order.isDemo) {
        await Future<void>.delayed(demoDelay);
        final r = await service.verifyPayment(orderId: order.orderId);
        return PurchaseResult(added: r.added, swipesLeft: r.swipesLeft);
      }

      final outcome = await launcher.open(CheckoutRequest(
        keyId: order.keyId,
        orderId: order.orderId,
        amountPaise: order.amount,
        currency: order.currency,
        description: '${plan.name} plan · ${plan.swipes} swipes',
        email: email,
        contact: contact,
      ));
      if (outcome.cancelled) return const PurchaseResult(cancelled: true);
      if (outcome.error != null) return PurchaseResult(error: outcome.error);
      final r = await service.verifyPayment(
        orderId: order.orderId,
        paymentId: outcome.paymentId,
        signature: outcome.signature,
      );
      return PurchaseResult(added: r.added, swipesLeft: r.swipesLeft);
    } on ApiException catch (e) {
      return PurchaseResult(error: e.message);
    } catch (e) {
      debugPrint('PlanPurchase failed: $e');
      return const PurchaseResult(error: 'Payment failed');
    }
  }

  /// "150 swipes added. Happy hiring!"
  static String successMessage(int added) => '$added swipes added. Happy hiring!';
}
