import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/opportunity.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/section_card.dart';
import '../../widgets/trust_widgets.dart';
import '../chat_screen.dart';
import 'task_submit_screen.dart';

/// One recruiter interaction, shown as a status-colour-coded card --
/// reused by the Dashboard's "Recent Activity" preview and the full
/// Applications list. Besides showing where things stand, it is where a
/// candidate answers: do a task, confirm or move the interview, accept or
/// decline an offer, or withdraw.
class CandidateApplicationTile extends StatefulWidget {
  final Opportunity opportunity;
  const CandidateApplicationTile({super.key, required this.opportunity});

  @override
  State<CandidateApplicationTile> createState() => _CandidateApplicationTileState();
}

class _CandidateApplicationTileState extends State<CandidateApplicationTile> {
  bool _busy = false;

  Opportunity get _o => widget.opportunity;

  Color get _statusColor => switch (_o.status) {
        OpportunityStatus.applied => AppColors.textSecondary,
        OpportunityStatus.shortlisted => AppColors.info,
        OpportunityStatus.taskAssigned => AppColors.accent,
        OpportunityStatus.taskSubmitted => AppColors.accentAlt,
        OpportunityStatus.interviewScheduled => AppColors.warning,
        OpportunityStatus.offered => AppColors.like,
        OpportunityStatus.hired => AppColors.like,
        OpportunityStatus.rejected => AppColors.reject,
        OpportunityStatus.withdrawn => AppColors.textSecondary,
      };

  /// Runs one answer against the backend with a busy state and the same
  /// error handling for all of them.
  Future<void> _run(Future<void> Function() action, {required String failure}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) AppToast.error(failure, description: e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'ApplicationTile: $failure');
      if (mounted) AppToast.error(failure, description: 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmInterview() => _run(() async {
        await OpportunityService.instance.respondToInterview(_o.id, confirm: true);
        AppToast.success('Interview confirmed', description: '${_o.companyName} knows you will be there.');
      }, failure: 'Could not confirm the interview');

  Future<void> _askToReschedule() async {
    final note = await _promptText(
      title: 'Ask for another time',
      hint: 'Which time would suit you? e.g. Friday after 5 pm',
      confirmLabel: 'Send request',
      required: true,
    );
    if (note == null || !mounted) return;
    await _run(() async {
      await OpportunityService.instance.respondToInterview(_o.id, confirm: false, note: note);
      AppToast.info('Request sent', description: '${_o.companyName} will pick a new time.');
    }, failure: 'Could not send your request');
  }

  Future<void> _acceptOffer() => _run(() async {
        await OpportunityService.instance.respondToOffer(_o.id, accept: true);
        AppToast.success('Offer accepted', description: '${_o.companyName} has been told. Congratulations!');
      }, failure: 'Could not accept the offer');

  Future<void> _declineOffer() async {
    final sure = await _confirm(
      title: 'Decline this offer?',
      message: 'This closes your application with ${_o.companyName}. They will be told.',
      confirmLabel: 'Decline offer',
    );
    if (!sure || !mounted) return;
    await _run(() async {
      await OpportunityService.instance.respondToOffer(_o.id, accept: false);
      AppToast.info('Offer declined', description: 'Your application was closed.');
    }, failure: 'Could not decline the offer');
  }

  Future<void> _withdraw() async {
    final reason = await _promptText(
      title: 'Withdraw your application?',
      hint: 'Reason (optional)',
      confirmLabel: 'Withdraw',
      required: false,
      message: 'This closes your application with ${_o.companyName}. They will be told.',
    );
    if (reason == null || !mounted) return;
    await _run(() async {
      await OpportunityService.instance.withdraw(_o.id, reason: reason);
      AppToast.info('Application withdrawn');
    }, failure: 'Could not withdraw');
  }

  Future<bool> _confirm({required String title, required String message, required String confirmLabel}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.reject),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Returns the text typed, or null if cancelled.
  Future<String?> _promptText({
    required String title,
    required String hint,
    required String confirmLabel,
    required bool required,
    String? message,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message != null) ...[Text(message), const SizedBox(height: 12)],
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 3,
                  minLines: 1,
                  decoration: InputDecoration(hintText: hint, errorText: error),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  final text = controller.text.trim();
                  if (required && text.length < 3) {
                    setLocal(() => error = 'Please add a few words');
                    return;
                  }
                  Navigator.of(context).pop(text);
                },
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _addToCalendar() async {
    final when = _o.interviewDate;
    if (when == null) return;
    final uri = googleCalendarUri(
      title: 'Interview: ${_o.role.isEmpty ? 'role' : _o.role} at ${_o.companyName}',
      start: when,
      details: [
        if (_o.interviewMode.isNotEmpty) 'Mode: ${_o.interviewMode}',
        if (_o.interviewDetails.isNotEmpty) 'Details: ${_o.interviewDetails}',
      ].join('\n'),
      location: _o.interviewDetails,
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) AppToast.error('Could not open your calendar');
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final tasks = o.tasks;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: _statusColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CompanyName(
                                name: o.companyName,
                                verified: o.companyVerified,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              Text(o.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        StatusBadge(status: o.status),
                      ],
                    ),
                    if (tasks.isNotEmpty && !o.status.isClosed) ...[
                      const Divider(height: 20, color: AppColors.border),
                      for (final task in tasks.take(3)) _TaskRow(opportunity: o, task: task),
                      if (tasks.length > 3)
                        Text('+${tasks.length - 3} more tasks', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    if (o.status == OpportunityStatus.interviewScheduled && o.interviewDate != null) ..._interview(),
                    if (o.status == OpportunityStatus.offered || o.status == OpportunityStatus.hired) ..._offer(),
                    if (o.status == OpportunityStatus.withdrawn) ...[
                      const Divider(height: 20, color: AppColors.border),
                      Text(
                        o.offerResponse == 'declined' ? 'You declined this offer.' : 'You withdrew this application.',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ],
                    if (o.recruiterName.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text('Contact: ${o.recruiterName}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ),
                          if (o.status != OpportunityStatus.applied && o.status != OpportunityStatus.withdrawn)
                            InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  opportunity: o,
                                  currentUid: AuthService.instance.currentUid,
                                  currentName: o.candidateName,
                                ),
                              )),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Badge(
                                  isLabelVisible: o.unreadCount > 0,
                                  label: Text('${o.unreadCount}'),
                                  backgroundColor: AppColors.like,
                                  child: const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: AppColors.accentAlt),
                                ),
                              ),
                            ),
                          if (!o.status.isClosed)
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_horiz_rounded, size: 18, color: AppColors.textSecondary),
                              padding: EdgeInsets.zero,
                              enabled: !_busy,
                              onSelected: (value) {
                                if (value == 'withdraw') _withdraw();
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'withdraw', child: Text('Withdraw application')),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _interview() {
    final o = _o;
    final response = o.interviewResponse;
    return [
      const Divider(height: 20, color: AppColors.border),
      _DetailRow(icon: Icons.event_outlined, label: 'Interview', value: formatDateTime(o.interviewDate!)),
      if (o.interviewMode.isNotEmpty) _DetailRow(icon: Icons.videocam_outlined, label: 'Mode', value: o.interviewMode),
      if (o.interviewDetails.isNotEmpty) _DetailRow(icon: Icons.link_rounded, label: 'Details', value: o.interviewDetails),
      const SizedBox(height: 4),
      if (response == InterviewResponse.confirmed)
        const Align(
          alignment: Alignment.centerLeft,
          child: StatePill(label: 'You confirmed', color: AppColors.like, icon: Icons.check_circle_rounded),
        )
      else if (response == InterviewResponse.rescheduleRequested)
        Align(
          alignment: Alignment.centerLeft,
          child: StatePill(
            label: o.interviewResponseNote.isEmpty ? 'Reschedule requested' : 'Reschedule requested: ${o.interviewResponseNote}',
            color: AppColors.warning,
            icon: Icons.event_repeat_rounded,
          ),
        )
      else
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _confirmInterview,
              icon: const Icon(Icons.check_rounded, size: 16),
              label: const Text('Confirm'),
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _askToReschedule,
              icon: const Icon(Icons.event_repeat_rounded, size: 16),
              label: const Text('Ask for another time'),
              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _addToCalendar,
          icon: const Icon(Icons.edit_calendar_outlined, size: 16),
          label: const Text('Add to calendar'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
        ),
      ),
    ];
  }

  List<Widget> _offer() {
    final o = _o;
    final answered = o.offerResponse.isNotEmpty;
    return [
      const Divider(height: 20, color: AppColors.border),
      if (o.offerSalaryLpa != null)
        _DetailRow(icon: Icons.payments_outlined, label: 'Offered CTC', value: '₹${o.offerSalaryLpa!.toStringAsFixed(1)} LPA'),
      if (o.offerJoiningDate != null)
        _DetailRow(icon: Icons.event_available_outlined, label: 'Joining date', value: formatDay(o.offerJoiningDate!)),
      if (o.offerNotes.isNotEmpty) _DetailRow(icon: Icons.notes_rounded, label: 'Notes', value: o.offerNotes),
      if (o.status == OpportunityStatus.offered) ...[
        const SizedBox(height: 4),
        if (o.offerResponse == 'accepted')
          const Align(
            alignment: Alignment.centerLeft,
            child: StatePill(label: 'You accepted this offer', color: AppColors.like, icon: Icons.celebration_rounded),
          )
        else if (!answered)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _acceptOffer,
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Accept offer'),
                style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: AppColors.like),
              ),
              OutlinedButton(
                onPressed: _busy ? null : _declineOffer,
                style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: AppColors.reject),
                child: const Text('Decline'),
              ),
            ],
          ),
      ],
    ];
  }
}

