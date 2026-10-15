import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/pair/hiring_task.dart';
import '../../models/pair/pair_format.dart';
import '../../services/api_client.dart';
import '../../services/hiring_task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/inputs/form_blocks.dart';
import '../../widgets/trust_widgets.dart';
import '../messages/pair_inputs.dart';
import '../messages/pair_nav.dart';
import '../messages/pair_widgets.dart';

Color taskStatusColor(String effectiveStatus) => switch (effectiveStatus) {
      'submitted' => AppColors.taskSubmitted,
      'overdue' => AppColors.taskOverdue,
      'cancelled' => AppColors.taskCancelled,
      _ => AppColors.taskWaiting,
    };

/// A task, for both roles. [compact] drops the person header (used inside
/// the shortlisted candidate sheet).
class TaskCard extends StatefulWidget {
  final HiringTask task;
  final bool isCompany;
  final bool compact;

  /// Called after a successful write so the parent can refetch.
  final VoidCallback onChanged;

  const TaskCard({super.key, required this.task, required this.isCompany, required this.onChanged, this.compact = false});

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  late bool _detailsOpen;
  bool _editingDeadline = false;
  DateTime? _newDeadline;
  String? _deadlineError;
  bool _busy = false;

  final _live = TextEditingController();
  final _repo = TextEditingController();
  final _note = TextEditingController();
  SubmissionCheck? _check;
  String? _submitError;

  HiringTask get _t => widget.task;

  @override
  void initState() {
    super.initState();
    _detailsOpen = !widget.isCompany && !widget.compact && _t.status == 'assigned';
    _prefill();
  }

  @override
  void didUpdateWidget(covariant TaskCard old) {
    super.didUpdateWidget(old);
    if (old.task.id != widget.task.id ||
        (old.task.submission?.at != widget.task.submission?.at && !_busy && _live.text.isEmpty && _repo.text.isEmpty)) {
      _prefill();
    }
  }

  void _prefill() {
    final s = _t.submission;
    if (s != null) {
      _live.text = s.liveUrl;
      _repo.text = s.repoUrl;
      _note.text = s.note;
    }
  }

