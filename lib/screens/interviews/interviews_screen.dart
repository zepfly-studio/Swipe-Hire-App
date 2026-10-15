import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_user.dart';
import '../../models/pair/interview.dart';
import '../../models/pair/pair_format.dart';
import '../../services/api_client.dart';
import '../../services/interview_service.dart';
import '../../services/pair_session.dart';
import '../../services/visible_poller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/trust_widgets.dart';
import '../messages/pair_nav.dart';
import '../messages/pair_widgets.dart';

/// Interviews for BOTH roles (slot picking for candidates, schedule/cancel
/// for companies). Polled every 30 s while visible.
class InterviewsScreen extends StatefulWidget {
  /// Whether the signed-in account is a company; when null it is looked up.
  final bool? isCompany;
  const InterviewsScreen({super.key, this.isCompany});

  @override
  State<InterviewsScreen> createState() => _InterviewsScreenState();
}

class _InterviewsScreenState extends State<InterviewsScreen> {
  late final VisiblePoller _poller;
  bool? _isCompany;
  List<Interview>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _isCompany = widget.isCompany;
    _poller = VisiblePoller(interval: const Duration(seconds: 30), onTick: _load)..start();
    if (_isCompany == null) _resolveRole();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setVisible(TickerMode.valuesOf(context).enabled);
  }

  @override
  void dispose() {
    _poller.dispose();
    super.dispose();
  }

  Future<void> _resolveRole() async {
    try {
      final user = await PairSession.instance.user();
      if (!mounted) return;
      setState(() => _isCompany = user != null && user.role == UserRole.recruiter);
    } catch (_) {
      if (mounted) setState(() => _isCompany = false);
    }
  }

  Future<void> _load() async {
    try {
      final list = await InterviewService.instance.list();
      if (!mounted) return;
      setState(() {
        _items = list;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_items == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _items == null) setState(() => _error = 'Could not load your interviews.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCompany = _isCompany;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PairHeader(
                title: 'Interviews',
                subtitle: isCompany == true
                    ? 'Invite candidates from your Shortlisted page or from chat.'
                    : 'Companies that want to meet you will appear here.',
              ),
              Expanded(
                child: isCompany == null
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accentAlt))
                    : _body(isCompany),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(bool isCompany) {
    final items = _items;
    if (items == null) {
      if (_error != null) {
        return PairErrorState(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _load();
          },
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    final groups = groupInterviews(items);
    if (groups.isEmpty) {
      return PairEmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No interviews yet.',
        actionLabel: isCompany ? 'Open shortlisted' : null,
        onAction: isCompany ? () => PairNav.openShortlisted(context) : null,
      );
    }
    Widget section(String title, List<Interview> list) {
      if (list.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 14, 0, 8),
            child: Text(
              '${title.toUpperCase()} · ${list.length}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final i in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InterviewCard(key: ValueKey(i.id), interview: i, isCompany: isCompany, onChanged: _load),
            ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          section(isCompany ? 'Waiting for the candidate' : 'Needs your reply', groups.pending),
          section('Upcoming', groups.upcoming),
          section('Past & cancelled', groups.past),
        ],
      ),
    );
  }
}

class InterviewCard extends StatefulWidget {
  final Interview interview;
  final bool isCompany;
  final VoidCallback onChanged;
  const InterviewCard({super.key, required this.interview, required this.isCompany, required this.onChanged});

  @override
  State<InterviewCard> createState() => _InterviewCardState();
}

class _InterviewCardState extends State<InterviewCard> {
  bool _busy = false;
  String? _error;

  Interview get _i => widget.interview;

  Future<void> _open(Uri uri) async {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) AppToast.error('Could not open the link');
  }

  Future<void> _accept(DateTime slot) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await InterviewService.instance.accept(_i.id, slot);
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.success('Interview confirmed! Added to your interviews.');
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel interview with ${_i.person.name}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('They will be notified. You can agree on a new time in chat.'),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Reason (optional)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.reject),
            child: const Text('Cancel interview'),
          ),
        ],
      ),
    );
    final text = reason.text;
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await InterviewService.instance.cancel(_i.id, reason: text);
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.success('Interview cancelled');
      widget.onChanged();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.error('Could not cancel the interview', description: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final i = _i;
    final done = i.isDone(now);
    final statusLabel = interviewStatusLabel(i, isCompany: widget.isCompany, now: now);
    final Color tone = i.isCancelled
        ? AppColors.textSecondary
        : i.isConfirmed
            ? (done ? AppColors.textSecondary : AppColors.like)
            : AppColors.warning;
    final active = i.isActive(now);
    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: tone.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.event_rounded, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanyName(
                      name: i.person.name,
                      verified: i.person.verified,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    if (i.jobTitle.isNotEmpty)
                      Text('For ${i.jobTitle}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatePill(label: statusLabel, color: tone),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoChip(icon: _modeIcon(i.mode), label: interviewModeLabel(i.mode)),
              _InfoChip(icon: Icons.timer_outlined, label: '${i.durationMins} min'),
              if (i.location.isNotEmpty) _InfoChip(icon: Icons.place_outlined, label: i.location),
            ],
          ),
          if (i.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '“${i.note}”',
                style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5, height: 1.4),
              ),
            ),
          if (i.isConfirmed && i.chosenSlot != null) _confirmedBox(i, done),
          if (i.isProposed) _proposedBlock(now),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: InlineError(_error!)),
          if (active) _links(),
        ],
      ),
    );
  }

  IconData _modeIcon(String mode) => switch (mode) {
        'phone' => Icons.call_outlined,
        'in-person' => Icons.groups_outlined,
        _ => Icons.videocam_outlined,
      };

  Widget _confirmedBox(Interview i, bool done) {
    final slot = i.chosenSlot!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (done ? AppColors.textSecondary : AppColors.like).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (done ? AppColors.textSecondary : AppColors.like).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatPairDateTime(slot),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: done ? AppColors.textSecondary : AppColors.likeText,
            ),
          ),
          if (!done) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (i.mode == 'video' && i.meetingLink.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _open(Uri.parse(i.meetingLink)),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Join video call'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _open(interviewCalendarUri(i, title: 'Interview: ${i.person.name}')),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Add to calendar'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _proposedBlock(DateTime now) {
    final i = _i;
    if (widget.isCompany) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Times you offered',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in i.slots) _InfoChip(icon: Icons.schedule_rounded, label: formatPairDateTime(s))],
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a time that suits you',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          for (final s in i.slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: OutlinedButton(
                onPressed: (_busy || !s.isAfter(now)) ? null : () => _accept(s),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                child: Text(formatPairDateTime(s)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _links() {
    final person = _i.person;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        children: [
          TextButton.icon(
            onPressed: () => PairNav.openChat(context, person.id, isCompany: widget.isCompany),
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
            label: Text(widget.isCompany ? 'Message candidate' : 'Ask for another time'),
          ),
          TextButton.icon(
            onPressed: _busy ? null : _cancel,
            style: TextButton.styleFrom(foregroundColor: AppColors.reject),
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text('Cancel interview'),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 5),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
