import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The blue tick next to a company whose identity has been verified.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Verified company',
      child: Icon(Icons.verified_rounded, size: size, color: AppColors.info),
    );
  }
}

/// A company name that shows the verified tick when it has earned it, and
/// shrinks with an ellipsis instead of overflowing.
class CompanyName extends StatelessWidget {
  final String name;
  final bool verified;
  final TextStyle? style;
  const CompanyName({super.key, required this.name, this.verified = false, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        if (verified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(size: (style?.fontSize ?? 14) + 2),
        ],
      ],
    );
  }
}

/// "92% match" -- green when it's a strong fit, grey when it's a stretch.
class MatchChip extends StatelessWidget {
  final int score;
  final bool compact;
  const MatchChip({super.key, required this.score, this.compact = false});

  Color get _color {
    if (score >= 75) return AppColors.like;
    if (score >= 50) return AppColors.accent;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Semantics(
      label: '$score percent match',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_graph_rounded, size: compact ? 12 : 14, color: color),
            const SizedBox(width: 4),
            Text(
              '$score% match',
              style: TextStyle(color: color, fontSize: compact ? 11 : 12, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small coloured pill, used for "Interview confirmed", "Offer accepted"
/// and similar one-word states on a tile.
class StatePill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatePill({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: color), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
