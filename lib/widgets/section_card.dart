import 'package:flutter/material.dart';
import '../models/opportunity.dart';
import '../theme/app_theme.dart';

/// The bordered, titled card used across profile/dashboard screens for a
/// labelled block of content (About, Skills, an opportunity's details...).
class SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Color accent;

  const SectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.accent = AppColors.accentAlt,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: accent),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: accent)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Colour-coded pill for an [OpportunityStatus] -- shared by the
/// candidate's "Hiring Activity" list and the recruiter's "Pipeline" list.
class StatusBadge extends StatelessWidget {
  final OpportunityStatus status;
  const StatusBadge({super.key, required this.status});

  Color get _color => switch (status) {
        OpportunityStatus.applied => AppColors.textSecondary,
        OpportunityStatus.shortlisted => AppColors.accentAlt,
        OpportunityStatus.interviewScheduled => const Color(0xFFFFB84D),
        OpportunityStatus.offered => AppColors.like,
        OpportunityStatus.hired => AppColors.like,
        OpportunityStatus.rejected => AppColors.reject,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: _color, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}
