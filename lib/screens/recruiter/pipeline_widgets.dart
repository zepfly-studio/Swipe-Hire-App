import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/candidate.dart';
import '../../models/opportunity.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/time_format.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';
import '../../widgets/trust_widgets.dart';
import '../chat_screen.dart';
import 'assign_task_screen.dart';
import 'task_review_screen.dart';

// ---------------------------------------------------------------- actions --
//
// What a recruiter can do to a pipeline entry, as plain functions so every
// screen that lists entries (the Pipeline tab, a posting's applicants) does
// exactly the same thing.

/// Opens the editor for a new entry ([candidate]) or an existing one.
void openOpportunityEditor(
  BuildContext context, {
  AppUser? candidate,
  Opportunity? existing,
  OpportunityStatus? initialStatus,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => OpportunityEditorScreen(candidate: candidate, existing: existing, initialStatus: initialStatus),
    ),
  );
}

Future<void> assignTaskTo(BuildContext context, Opportunity opportunity) async {
  final sent = await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => AssignTaskScreen(opportunity: opportunity)),
  );
  if (sent == true && context.mounted) {
    AppToast.success('Task sent', description: '${opportunity.candidateName} has been notified.');
  }
}

/// Reviews [task] (default: the first one waiting). Approving goes straight
/// on to scheduling the interview.
Future<void> reviewTaskOf(BuildContext context, Opportunity opportunity, {OpportunityTask? task}) async {
  final target = task ?? (opportunity.tasksToReview.isNotEmpty ? opportunity.tasksToReview.first : opportunity.task);
  if (target == null) return;
  final outcome = await Navigator.of(context).push<TaskReviewOutcome>(
    MaterialPageRoute(builder: (_) => TaskReviewScreen(opportunity: opportunity, task: target)),
  );
  if (outcome == null || !context.mounted) return;
  switch (outcome) {
    case TaskReviewOutcome.approvedSchedule:
      // Another task may still be waiting; only go on to the interview once
      // nothing else is open.
      final othersOpen = opportunity.tasks.any((t) => t.id != target.id && t.status != TaskStatus.approved && t.status != TaskStatus.rejected);
      if (othersOpen) {
        AppToast.success('Task approved', description: 'Review the remaining tasks, then schedule the interview.');
      } else {
        openOpportunityEditor(context, existing: opportunity, initialStatus: OpportunityStatus.interviewScheduled);
      }
    case TaskReviewOutcome.changes:
      AppToast.info('Sent back for changes', description: '${opportunity.candidateName} will see your feedback.');
    case TaskReviewOutcome.rejected:
      AppToast.warning('Marked as not selected', description: '${opportunity.candidateName} has been told.');
  }
}

Future<void> moveOpportunity(BuildContext context, Opportunity opportunity, OpportunityStatus status) async {
  // An interview needs a date, mode and link, so collect those first.
  if (status == OpportunityStatus.interviewScheduled) {
    openOpportunityEditor(context, existing: opportunity, initialStatus: OpportunityStatus.interviewScheduled);
    return;
  }
  try {
    await OpportunityService.instance.save(opportunity.copyWithStatus(status));
  } catch (e, stackTrace) {
    ErrorReporter.report(e, stackTrace, reason: 'Pipeline: quick status move failed');
    if (!context.mounted) return;
    AppToast.error('Could not move candidate. Please try again.');
  }
}

void openChatWith(BuildContext context, Opportunity opportunity) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ChatScreen(
      opportunity: opportunity,
      currentUid: AuthService.instance.currentUid,
      currentName: RecruiterProfileService.instance.name,
    ),
  ));
}

// ------------------------------------------------------------------- tile --

/// One entry on the recruiter's side: who, where they stand, and the next
/// thing to do (assign a task, review a submission, schedule the interview,
/// mark an accepted offer as hired).
class PipelineTile extends StatelessWidget {
  final Opportunity opportunity;

  /// Shown as a chip when known (the applicants list scores each person).
  final Candidate? candidate;
  final VoidCallback onTap;
  final ValueChanged<OpportunityStatus> onMove;
  final VoidCallback onAssignTask;
  final ValueChanged<OpportunityTask> onReviewTask;
  final VoidCallback onScheduleInterview;
  final VoidCallback onOpenChat;

  const PipelineTile({
    super.key,
    required this.opportunity,
    this.candidate,
    required this.onTap,
    required this.onMove,
    required this.onAssignTask,
    required this.onReviewTask,
    required this.onScheduleInterview,
    required this.onOpenChat,
  });

