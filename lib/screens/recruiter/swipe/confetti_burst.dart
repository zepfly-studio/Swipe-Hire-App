import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// A one-shot burst of confetti (shortlist flash, onboarding done screen).
/// Ignores pointer events so it can sit on top of anything.
class ConfettiBurst extends StatefulWidget {
  final Duration duration;
  final int count;
  const ConfettiBurst({super.key, this.duration = const Duration(milliseconds: 1800), this.count = 36});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  final double spin;
  const _Particle(this.angle, this.speed, this.size, this.color, this.spin);
}

class _ConfettiBurstState extends State<ConfettiBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration)..forward();
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final rnd = math.Random(7);
    const colors = [AppColors.primary, AppColors.accent, AppColors.like, AppColors.warning, AppColors.info];
    _particles = List.generate(widget.count, (i) {
      return _Particle(
        -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.3,
        120 + rnd.nextDouble() * 260,
        4 + rnd.nextDouble() * 5,
        colors[rnd.nextInt(colors.length)],
        rnd.nextDouble() * 6,
      );
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_particles, _c.value),
        ),
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  _ConfettiPainter(this.particles, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width / 2, size.height * 0.35);
    final fade = (1 - ((t - 0.6) / 0.4)).clamp(0.0, 1.0);
    for (final p in particles) {
      final dx = math.cos(p.angle) * p.speed * t;
      final dy = math.sin(p.angle) * p.speed * t + 520 * t * t; // gravity
      final paint = Paint()..color = p.color.withValues(alpha: fade);
      canvas.save();
      canvas.translate(origin.dx + dx, origin.dy + dy);
      canvas.rotate(p.spin * t * 4);
      canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.6), paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