  @override
  void dispose() {
    _live.dispose();
    _repo.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) AppToast.error('Could not open the link');
  }

  Future<void> _submit() async {
    final check = validateSubmission(live: _live.text, repo: _repo.text);
    setState(() {
      _check = check;
      _submitError = null;
    });
    if (!check.isValid) return;
    setState(() => _busy = true);
    final updating = _t.submission != null;
    try {
      // The server replaces the whole submission, so always send both links.
      await HiringTaskService.instance.submit(
        _t.id,
        liveUrl: check.liveUrl,
        repoUrl: check.repoUrl,
        note: _note.text,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.success(updating ? 'Submission updated' : 'Task submitted! The company has been notified.');
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitError = e.message;
      });
    }
  }

  Future<void> _saveDeadline() async {
    final problem = validateTaskDeadline(_newDeadline);
    if (problem != null) {
      setState(() => _deadlineError = problem);
      return;
    }
    setState(() {
      _busy = true;
      _deadlineError = null;
    });
    try {
      await HiringTaskService.instance.changeDeadline(_t.id, _newDeadline!);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _editingDeadline = false;
      });
      AppToast.success('Deadline updated');
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _deadlineError = e.message;
      });
    }
  }

  Future<void> _cancelTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel task?'),
        content: Text('Cancel "${_t.title}"? The candidate will be told they don\'t need to submit it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.reject),
            child: const Text('Cancel task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await HiringTaskService.instance.cancel(_t.id);
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.success('Task cancelled');
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error('Could not cancel the task', description: e.message);
    }
  }

  Future<void> _pickDeadline() async {
    final picked = await pickPairDateTime(
      context,
      initial: _newDeadline ?? DateTime.now().add(const Duration(days: 2)),
      last: DateTime.now().add(const Duration(days: 31)),
    );
    if (picked != null && mounted) setState(() => _newDeadline = picked);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final status = _t.effectiveStatus(now);
    final color = taskStatusColor(status);
    final due = _t.dueAt;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.compact) ...[_header(), const SizedBox(height: 12)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: Icon(Icons.assignment_outlined, size: 18, color: AppColors.primary),
              ),
              Expanded(
                child: Text(_t.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3)),
              ),
              const SizedBox(width: 8),
              StatePill(label: taskStatusLabel(status), color: color),
            ],
          ),
          if (due != null) ...[const SizedBox(height: 8), _dueLine(due, status, now)],
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _detailsOpen = !_detailsOpen),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 32)),
              child: Text(_detailsOpen ? 'Hide details' : 'Show task details'),
            ),
          ),
          if (_detailsOpen) ...[
            if (_t.description.isNotEmpty)
              Text(_t.description, style: const TextStyle(fontSize: 13.5, height: 1.45)),
            if (_t.briefUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _LinkRow(label: 'Reference', url: _t.briefUrl, onTap: () => _open(_t.briefUrl)),
              ),
            const SizedBox(height: 6),
          ],
          if (_t.submission != null) _submissionBlock(_t.submission!),
          if (!widget.isCompany) _candidateArea(status, now),
          if (widget.isCompany && !_t.isCancelled) _companyActions(),
        ],
      ),
    );
  }

  Widget _header() {
    final p = _t.person;
    return Row(
      children: [
        PairAvatar(name: p.name, url: p.avatarUrl, size: 40, square: !widget.isCompany),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompanyName(name: p.name, verified: p.verified, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              if (_t.jobTitle.isNotEmpty)
                Text(
                  'For ${_t.jobTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => PairNav.openChat(context, p.id, isCompany: widget.isCompany),
          tooltip: 'Message',
          icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _dueLine(DateTime due, String status, DateTime now) {
    final showLeft = status == 'assigned';
    final urgent = showLeft && isTimeLeftUrgent(due, now: now);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Due ${formatPairDateTime(due)}'),
          if (showLeft)
            TextSpan(
              text: ' · ${timeLeftLabel(due, now: now)}',
              style: TextStyle(
                fontWeight: urgent ? FontWeight.w800 : FontWeight.w600,
                color: urgent ? AppColors.reject : AppColors.textPrimary,
              ),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
    );
  }

  Widget _submissionBlock(TaskSubmission s) {
    final when = s.at == null ? '' : ' · ${formatPairDateTime(s.at!)}';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.like.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.like.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.isCompany ? 'SUBMISSION' : 'YOUR SUBMISSION'}$when',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.likeText),
          ),
          if (s.liveUrl.isNotEmpty) _LinkRow(label: 'Live', url: s.liveUrl, onTap: () => _open(s.liveUrl)),
          if (s.repoUrl.isNotEmpty) _LinkRow(label: 'GitHub', url: s.repoUrl, onTap: () => _open(s.repoUrl)),
          if (s.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(s.note, style: const TextStyle(fontSize: 13, height: 1.35)),
            ),
        ],
      ),
    );
  }

  Widget _candidateArea(String status, DateTime now) {
    if (_t.isCancelled) return const SizedBox.shrink();
    if (_t.canSubmit(now)) {
      final check = _check;
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormFieldBlock(
              label: 'Live link',
              error: check?.liveError,
              child: TextField(
                controller: _live,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: fieldDecoration(hintText: 'my-app.vercel.app', hasError: check?.liveError != null),
              ),
            ),
            const SizedBox(height: 12),
            FormFieldBlock(
              label: 'GitHub repo',
              error: check?.repoError,
              child: TextField(
                controller: _repo,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: fieldDecoration(hintText: 'github.com/you/project', hasError: check?.repoError != null),
              ),
            ),
            const SizedBox(height: 12),
            FormFieldBlock(
              label: 'Note for the company',
              hint: 'Optional',
              child: TextField(
                controller: _note,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: fieldDecoration(hintText: 'Login: demo@test.com / demo123'),
              ),
            ),
            if (check?.formError != null) Padding(padding: const EdgeInsets.only(top: 4), child: InlineError(check!.formError!)),
            if (_submitError != null) Padding(padding: const EdgeInsets.only(top: 4), child: InlineError(_submitError!)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _submit,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                  : Text(_t.submission != null ? 'Update submission' : 'Submit task'),
            ),
          ],
        ),
      );
    }
    if (status == 'overdue') {
      return const Padding(
        padding: EdgeInsets.only(top: 10),
        child: Text(
          'The deadline has passed. Message the company if you need more time.',
          style: TextStyle(color: AppColors.reject, fontSize: 12.5, height: 1.35),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _companyActions() {
    if (_editingDeadline) {
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DateTimeField(value: _newDeadline, onTap: _pickDeadline, hasError: _deadlineError != null),
            if (_deadlineError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_deadlineError!, style: const TextStyle(color: AppColors.reject, fontSize: 12)),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _saveDeadline,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => setState(() => _editingDeadline = false),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: _busy
                ? null
                : () {
                    final base = _t.dueAt != null && _t.dueAt!.isAfter(DateTime.now()) ? _t.dueAt! : DateTime.now();
                    setState(() {
                      _editingDeadline = true;
                      _deadlineError = null;
                      _newDeadline = base.add(const Duration(days: 2));
                    });
                  },
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text('Change deadline'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _cancelTask,
            style: TextButton.styleFrom(foregroundColor: AppColors.reject),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel task'),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final String label;
  final String url;
  final VoidCallback onTap;
  const _LinkRow({required this.label, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Text(
                url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.info,
                  decoration: TextDecoration.underline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded, size: 14, color: AppColors.info),
          ],
        ),
      ),
    );
  }
}