  @override
  Widget build(BuildContext context) {
    final match = candidate?.matchScore;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: ClipOval(child: InitialsAvatar(name: opportunity.candidateName)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(opportunity.candidateName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(opportunity.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                        if (match != null) ...[
                          const SizedBox(height: 6),
                          Align(alignment: Alignment.centerLeft, child: MatchChip(score: match, compact: true)),
                        ],
                      ],
                    ),
                  ),
                  StatusBadge(status: opportunity.status),
                  if (opportunity.status != OpportunityStatus.applied)
                    IconButton(
                      onPressed: onOpenChat,
                      icon: Badge(
                        isLabelVisible: opportunity.unreadCount > 0,
                        label: Text('${opportunity.unreadCount}'),
                        backgroundColor: AppColors.like,
                        child: const Icon(Icons.chat_bubble_outline_rounded, size: 19, color: AppColors.accentAlt),
                      ),
                      tooltip: 'Message ${opportunity.candidateName}',
                    ),
                  PopupMenuButton<OpportunityStatus>(
                    icon: const Icon(Icons.more_vert_rounded, size: 20, color: AppColors.textSecondary),
                    tooltip: 'Move to',
                    onSelected: onMove,
                    enabled: opportunity.status != OpportunityStatus.withdrawn,
                    itemBuilder: (context) => OpportunityStatus.values
                        .where((s) => s != opportunity.status && s.isManual)
                        .map((s) => PopupMenuItem(value: s, child: Text('Move to ${s.label}')))
                        .toList(),
                  ),
                ],
              ),
              ..._nextStep(),
            ],
          ),
        ),
      ),
    );
  }

  /// The strip(s) under the candidate's row for what happens next.
  List<Widget> _nextStep() {
    final status = opportunity.status;
    final strips = <Widget>[];

    Widget strip(IconData icon, Color color, String label, {Widget? action, List<Widget> trailing = const []}) {
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600))),
            ...trailing,
            if (action != null) ...[const SizedBox(width: 8), action],
          ],
        ),
      );
    }

    final compact = FilledButton.styleFrom(visualDensity: VisualDensity.compact);

    if (status == OpportunityStatus.withdrawn) {
      final declined = opportunity.offerResponse == 'declined';
      strips.add(strip(Icons.logout_rounded, AppColors.textSecondary, declined ? 'Declined the offer' : 'The candidate withdrew'));
    } else if (status == OpportunityStatus.interviewScheduled && opportunity.interviewDate != null) {
      final when = formatDateTime(opportunity.interviewDate!);
      switch (opportunity.interviewResponse) {
        case InterviewResponse.confirmed:
          strips.add(strip(Icons.event_available_rounded, AppColors.like, 'Interview $when · confirmed'));
        case InterviewResponse.rescheduleRequested:
          final note = opportunity.interviewResponseNote;
          strips.add(strip(
            Icons.event_repeat_rounded,
            AppColors.warning,
            'Asked to reschedule${note.isEmpty ? '' : ': $note'}',
            action: FilledButton.tonal(onPressed: onScheduleInterview, style: compact, child: const Text('Pick a new time')),
          ));
        case InterviewResponse.none:
          strips.add(strip(Icons.event_outlined, AppColors.textSecondary, 'Interview $when · waiting for confirmation'));
      }
    } else if (status == OpportunityStatus.offered) {
      if (opportunity.offerResponse == 'accepted') {
        strips.add(strip(
          Icons.celebration_rounded,
          AppColors.like,
          'Offer accepted',
          action: FilledButton(
            onPressed: () => onMove(OpportunityStatus.hired),
            style: compact,
            child: const Text('Mark as hired'),
          ),
        ));
      } else {
        strips.add(strip(Icons.hourglass_empty_rounded, AppColors.textSecondary, 'Offer sent · waiting for an answer'));
      }
    }

    // Assessment tasks only matter before the interview stage.
    final tasks = opportunity.tasks;
    final toReview = opportunity.tasksToReview;
    final pending = opportunity.pendingTasks;
    final beforeInterview = status == OpportunityStatus.applied ||
        status == OpportunityStatus.shortlisted ||
        status == OpportunityStatus.taskAssigned ||
        status == OpportunityStatus.taskSubmitted;

    if (toReview.isNotEmpty) {
      final first = toReview.first;
      final extra = toReview.length > 1 ? ' (+${toReview.length - 1} more)' : '';
      strips.add(strip(
        Icons.inbox_rounded,
        AppColors.accent,
        '"${first.title}" submitted${first.wasSubmittedLate ? ' late' : ''}$extra, ready to review',
        action: FilledButton.icon(
          onPressed: () => onReviewTask(first),
          icon: const Icon(Icons.rate_review_outlined, size: 16),
          label: const Text('Review'),
          style: compact,
        ),
      ));
    }
    if (pending.isNotEmpty) {
      final first = pending.first;
      final extra = pending.length > 1 ? ' (+${pending.length - 1} more)' : '';
      final overdue = pending.any((t) => t.isOverdue);
      strips.add(strip(
        first.hasChangeRequest ? Icons.edit_note_rounded : (overdue ? Icons.schedule_rounded : Icons.hourglass_empty_rounded),
        overdue ? AppColors.reject : AppColors.accentAlt,
        first.hasChangeRequest
            ? '"${first.title}": changes requested$extra, waiting for the candidate'
            : '"${first.title}": ${overdue ? 'overdue' : 'waiting for the candidate'}$extra',
      ));
    }
    if (beforeInterview && toReview.isEmpty && pending.isEmpty) {
      if (tasks.isEmpty) {
        strips.add(strip(
          Icons.assignment_outlined,
          AppColors.accentAlt,
          'Next: give them a task before the interview',
          action: FilledButton.tonalIcon(
            onPressed: onAssignTask,
            icon: const Icon(Icons.assignment_add, size: 16),
            label: const Text('Assign task'),
            style: compact,
          ),
        ));
      } else if (tasks.every((t) => t.status == TaskStatus.approved)) {
        strips.add(strip(
          Icons.check_circle_outline_rounded,
          AppColors.like,
          tasks.length == 1 ? 'Task approved. Schedule the interview.' : 'All ${tasks.length} tasks approved. Schedule the interview.',
          action: FilledButton.icon(
            onPressed: onScheduleInterview,
            icon: const Icon(Icons.event_available_rounded, size: 16),
            label: const Text('Schedule interview'),
            style: compact,
          ),
        ));
      }
    }
    if (beforeInterview && tasks.isNotEmpty && tasks.length < 5 && toReview.isEmpty) {
      strips.add(Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onAssignTask,
          icon: const Icon(Icons.add_rounded, size: 16),
          label: const Text('Assign another task'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 4)),
        ),
      ));
    }

    if (strips.isEmpty) return const [];
    return [const Divider(height: 22, color: AppColors.border), ...strips];
  }
}

