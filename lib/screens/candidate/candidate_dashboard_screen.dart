import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate_profile.dart';
import '../../models/opportunity.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/notification_bell.dart';
import '../../widgets/section_card.dart';
import 'candidate_application_tile.dart';
import 'task_submit_screen.dart';

/// The candidate's "Dashboard" tab: a greeting, pipeline metrics
/// (opportunities / tasks to do / interviews / offers), the tasks that
/// still need handing in, and a preview of the most recent recruiter
/// activity, with a link through to the full list on the Applications tab.
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

        // Every task still waiting on this candidate, across all their
        // applications, soonest deadline first (no deadline last).
        final pendingTasks = <_PendingTask>[
          for (final o in opportunities.where((o) => !o.status.isClosed))
            for (final t in o.pendingTasks) _PendingTask(o, t),
        ]..sort((a, b) {
            final da = a.task.dueDate;
            final db = b.task.dueDate;
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        final awaitingReview = opportunities.fold<int>(0, (sum, o) => sum + o.tasksToReview.length);
        final overdue = pendingTasks.where((p) => p.task.isOverdue).length;

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            FadeInUp(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
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
                  const NotificationBell(),
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
                childAspectRatio: 2.0,
                children: [
                  _KpiTile(icon: Icons.business_center_rounded, value: '${opportunities.length}', label: 'Opportunities', color: AppColors.accentAlt),
                  _KpiTile(
                    icon: Icons.assignment_late_outlined,
                    value: '${pendingTasks.length}',
                    label: overdue > 0 ? 'Tasks to do ($overdue overdue)' : 'Tasks to do',
                    color: overdue > 0 ? AppColors.reject : AppColors.info,
                  ),
                  _KpiTile(icon: Icons.hourglass_top_rounded, value: '$awaitingReview', label: 'Awaiting review', color: AppColors.accent),
                  _KpiTile(icon: Icons.event_rounded, value: '$interviews', label: 'Interviews', color: AppColors.warning),
                  _KpiTile(icon: Icons.card_giftcard_rounded, value: '$offers', label: 'Offers', color: AppColors.like),
                  _KpiTile(icon: Icons.donut_large_rounded, value: '${_profileCompletion(profile)}%', label: 'Profile complete', color: AppColors.accent),
                ],
              ),
            ),
            if (pendingTasks.isNotEmpty) ...[
              const SizedBox(height: 20),
              FadeInUp(
                delay: const Duration(milliseconds: 80),
                child: _PendingTasksCard(tasks: pendingTasks),
              ),
            ],
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

/// A task together with the application it belongs to.
class _PendingTask {
  final Opportunity opportunity;
  final OpportunityTask task;
  const _PendingTask(this.opportunity, this.task);
}

/// The to-do list on the dashboard: every task still waiting on the
/// candidate, soonest deadline first, each one a tap away from the form.
class _PendingTasksCard extends StatelessWidget {
  final List<_PendingTask> tasks;
  const _PendingTasksCard({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Tasks to do',
      icon: Icons.assignment_late_outlined,
      child: Column(
        children: [
          for (final p in tasks.take(3))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => TaskSubmitScreen(opportunity: p.opportunity, taskId: p.task.id)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14), overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(
                            '${p.opportunity.companyName} · '
                            '${p.task.dueDate == null ? 'No deadline' : dueLabel(p.task.dueDate!)}'
                            '${p.task.hasChangeRequest ? ' · changes requested' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: p.task.isOverdue ? AppColors.reject : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
            ),
          if (tasks.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('+${tasks.length - 3} more in Applications',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ),
            ),
        ],
      ),
    );
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
        boxShadow: AppColors.cardShadow(),
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
