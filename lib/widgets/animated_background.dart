import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Decorative, slowly-drifting gradient blobs behind the content to give the
/// dark theme depth without distracting from the cards on top.
class AnimatedBackdrop extends StatefulWidget {
  final Widget child;
  const AnimatedBackdrop({super.key, required this.child});

  @override
  State<AnimatedBackdrop> createState() => _AnimatedBackdropState();
}

class _AnimatedBackdropState extends State<AnimatedBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(decoration: const BoxDecoration(gradient: AppColors.backgroundGradient)),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * pi;
            return CustomPaint(
              painter: _BlobPainter(t),
              size: Size.infinite,
            );
          },
        ),
        widget.child,
      ],
    );
  }
}

class _BlobPainter extends CustomPainter {
  final double t;
  _BlobPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    void blob(Offset center, double radius, Color color) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..blendMode = BlendMode.plus;
      canvas.drawCircle(center, radius, paint);
    }

    final w = size.width;
    final h = size.height;

    blob(
      Offset(w * 0.2 + sin(t) * 30, h * 0.15 + cos(t) * 20),
      w * 0.55,
      AppColors.accent,
    );
    blob(
      Offset(w * 0.85 + cos(t * 0.8) * 24, h * 0.35 + sin(t * 0.8) * 30),
      w * 0.5,
      AppColors.accentAlt,
    );
    blob(
      Offset(w * 0.4 + sin(t * 0.6) * 26, h * 0.9 + cos(t * 0.6) * 20),
      w * 0.6,
      AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(covariant _BlobPainter oldDelegate) => oldDelegate.t != t;
}
