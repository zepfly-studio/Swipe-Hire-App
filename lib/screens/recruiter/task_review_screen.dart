import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/opportunity.dart';
import '../../services/api_client.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';
import '../../widgets/app_toast.dart';

/// What the recruiter decided on a submission.
enum TaskReviewOutcome { approvedSchedule, changes, rejected }

/// Recruiter reviews what the candidate submitted for the assigned task.
/// Approving goes straight on to scheduling the interview (the caller opens
/// the interview editor when this pops [TaskReviewOutcome.approvedSchedule]).
class TaskReviewScreen extends StatefulWidget {
  final Opportunity opportunity;

  /// The task being reviewed (an entry can have several).
  final OpportunityTask task;
  const TaskReviewScreen({super.key, required this.opportunity, required this.task});

  @override
  State<TaskReviewScreen> createState() => _TaskReviewScreenState();
}

class _TaskReviewScreenState extends State<TaskReviewScreen> {
  final _feedback = TextEditingController();
  bool _busy = false;

  OpportunityTask get _task => widget.task;

  @override
  void dispose() {
    _feedback.dispose();
    super.dispose();
  }

  Future<void> _decide(String decision) async {
    final feedback = _feedback.text.trim();
    if (decision == 'changes' && feedback.isEmpty) {
      _showError('Tell the candidate what to change.');
      return;
    }
    setState(() => _busy = true);
    try {
      await OpportunityService.instance.reviewTask(
        widget.opportunity.id,
        _task.id,
        decision: decision,
        feedback: feedback,
      );
      if (!mounted) return;
      Navigator.of(context).pop(switch (decision) {
        'approved' => TaskReviewOutcome.approvedSchedule,
        'changes' => TaskReviewOutcome.changes,
        _ => TaskReviewOutcome.rejected,
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'TaskReviewScreen: review failed');
      if (!mounted) return;
      _showError('Could not save your review. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    AppToast.error(message);
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      _showError('Could not open that link.');
    }
  }

  String _formatDateTime(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]} ${d.year}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    final o = widget.opportunity;
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
                      child: Text('Review ${o.candidateName}\'s task',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
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
                      FadeInUp(
                        child: SectionCard(
                          title: 'The task',
                          icon: Icons.assignment_outlined,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                              if (task.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(task.description, style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeInUp(
                        delay: const Duration(milliseconds: 40),
                        child: SectionCard(
                          title: 'Their submission',
                          icon: Icons.upload_file_rounded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (task.submittedAt != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.schedule_rounded, size: 15, color: AppColors.accentAlt),
                                      const SizedBox(width: 6),
                                      Text('Submitted ${_formatDateTime(task.submittedAt!)}', style: const TextStyle(fontSize: 12.5)),
                                      if (task.wasSubmittedLate) ...[
                                        const SizedBox(width: 8),
                                        const Text('Late', style: TextStyle(color: AppColors.reject, fontWeight: FontWeight.w700, fontSize: 12.5)),
                                      ],
                                    ],
                                  ),
                                ),
                              if (task.answer.isNotEmpty) Text(task.answer, style: const TextStyle(fontSize: 14, height: 1.4)),
                              if (task.submissionLink.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                InkWell(
                                  onTap: () => _open(task.submissionLink),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.open_in_new_rounded, size: 16, color: AppColors.accent),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(task.submissionLink,
                                            style: const TextStyle(color: AppColors.accent, fontSize: 13, decoration: TextDecoration.underline),
                                            overflow: TextOverflow.ellipsis),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              if (task.submissionFileUrl.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                InkWell(
                                  onTap: () => _open(task.submissionFileUrl),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.attach_file_rounded, size: 16, color: AppColors.accent),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          task.submissionFileName.isEmpty ? 'Attached file' : task.submissionFileName,
                                          style: const TextStyle(color: AppColors.accent, fontSize: 13, decoration: TextDecoration.underline),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeInUp(
                        delay: const Duration(milliseconds: 80),
                        child: TextField(
                          controller: _feedback,
                          minLines: 2,
                          maxLines: 5,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: InputDecoration(
                            labelText: 'Feedback for the candidate (required to ask for changes)',
                            alignLabelWithHint: true,
                            filled: true,
                            fillColor: AppColors.surface,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeInUp(
                        delay: const Duration(milliseconds: 120),
                        child: FilledButton.icon(
                          onPressed: _busy ? null : () => _decide('approved'),
                          icon: const Icon(Icons.event_available_rounded, size: 18),
                          label: const Text('Approve & schedule interview'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeInUp(
                        delay: const Duration(milliseconds: 150),
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : () => _decide('changes'),
                          icon: const Icon(Icons.edit_note_rounded, size: 18),
                          label: const Text('Ask for changes'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      FadeInUp(
                        delay: const Duration(milliseconds: 180),
                        child: TextButton.icon(
                          onPressed: _busy ? null : () => _decide('rejected'),
                          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.reject),
                          label: const Text('Not a fit', style: TextStyle(color: AppColors.reject)),
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
}
