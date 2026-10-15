import 'package:flutter/material.dart';

import '../../../models/swipe_models.dart';
import '../../../services/auth_service.dart';
import '../../../services/hiring_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import 'plan_purchase.dart';

/// The free card plus the paid plan(s), with the buy flow (spec C6).
/// Used on the Plans screen and inside the paywall.
class PlanCards extends StatefulWidget {
  /// Called after swipes were added (the paywall closes itself here).
  final VoidCallback? onPurchased;
  final HiringService? service;
  final CheckoutLauncher? launcher;

  const PlanCards({super.key, this.onPurchased, this.service, this.launcher});

  @override
  State<PlanCards> createState() => _PlanCardsState();
}

class _PlanCardsState extends State<PlanCards> {
  PlansInfo? _info;
  bool _loading = true;
  String? _buying;

  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final info = await _service.fetchPlans();
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error('Could not load plans');
    }
  }

  Future<void> _buy(Plan plan) async {
    if (_buying != null) return;
    setState(() => _buying = plan.id);
    final user = AuthService.instance.currentUser;
    final purchase = PlanPurchase(
      service: _service,
      launcher: widget.launcher,
      email: user?.email ?? '',
    );
    final result = await purchase.buy(plan);
    if (!mounted) return;
    setState(() => _buying = null);
    if (result.cancelled) return;
    if (!result.ok) {
      AppToast.error(result.error ?? 'Payment failed');
      return;
    }
    AppToast.success(PlanPurchase.successMessage(result.added > 0 ? result.added : plan.swipes));
    widget.onPurchased?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final info = _info;
    if (info == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FreeCard(freeSwipes: info.freeSwipes),
        for (final plan in info.plans) ...[
          const SizedBox(height: 14),
          _PaidCard(plan: plan, busy: _buying == plan.id, disabled: _buying != null, onBuy: () => _buy(plan)),
        ],
        if (info.demoMode)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'Demo mode: Razorpay keys are not set, so purchases are simulated (no real money is charged).',
              style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.35),
            ),
          ),
      ],
    );
  }
}

class _Perk extends StatelessWidget {
  final String text;
  const _Perk(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.like),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.3))),
        ],
      ),
    );
  }
}

class _FreeCard extends StatelessWidget {
  final int freeSwipes;
  const _FreeCard({required this.freeSwipes});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Free', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              Spacer(),
              Text('₹0', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$freeSwipes swipes to try Swipe Hire',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
          ),
          const _Perk('Given on sign-up'),
          const _Perk('Resume & video access'),
        ],
      ),
    );
  }
}

class _PaidCard extends StatelessWidget {
  final Plan plan;
  final bool busy;
  final bool disabled;
  final VoidCallback onBuy;

  const _PaidCard({required this.plan, required this.busy, required this.disabled, required this.onBuy});

  @override
  Widget build(BuildContext context) {
    final per = plan.perSwipeLabel;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        gradient: AppColors.accentGradient,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(plan.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Most popular',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${plan.price}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 26)),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('one-time', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
              ],
            ),
            Text(
              '${plan.swipes} swipes${per.isEmpty ? '' : ' · $per per candidate'}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
            ),
            for (final p in plan.displayPerks) _Perk(p),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: disabled ? null : onBuy,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onPrimary),
                    )
                  : Text('Buy ${plan.swipes} swipes'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the paywall as a bottom sheet ("You've used all your swipes").
/// Resolves when it closes; a purchase closes it automatically.
Future<void> showPaywall(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgTop,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  "You've used all your swipes",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const Text(
            'Pick a plan to keep swiping. Your wishlist and shortlist stay safe.',
            style: TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          PlanCards(onPurchased: () => Navigator.of(sheetContext).pop()),
        ],
      ),
    ),
  );
}
