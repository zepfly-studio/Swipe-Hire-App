import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

/// The six pipeline stages, in funnel order (backend `PipelineStage`).
const List<String> kPipelineStages = ['shortlisted', 'contacted', 'task', 'interview', 'hired', 'rejected'];

/// Stage label as the COMPANY sees it.
String stageLabel(String stage) => switch (stage) {
      'shortlisted' => 'Shortlisted',
      'contacted' => 'Contacted',
      'task' => 'Task sent',
      'interview' => 'Interview',
      'hired' => 'Hired',
      'rejected' => 'Rejected',
      _ => stage.isEmpty ? 'Shortlisted' : stage,
    };

/// Stage label as the CANDIDATE sees it (spec B0: hired is "Selected",
/// rejected/closed are shown as "Closed").
String candidateStageLabel(String stage) => switch (stage) {
      'shortlisted' => 'Shortlisted',
      'contacted' => 'Contacted',
      'task' => 'Task sent',
      'interview' => 'Interview',
      'hired' => 'Selected \u{1F389}',
      'rejected' || 'closed' => 'Closed',
      _ => stage.isEmpty ? 'Shortlisted' : stage,
    };

/// Pill colour per stage. Spec: grey, sky, violet, amber, green, red; the
/// app palette has no violet, so "task" uses the brand accent.
Color stageColor(String stage) => switch (stage) {
      'contacted' => AppColors.info,
      'task' => AppColors.accent,
      'interview' => AppColors.warning,
      'hired' => AppColors.like,
      'rejected' || 'closed' => AppColors.reject,
      _ => AppColors.textSecondary,
    };

/// Counts per stage plus `'all'`, for the stage tabs. An unknown stage is
/// counted as shortlisted.
Map<String, int> stageCounts(Iterable<String> stages) {
  final counts = <String, int>{'all': 0, for (final s in kPipelineStages) s: 0};
  for (final s in stages) {
    counts['all'] = counts['all']! + 1;
    final key = counts.containsKey(s) && s != 'all' ? s : 'shortlisted';
    counts[key] = counts[key]! + 1;
  }
  return counts;
}
