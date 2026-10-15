import 'package:flutter/material.dart';

import '../../../services/hiring_service.dart';
import '../../../theme/app_theme.dart';
import 'plan_cards.dart';

/// "Swipe more, hire faster." -- free card + the paid plan (spec C6).
class PlansScreen extends StatelessWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(title: const Text('Plans & swipes')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text(
              'Swipe more, hire faster.',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Every swipe (left or right) uses one credit. Saving candidates to your wishlist is always free.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: ValueListenableBuilder<int>(
                valueListenable: HiringService.swipesLeft,
                builder: (context, n, _) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: (n == 0 ? AppColors.reject : AppColors.primary).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 18, color: n == 0 ? AppColors.reject : AppColors.primary),
                      const SizedBox(width: 6),
                      Text.rich(
                        TextSpan(
                          text: 'You have ',
                          children: [
                            TextSpan(
                              text: n < 0 ? '–' : '$n',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const TextSpan(text: ' swipes left'),
                          ],
                        ),
                        style: const TextStyle(fontSize: 13.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const PlanCards(),
          ],
        ),
      ),
    );
  }
}
