import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/opportunity.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import 'candidate_application_tile.dart';

/// The candidate's "My Applications" tab: every recruiter interaction,
/// filterable by status -- the full list the Dashboard's "Recent
/// Activity" only previews.
class CandidateApplicationsScreen extends StatefulWidget {
  final AppUser user;
  const CandidateApplicationsScreen({super.key, required this.user});

  @override
  State<CandidateApplicationsScreen> createState() => _CandidateApplicationsScreenState();
}

class _CandidateApplicationsScreenState extends State<CandidateApplicationsScreen> {
  OpportunityStatus? _filter;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Opportunity>>(
      stream: OpportunityService.instance.streamForCandidate(widget.user.uid),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Opportunity>[];
        final filtered = _filter == null ? all : all.where((o) => o.status == _filter).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('My Applications', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                children: [
                  _FilterChip(label: 'All (${all.length})', selected: _filter == null, onTap: () => setState(() => _filter = null)),
                  const SizedBox(width: 8),
                  for (final status in OpportunityStatus.values) ...[
                    _FilterChip(
                      label: '${status.label} (${all.where((o) => o.status == status).length})',
                      selected: _filter == status,
                      onTap: () => setState(() => _filter = status),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: filtered.isEmpty
                  ? FadeInUp(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            all.isEmpty
                                ? 'No recruiter has reached out yet.\nOnce a company shortlists you, it will show up here.'
                                : 'Nothing in this category yet.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) => FadeInUp(
                        delay: Duration(milliseconds: 35 * index),
                        child: CandidateApplicationTile(opportunity: filtered[index]),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.accent.withValues(alpha: 0.35),
      backgroundColor: AppColors.surface,
      labelStyle: TextStyle(color: selected ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: FontWeight.w600, fontSize: 12.5),
      side: const BorderSide(color: AppColors.border),
    );
  }
}
