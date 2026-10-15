import 'package:flutter/material.dart';

import '../../../models/hiring_job.dart';
import '../../../services/api_client.dart';
import '../../../services/hiring_service.dart';
import '../../../services/polling.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_nav.dart';
import '../../../widgets/app_toast.dart';
import 'job_form_sheet.dart';

/// The company's jobs (spec C5): Hiring / Paused / Closed, funnel stats and
/// actions. "Swipe" and "Shortlisted" switch the shell's tab.
class JobsScreen extends StatefulWidget {
  final HiringService? service;
  const JobsScreen({super.key, this.service});

  @override
  State<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends State<JobsScreen> {
  List<HiringJob> _jobs = [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    _load();
    DataRefresh.instance.addListener(_onData);
  }

  @override
  void dispose() {
    DataRefresh.instance.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    if (mounted && !_loading) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final jobs = await _service.fetchJobs();
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = e.message;
      });
    }
  }

  Future<void> _post() async {
    final defaultLocation = HiringService.company.value?.location ?? '';
    await showJobFormSheet(context, defaultLocation: defaultLocation, service: _service);
  }

  Future<void> _edit(HiringJob job) => showJobFormSheet(context, job: job, service: _service);

  Future<void> _setStatus(HiringJob job, String status) async {
    if (_busy.contains(job.id)) return;
    setState(() => _busy.add(job.id));
    try {
      await _service.setJobStatus(job.id, status);
      AppToast.success(switch (status) {
        'paused' => 'Job paused',
        'closed' => 'Job closed',
        _ => 'Job reopened',
      });
      await _load(silent: true);
    } on ApiException catch (e) {
      AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(job.id));
    }
  }

  Future<void> _swipe(HiringJob job) async {
    final companyId = HiringService.company.value?.id ?? '';
    if (companyId.isNotEmpty) await _service.rememberJob(companyId, job.id);
    HiringService.swipeJobRequest.value = job.id;
    AppNav.recruiterTab.value = AppNav.recruiterSwipe;
  }

  void _shortlisted(HiringJob job) {
    HiringService.pendingShortlistedJobId.value = job.id;
    AppNav.recruiterTab.value = AppNav.recruiterShortlisted;
  }

  @override
  Widget build(BuildContext context) {
    final hiring = _jobs.where((j) => j.isOpen).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Jobs', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    Text(
                      _loading ? 'Every job has its own swipe feed and pipeline.' : '$hiring hiring now',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _post,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Post a job'),
              ),
            ],
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    if (_jobs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'No jobs yet. Post your first one!',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(silent: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _jobs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final job = _jobs[i];
          return JobCard(
            job: job,
            busy: _busy.contains(job.id),
            onSwipe: () => _swipe(job),
            onShortlisted: () => _shortlisted(job),
            onEdit: () => _edit(job),
            onPause: () => _setStatus(job, 'paused'),
            onReopen: () => _setStatus(job, 'open'),
            onClose: () => _setStatus(job, 'closed'),
          );
        },
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  final HiringJob job;
  final bool busy;
  final VoidCallback onSwipe;
  final VoidCallback onShortlisted;
  final VoidCallback onEdit;
  final VoidCallback onPause;
  final VoidCallback onReopen;
  final VoidCallback onClose;

  const JobCard({
    super.key,
    required this.job,
    required this.busy,
    required this.onSwipe,
    required this.onShortlisted,
    required this.onEdit,
    required this.onPause,
    required this.onReopen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final (pillLabel, pillColor) = switch (job.status) {
      'paused' => ('Paused', AppColors.warning),
      'closed' => ('Closed', AppColors.textSecondary),
      _ => ('Hiring', AppColors.like),
    };
    final meta = [
      if (job.location.trim().isNotEmpty) '📍 ${job.location}',
      job.workModeLabel,
      job.employmentTypeLabel,
    ].join(' · ');
    final facts = [
      if (job.salaryLabel.isNotEmpty) job.salaryLabel,
      job.experienceLabel,
      if (job.openings > 1) '${job.openings} openings',
    ].join(' · ');
    return Opacity(
      opacity: job.isClosed ? 0.65 : 1,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: AppColors.accentGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.work_outline_rounded, color: AppColors.onPrimary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        job.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (meta.isNotEmpty)
                        Text(meta, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: pillColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    pillLabel,
                    style: TextStyle(color: pillColor, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(facts, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            if (job.skills.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in job.skills.take(6))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(s, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _Stat('Seen', job.stats.swiped),
                _Stat('Shortlist', job.stats.shortlisted),
                _Stat('Interview', job.stats.interviewing),
                _Stat('Hired', job.stats.hired),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (job.isOpen)
                  FilledButton(
                    onPressed: onSwipe,
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 14)),
                    child: const Text('Swipe'),
                  ),
                if (job.isOpen) const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onShortlisted,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('Shortlisted'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: onEdit,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text('Edit'),
                ),
                const Spacer(),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.all(10),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else ...[
                  if (job.isOpen)
                    IconButton(
                      tooltip: 'Pause',
                      onPressed: onPause,
                      icon: const Icon(Icons.pause_circle_outline_rounded, color: AppColors.warning),
                    ),
                  if (!job.isOpen)
                    IconButton(
                      tooltip: 'Reopen',
                      onPressed: onReopen,
                      icon: const Icon(Icons.play_circle_outline_rounded, color: AppColors.like),
                    ),
                  if (!job.isClosed)
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onClose,
                      icon: const Icon(Icons.cancel_outlined, color: AppColors.reject),
                    ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final int value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text('$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
