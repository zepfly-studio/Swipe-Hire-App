import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../models/candidate.dart';
import '../../../models/pair/hiring_task.dart';
import '../../../services/hiring_task_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/trust_widgets.dart' show MatchChip;
import '../../messages/pair_widgets.dart';
import '../../resume_screen.dart';
import '../../tasks/task_card.dart';
import '../../video_intro_screen.dart';
import 'pipeline_controls.dart';

/// Opens the candidate modal (pipeline mode) for a shortlisted row.
Future<void> showCandidateSheet(
  BuildContext context,
  Candidate candidate, {
  required void Function(String swipeId, String personId, String stage) onStageChanged,
  required void Function(String swipeId, String notes) onNotesChanged,
  void Function(String swipeId, String personId)? onRemoved,
}) {
  return showPairSheet<void>(
    context,
    (_) => CandidateSheet(
      candidate: candidate,
      onStageChanged: onStageChanged,
      onNotesChanged: onNotesChanged,
      onRemoved: onRemoved,
    ),
    full: true,
  );
}

class CandidateSheet extends StatefulWidget {
  final Candidate candidate;
  final void Function(String swipeId, String personId, String stage) onStageChanged;
  final void Function(String swipeId, String notes) onNotesChanged;

  /// Called after the candidate was taken out of the shortlist; the sheet
  /// then closes itself.
  final void Function(String swipeId, String personId)? onRemoved;

  const CandidateSheet({
    super.key,
    required this.candidate,
    required this.onStageChanged,
    required this.onNotesChanged,
    this.onRemoved,
  });

  @override
  State<CandidateSheet> createState() => _CandidateSheetState();
}

class _CandidateSheetState extends State<CandidateSheet> {
  late String _stage;
  List<HiringTask>? _tasks;

  Candidate get _c => widget.candidate;

  @override
  void initState() {
    super.initState();
    _stage = _c.stage.isEmpty ? 'shortlisted' : _c.stage;
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final list = await HiringTaskService.instance.list(candidateId: _c.id);
      if (!mounted) return;
      setState(() => _tasks = list.where((t) => !t.isCancelled).toList());
    } catch (_) {
      if (mounted) setState(() => _tasks ??= const []);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    AppToast.success('Copied');
  }

  Future<void> _launch(Uri uri) async {
    final ok = await launchUrl(uri);
    if (!ok && mounted) AppToast.error('Could not open that');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return PairSheetFrame(
      title: c.name,
      subtitle: [c.role, c.currentCompany].where((s) => s.isNotEmpty && s != '-').join(' · '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StagePill(stage: _stage),
              if (c.jobTitle.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.work_outline_rounded, size: 15, color: AppColors.accent),
                    const SizedBox(width: 4),
                    Text(c.jobTitle, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              if (c.matchScore != null) MatchChip(score: c.matchScore!, compact: true),
            ],
          ),
          const SizedBox(height: 14),
          if (c.contactEmail.isNotEmpty)
            _ContactRow(
              icon: Icons.mail_outline_rounded,
              value: c.contactEmail,
              onOpen: () => _launch(Uri(scheme: 'mailto', path: c.contactEmail)),
              onCopy: () => _copy(c.contactEmail),
            ),
          if (c.contactPhone.isNotEmpty)
            _ContactRow(
              icon: Icons.call_outlined,
              value: c.contactPhone,
              onOpen: () => _launch(Uri(scheme: 'tel', path: c.contactPhone)),
              onCopy: () => _copy(c.contactPhone),
            ),
          const SizedBox(height: 6),
          PipelineControls(
            candidate: c,
            onStageChanged: (s) {
              if (mounted) setState(() => _stage = s);
              widget.onStageChanged(c.swipeId, c.id, s);
            },
            onNotesChanged: (n) => widget.onNotesChanged(c.swipeId, n),
            onTaskSent: _loadTasks,
            onInterviewSent: () {},
            onRemoved: widget.onRemoved == null
                ? null
                : () {
                    widget.onRemoved!(c.swipeId, c.id);
                    if (mounted) Navigator.of(context).maybePop();
                  },
          ),
          if (_tasks != null && _tasks!.isNotEmpty) ...[
            const SizedBox(height: 18),
            const Text('Tasks', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            const SizedBox(height: 8),
            for (final t in _tasks!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TaskCard(key: ValueKey(t.id), task: t, isCompany: true, compact: true, onChanged: _loadTasks),
              ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ResumeScreen(candidate: c))),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('View resume'),
          ),
          if (c.introVideoUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoIntroScreen(candidate: c))),
              icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
              label: const Text('Watch intro video'),
            ),
          ],
          const SizedBox(height: 18),
          _Details(candidate: c),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String value;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  const _ContactRow({required this.icon, required this.value, required this.onOpen, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.like.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.like.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onOpen,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: AppColors.likeText),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        value,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.likeText),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(onPressed: onCopy, tooltip: 'Copy', icon: const Icon(Icons.copy_rounded, size: 18)),
        ],
      ),
    );
  }
}

/// Skills, detail rows and about (the CandidateDetails block).
class _Details extends StatelessWidget {
  final Candidate candidate;
  const _Details({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final rows = <(String, String)>[
      ('Experience', c.experience),
      ('Current company', c.currentCompany),
      if (c.currentPost.isNotEmpty) ('Current post', c.currentPost),
      ('Expected CTC', c.expectedSalaryLpa > 0 ? '₹${c.expectedSalaryLpa.toStringAsFixed(1)} LPA' : ''),
      if (c.currentSalaryLpa > 0) ('Current CTC', '₹${c.currentSalaryLpa.toStringAsFixed(1)} LPA'),
      ('Notice period', c.noticePeriod),
      ('Location', c.location),
      ('Qualification', c.degree.isNotEmpty ? [c.degree, c.college].where((s) => s.isNotEmpty).join(', ') : c.qualification),
      if (c.workModes.isNotEmpty) ('Work mode', c.workModes.join(', ')),
      if (c.preferredLocations.isNotEmpty) ('Preferred locations', c.preferredLocations.join(', ')),
    ].where((r) => r.$2.isNotEmpty && r.$2 != '-').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.skills.isNotEmpty) ...[
          const Text('Skills', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final s in c.skills)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.matchedSkills.contains(s) ? AppColors.like.withValues(alpha: 0.12) : AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(s, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 130,
                  child: Text(r.$1, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ),
                Expanded(child: Text(r.$2, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5))),
              ],
            ),
          ),
        if (c.about.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('About', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          Text(c.about, style: const TextStyle(fontSize: 13.5, height: 1.45)),
        ],
      ],
    );
  }
}
