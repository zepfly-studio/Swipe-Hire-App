import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The page backdrop: a flat off-white surface (the theme's background
/// colour). It used to paint drifting colour blobs; the professional look
/// wants a calm, solid background, so nothing is drawn or animated here.
/// Kept as a widget so every screen keeps the same wrapper.
class AnimatedBackdrop extends StatelessWidget {
  final Widget child;
  const AnimatedBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: AppColors.bgTop),
        child,
      ],
    );
  }
}