/// One assessment task on an application: what it is, where it stands and
/// the button to open (and hand in) the work.
class _TaskRow extends StatelessWidget {
  final Opportunity opportunity;
  final OpportunityTask task;
  const _TaskRow({required this.opportunity, required this.task});

  @override
  Widget build(BuildContext context) {
    final due = task.dueDate;
    final (color, text, cta) = switch (task.status) {
      TaskStatus.assigned when task.hasChangeRequest => (AppColors.warning, 'Changes requested', 'Fix and resubmit'),
      TaskStatus.assigned when task.isOverdue => (AppColors.reject, due == null ? 'Overdue' : dueLabel(due), 'Open task'),
      TaskStatus.assigned => (AppColors.info, due == null ? 'To do' : 'To do · ${dueLabel(due).toLowerCase()}', 'Open task'),
      TaskStatus.submitted => (AppColors.accentAlt, 'Submitted · waiting for review', 'View'),
      TaskStatus.approved => (AppColors.like, 'Approved', 'View'),
      TaskStatus.rejected => (AppColors.reject, 'Not selected', 'View'),
    };
    final needsAction = task.status == TaskStatus.assigned;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.assignment_outlined, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          needsAction
              ? FilledButton(
                  onPressed: () => _open(context),
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(cta),
                )
              : OutlinedButton(
                  onPressed: () => _open(context),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: Text(cta),
                ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskSubmitScreen(opportunity: opportunity, taskId: task.id)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.accentAlt),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
