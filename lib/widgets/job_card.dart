import 'package:flutter/material.dart';
import '../models/job_posting.dart';
import '../theme/app_theme.dart';
import 'trust_widgets.dart';

/// A job posting as a card: title, company (with the verified tick), where,
/// what kind, pay, and -- for a candidate -- how well it fits them.
/// Used by Browse Jobs, Saved and a company's page.
class JobCard extends StatelessWidget {
  final JobPosting posting;
  final VoidCallback onTap;

  /// A narrower variant for horizontal carousels.
  final bool compact;
  const JobCard({super.key, required this.posting, required this.onTap, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final p = posting;
    final hasPay = p.salaryMinLpa > 0 || p.salaryMaxLpa > 0;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      p.title,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (p.matchScore != null) ...[const SizedBox(width: 8), MatchChip(score: p.matchScore!, compact: true)],
                ],
              ),
              const SizedBox(height: 3),
              CompanyName(
                name: p.companyName.isEmpty ? 'Company' : p.companyName,
                verified: p.companyVerified,
                style: const TextStyle(color: AppColors.accentAlt, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (p.location.isNotEmpty) _Meta(Icons.location_on_outlined, p.location),
                  if (p.employmentType.isNotEmpty) _Meta(Icons.schedule_outlined, p.employmentType),
                  _Meta(
                    Icons.timeline_rounded,
                    p.minExperienceYears <= 0 ? 'Freshers welcome' : '${_years(p.minExperienceYears)}+ yrs',
                  ),
                ],
              ),
              if (hasPay) ...[
                const SizedBox(height: 6),
                Text(
                  '₹${p.salaryMinLpa.toStringAsFixed(1)}-${p.salaryMaxLpa.toStringAsFixed(1)} LPA',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
              if (!compact && p.skills.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final s in p.skills.take(4)) _SkillTag(s)],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _years(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}

class _SkillTag extends StatelessWidget {
  final String label;
  const _SkillTag(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
