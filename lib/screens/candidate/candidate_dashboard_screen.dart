import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate_profile.dart';
import '../../models/opportunity.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';
import 'candidate_application_tile.dart';

/// The candidate's "Dashboard" tab: a greeting, pipeline metrics
/// (opportunities / interviews / offers), and a preview of the most
/// recent recruiter activity, with a link through to the full list on the
/// Applications tab.
class CandidateDashboardScreen extends StatelessWidget {
  final AppUser user;
  final CandidateProfile profile;
  final VoidCallback onViewAllApplications;

  const CandidateDashboardScreen({
    super.key,
    required this.user,
    required this.profile,
    required this.onViewAllApplications,
  });

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final firstName = user.name.trim().split(RegExp(r'\s+')).firstOrNull ?? user.name;

    return StreamBuilder<List<Opportunity>>(
      stream: OpportunityService.instance.streamForCandidate(user.uid),
      builder: (context, snapshot) {
        final opportunities = snapshot.data ?? const <Opportunity>[];
        final interviews = opportunities.where((o) => o.status == OpportunityStatus.interviewScheduled).length;
        final offers = opportunities
            .where((o) => o.status == OpportunityStatus.offered || o.status == OpportunityStatus.hired)
            .length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            FadeInUp(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$greeting, $firstName 👋', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text(
                    "Here's where things stand with recruiters right now.",
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FadeInUp(
              delay: const Duration(milliseconds: 60),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.7,
                children: [
                  _KpiTile(icon: Icons.business_center_rounded, value: '${opportunities.length}', label: 'Opportunities', color: AppColors.accentAlt),
                  _KpiTile(icon: Icons.event_rounded, value: '$interviews', label: 'Interviews', color: const Color(0xFFFFB84D)),
                  _KpiTile(icon: Icons.card_giftcard_rounded, value: '$offers', label: 'Offers', color: AppColors.like),
                  _KpiTile(icon: Icons.donut_large_rounded, value: '${_profileCompletion(profile)}%', label: 'Profile complete', color: AppColors.accent),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FadeInUp(
              delay: const Duration(milliseconds: 100),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Recent Activity', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  TextButton(
                    onPressed: onViewAllApplications,
                    child: const Text('View all', style: TextStyle(color: AppColors.accentAlt)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            if (opportunities.isEmpty)
              FadeInUp(
                delay: const Duration(milliseconds: 140),
                child: SectionCard(
                  title: 'Hiring Activity',
                  icon: Icons.timeline_rounded,
                  child: const Text(
                    'No recruiter has reached out yet. Once a company shortlists you, their updates -- interview schedule, offer -- will show up here.',
                    style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                  ),
                ),
              )
            else
              for (int i = 0; i < opportunities.take(3).length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: FadeInUp(
                    delay: Duration(milliseconds: 140 + 40 * i),
                    child: CandidateApplicationTile(opportunity: opportunities[i]),
                  ),
                ),
          ],
        );
      },
    );
  }

  int _profileCompletion(CandidateProfile p) {
    final fields = <bool>[
      p.age > 0,
      p.qualification.isNotEmpty,
      p.experience.isNotEmpty,
      p.desiredRole.isNotEmpty,
      p.location.isNotEmpty,
      p.skills.isNotEmpty,
      p.expectedSalaryLpa > 0,
      p.noticePeriod.isNotEmpty,
      p.about.isNotEmpty,
    ];
    final filled = fields.where((f) => f).length;
    return ((filled / fields.length) * 100).round();
  }
}

class _KpiTile extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  const _KpiTile({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