// ----------------------------------------------------------------- editor --

/// Create (candidate != null) or edit (existing != null) an [Opportunity]:
/// status, interview schedule, offer details.
class OpportunityEditorScreen extends StatefulWidget {
  final AppUser? candidate;
  final Opportunity? existing;

  /// Opens the editor with this status already chosen (e.g. straight to
  /// "Interview scheduled" after a task is approved).
  final OpportunityStatus? initialStatus;
  const OpportunityEditorScreen({super.key, this.candidate, this.existing, this.initialStatus});

  @override
  State<OpportunityEditorScreen> createState() => _OpportunityEditorScreenState();
}

class _OpportunityEditorScreenState extends State<OpportunityEditorScreen> {
  final _role = TextEditingController();
  final _interviewDetails = TextEditingController();
  final _interviewMode = TextEditingController();
  final _offerSalary = TextEditingController();
  final _offerNotes = TextEditingController();

  OpportunityStatus _status = OpportunityStatus.shortlisted;
  DateTime? _interviewDate;
  DateTime? _offerJoiningDate;
  bool _saving = false;

  Opportunity? get _existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    if (existing != null) {
      _role.text = existing.role;
      _status = existing.status;
      _interviewDate = existing.interviewDate;
      _interviewMode.text = existing.interviewMode;
      _interviewDetails.text = existing.interviewDetails;
      _offerSalary.text = existing.offerSalaryLpa?.toString() ?? '';
      _offerJoiningDate = existing.offerJoiningDate;
      _offerNotes.text = existing.offerNotes;
    }
    if (widget.initialStatus != null) _status = widget.initialStatus!;
  }

  @override
  void dispose() {
    _role.dispose();
    _interviewDetails.dispose();
    _interviewMode.dispose();
    _offerSalary.dispose();
    _offerNotes.dispose();
    super.dispose();
  }

  Future<void> _pickInterviewDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _interviewDate ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_interviewDate ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() => _interviewDate = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _pickJoiningDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _offerJoiningDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    setState(() => _offerJoiningDate = date);
  }

  Future<void> _save() async {
    if (_status == OpportunityStatus.interviewScheduled && _interviewDate == null) {
      AppToast.error('Pick the interview date and time first.');
      return;
    }
    setState(() => _saving = true);
    final recruiter = RecruiterProfileService.instance;
    final existing = _existing;
    final candidate = widget.candidate;

    final opportunity = Opportunity(
      id: existing?.id ?? '',
      candidateUid: existing?.candidateUid ?? candidate!.uid,
      candidateName: existing?.candidateName ?? candidate!.name,
      recruiterUid: AuthService.instance.currentUid,
      companyName: recruiter.company.isEmpty ? 'Hiring company' : recruiter.company,
      recruiterName: recruiter.name,
      role: _role.text.trim(),
      status: _status,
      interviewDate: _status == OpportunityStatus.interviewScheduled ? _interviewDate : null,
      interviewMode: _status == OpportunityStatus.interviewScheduled ? _interviewMode.text.trim() : '',
      interviewDetails: _status == OpportunityStatus.interviewScheduled ? _interviewDetails.text.trim() : '',
      offerSalaryLpa: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired)
          ? double.tryParse(_offerSalary.text.trim())
          : null,
      offerJoiningDate: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired) ? _offerJoiningDate : null,
      offerNotes: (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired) ? _offerNotes.text.trim() : '',
    );

    try {
      await OpportunityService.instance.save(opportunity);
      if (!mounted) return;
      Navigator.of(context).pop();
      if (_status == OpportunityStatus.interviewScheduled) {
        final who = existing?.candidateName ?? candidate?.name ?? 'The candidate';
        AppToast.success('Interview scheduled', description: '$who has been notified with the date and details.');
      } else {
        AppToast.success('Saved');
      }
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'Pipeline: save opportunity failed');
      if (!mounted) return;
      AppToast.error('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _existing?.candidateName ?? widget.candidate?.name ?? '';
    final existing = _existing;
    final asksToReschedule = existing != null &&
        existing.status == OpportunityStatus.interviewScheduled &&
        existing.interviewResponse == InterviewResponse.rescheduleRequested;
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    Expanded(
                      child: Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (asksToReschedule)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FadeInUp(
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.warning.withValues(alpha: 0.45)),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.event_repeat_rounded, color: AppColors.warning, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '$name asked for another time: "${existing.interviewResponseNote}". '
                                      'Pick a new date below and save; they will be notified.',
                                      style: const TextStyle(fontSize: 13, height: 1.35),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      FadeInUp(
                        child: TextField(
                          controller: _role,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: _decoration('Role', Icons.work_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FadeInUp(delay: const Duration(milliseconds: 40), child: _buildStatusPicker()),
                      const SizedBox(height: 18),
                      if (_status == OpportunityStatus.interviewScheduled)
                        FadeInUp(delay: const Duration(milliseconds: 80), child: _buildInterviewFields()),
                      if (_status == OpportunityStatus.offered || _status == OpportunityStatus.hired)
                        FadeInUp(delay: const Duration(milliseconds: 80), child: _buildOfferFields()),
                      const SizedBox(height: 26),
                      FadeInUp(
                        delay: const Duration(milliseconds: 160),
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _saving
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPicker() {
    return SectionCard(
      title: 'Status',
      icon: Icons.flag_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: OpportunityStatus.values.where((s) => s.isManual || s == _status).map((status) {
          final selected = status == _status;
          return ChoiceChip(
            label: Text(status.label),
            selected: selected,
            onSelected: status.isManual ? (_) => setState(() => _status = status) : null,
            selectedColor: AppColors.accent.withValues(alpha: 0.35),
            backgroundColor: AppColors.surfaceAlt,
            labelStyle: TextStyle(color: selected ? AppColors.textPrimary : AppColors.textSecondary, fontWeight: FontWeight.w600),
            side: const BorderSide(color: AppColors.border),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInterviewFields() {
    return SectionCard(
      title: 'Interview schedule',
      icon: Icons.event_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _pickInterviewDateTime,
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_interviewDate == null ? 'Pick date & time' : formatDateTime(_interviewDate!)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interviewMode,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Mode (e.g. Online / In-person)', Icons.videocam_outlined),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _interviewDetails,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Link or address', Icons.link_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferFields() {
    return SectionCard(
      title: 'Offer details',
      icon: Icons.card_giftcard_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _offerSalary,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Offered CTC (LPA)', Icons.payments_outlined),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _pickJoiningDate,
            icon: const Icon(Icons.event_available_outlined, size: 16),
            label: Text(_offerJoiningDate == null ? 'Pick joining date' : formatDay(_offerJoiningDate!)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _offerNotes,
            maxLines: 2,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: _decoration('Notes', Icons.notes_rounded),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }
}
