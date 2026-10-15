import 'package:flutter/material.dart';
import '../../../models/candidate.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/trust_widgets.dart' show MatchChip;
import '../../messages/pair_nav.dart';
import '../../messages/pair_widgets.dart';

/// One shortlisted row: checkbox, avatar, name/headline, stage pill, job,
/// match badge, chips, email and the first four skills.
class PipelineCard extends StatelessWidget {
  final Candidate candidate;
  final bool selected;
  final VoidCallback onToggleSelected;
  final VoidCallback onOpen;

  const PipelineCard({
    super.key,
    required this.candidate,
    required this.selected,
    required this.onToggleSelected,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final stage = c.stage.isEmpty ? 'shortlisted' : c.stage;
    final skills = c.skills;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 10, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? AppColors.reject : AppColors.border, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onToggleSelected(),
                    activeColor: AppColors.primary,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  PairAvatar(name: c.name, url: c.photoUrl, size: 46),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          c.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                  StagePill(stage: stage),
                  IconButton(
                    onPressed: () => PairNav.openChat(context, c.id, isCompany: true),
                    tooltip: 'Message',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20, color: AppColors.primary),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (c.jobTitle.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.work_outline_rounded, size: 14, color: AppColors.accent),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              c.jobTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (c.matchScore != null) MatchChip(score: c.matchScore!, compact: true),
                        if (c.location.isNotEmpty && c.location != '-') _Chip(icon: Icons.place_outlined, label: c.location),
                        if (c.experience.isNotEmpty && c.experience != '-')
                          _Chip(icon: Icons.work_history_outlined, label: c.experience),
                      ],
                    ),
                    if (c.contactEmail.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          c.contactEmail,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.likeText, fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                    if (skills.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final s in skills.take(4)) _Chip(label: s),
                            if (skills.length > 4) _Chip(label: '+${skills.length - 4}'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData? icon;
  final String label;
  const _Chip({this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: AppColors.textSecondary), const SizedBox(width: 4)],
          Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
