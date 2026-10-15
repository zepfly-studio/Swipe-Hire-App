import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/opportunity.dart';
import '../../services/api_client.dart';
import '../../services/cloudinary_service.dart';
import '../../services/error_reporter.dart';
import '../../services/opportunity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';
import '../../widgets/app_toast.dart';

/// Candidate side of the assessment: read the task, hand in an answer
/// and/or a link, and see the recruiter's feedback. Can be re-submitted
/// until the recruiter reviews it.
class TaskSubmitScreen extends StatefulWidget {
  final Opportunity opportunity;

  /// Which of the entry's tasks to open (default: the one that needs the
  /// candidate's attention first).
  final String? taskId;

  /// Defaults to [OpportunityService.instance]; tests pass a fake-backed one.
  final OpportunityService? service;

  /// Uploads an attached file and returns its link; tests replace it.
  final Future<String> Function(PlatformFile file)? uploadFile;

  const TaskSubmitScreen({super.key, required this.opportunity, this.taskId, this.service, this.uploadFile});

  @override
  State<TaskSubmitScreen> createState() => _TaskSubmitScreenState();
}

class _TaskSubmitScreenState extends State<TaskSubmitScreen> {
  late Opportunity _opportunity = widget.opportunity;
  late final TextEditingController _answer = TextEditingController(text: _opportunity.task?.answer ?? '');
  late final TextEditingController _link = TextEditingController(text: _opportunity.task?.submissionLink ?? '');
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  bool _uploading = false;

  /// A file just attached (not yet submitted), or kept from a submission.
  PlatformFile? _pickedFile;
  String _fileUrl = '';
  String _fileName = '';

  /// Reopens the form on an already-submitted task ("Edit submission").
  bool _editing = false;

  OpportunityTask? get _task {
    final id = widget.taskId;
    if (id != null) {
      for (final t in _opportunity.tasks) {
        if (t.id == id) return t;
      }
    }
    return _opportunity.task;
  }

  @override
  void initState() {
    super.initState();
    final task = _task;
    _answer.text = task?.answer ?? '';
    _link.text = task?.submissionLink ?? '';
    _fileUrl = task?.submissionFileUrl ?? '';
    _fileName = task?.submissionFileName ?? '';
  }

  Future<void> _pickFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: CloudinaryService.taskFileExtensions,
    );
    final file = files.isEmpty ? null : files.first;
    if (file == null || !mounted) return;
    final size = file.lengthSync() ?? await file.length();
    if (size != null && size > 10 * 1024 * 1024) {
      _showError('${file.name} is larger than 10 MB.');
      return;
    }
    setState(() {
      _pickedFile = file;
      _fileName = file.name;
    });
  }

  void _removeFile() => setState(() {
        _pickedFile = null;
        _fileUrl = '';
        _fileName = '';
      });

  @override
  void dispose() {
    _answer.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final task = _task;
    if (task == null) return;
    if (_answer.text.trim().isEmpty && _link.text.trim().isEmpty && _fileName.isEmpty) {
      _showError('Add your answer, a link, or a file.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      var fileUrl = _fileUrl;
      var fileName = _fileName;
      final picked = _pickedFile;
      if (picked != null) {
        setState(() => _uploading = true);
        fileUrl = await (widget.uploadFile ?? CloudinaryService.instance.uploadTaskFile)(picked);
        fileName = picked.name;
      }
      final updated = await (widget.service ?? OpportunityService.instance).submitTask(
        _opportunity.id,
        task.id,
        answer: _answer.text.trim(),
        link: _link.text.trim(),
        fileUrl: fileUrl,
        fileName: fileName,
      );
      if (!mounted) return;
      // The form empties as soon as the work is in; the submission is then
      // shown read-only below, with "Edit submission" to change it.
      _answer.clear();
      _link.clear();
      _formKey.currentState?.reset();
      setState(() {
        _opportunity = updated;
        _editing = false;
        _pickedFile = null;
        _fileUrl = '';
        _fileName = '';
      });
      await _showSubmittedPopup();
    } on ApiException catch (e) {
      if (!mounted) return;
      _showError(e.message);
    } on StateError catch (e) {
      // CloudinaryService reports a bad file as a StateError with a message
      // written for the person.
      if (!mounted) return;
      _showError(e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'TaskSubmitScreen: submit failed');
      if (!mounted) return;
      _showError('Could not submit. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploading = false;
        });
      }
    }
  }

  Future<void> _showSubmittedPopup() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        icon: const Icon(Icons.check_circle_rounded, color: AppColors.like, size: 52),
        title: const Text('Task submitted', textAlign: TextAlign.center),
        content: Text(
          'Your work for "${_task?.title ?? 'the task'}" is with ${_opportunity.companyName}. '
          'They have been notified and will review it soon. You will get an update here and as a notification.',
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.4),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(minimumSize: const Size(140, 46)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _startEditing() {
    final task = _task;
    if (task == null) return;
    _answer.text = task.answer;
    _link.text = task.submissionLink;
    _fileUrl = task.submissionFileUrl;
    _fileName = task.submissionFileName;
    setState(() => _editing = true);
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

  String _formatDay(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _formatDateTime(DateTime d) {
    final hour = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final minute = d.minute.toString().padLeft(2, '0');
    return '${_formatDay(d)}, $hour:$minute ${d.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
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
                      child: Text(
                        task?.title ?? 'Task',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: task == null
                    ? const Center(child: Text('No task here yet.', style: TextStyle(color: AppColors.textSecondary)))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FadeInUp(child: _statusBanner(task)),
                            const SizedBox(height: 14),
                            FadeInUp(delay: const Duration(milliseconds: 40), child: _taskCard(task)),
                            const SizedBox(height: 14),
                            if (task.status == TaskStatus.assigned || (task.status == TaskStatus.submitted && _editing))
                              FadeInUp(delay: const Duration(milliseconds: 80), child: _form(task))
                            else ...[
                              FadeInUp(delay: const Duration(milliseconds: 80), child: _readOnlySubmission(task)),
                              if (task.status == TaskStatus.submitted) ...[
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _startEditing,
                                  icon: const Icon(Icons.edit_outlined, size: 18),
                                  label: const Text('Edit submission'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                ),
                              ],
                            ],
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

  Widget _statusBanner(OpportunityTask task) {
    final (color, icon, text) = switch (task.status) {
      TaskStatus.assigned when task.hasChangeRequest => (
          AppColors.warning,
          Icons.edit_note_rounded,
          'Changes requested: ${task.feedback}',
        ),
      TaskStatus.assigned when task.isOverdue => (AppColors.reject, Icons.schedule_rounded, 'This task is past its due date. You can still submit it.'),
      TaskStatus.assigned => (AppColors.info, Icons.assignment_late_outlined, 'Waiting for your submission.'),
      TaskStatus.submitted => (
          AppColors.accentAlt,
          Icons.hourglass_top_rounded,
          'Submitted${task.submittedAt == null ? '' : ' on ${_formatDateTime(task.submittedAt!)}'}. Waiting for the recruiter to review.',
        ),
      TaskStatus.approved => (
          AppColors.like,
          Icons.check_circle_outline_rounded,
          task.feedback.isEmpty
              ? 'Approved. The recruiter will schedule your interview next.'
              : 'Approved. ${task.feedback}',
        ),
      TaskStatus.rejected => (
          AppColors.reject,
          Icons.cancel_outlined,
          task.feedback.isEmpty ? 'The recruiter did not move forward with this task.' : 'Not selected. ${task.feedback}',
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.35))),
        ],
      ),
    );
  }

  Widget _taskCard(OpportunityTask task) {
    return SectionCard(
      title: '${_opportunity.companyName}${_opportunity.role.isEmpty ? '' : ' · ${_opportunity.role}'}',
      icon: Icons.assignment_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(task.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(task.description, style: const TextStyle(fontSize: 14, height: 1.4)),
          ],
          if (task.link.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _open(task.link),
              child: Row(
                children: [
                  const Icon(Icons.link_rounded, size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(task.link,
                        style: const TextStyle(color: AppColors.accent, fontSize: 13, decoration: TextDecoration.underline),
                        overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ],
          if (task.dueDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.event_outlined, size: 16, color: task.isOverdue ? AppColors.reject : AppColors.accentAlt),
                const SizedBox(width: 6),
                Text(
                  'Due ${_formatDay(task.dueDate!)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: task.isOverdue ? AppColors.reject : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _form(OpportunityTask task) {
    final resubmitting = task.status == TaskStatus.submitted;
    return SectionCard(
      title: resubmitting ? 'Your submission' : 'Submit your work',
      icon: Icons.upload_file_rounded,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _answer,
              minLines: 5,
              maxLines: 10,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Your answer or notes',
                alignLabelWithHint: true,
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _link,
              keyboardType: TextInputType.url,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Link to your work (GitHub, Drive, Figma, video)',
                prefixIcon: const Icon(Icons.link_rounded, color: AppColors.accentAlt, size: 20),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
              validator: (v) {
                final value = v?.trim() ?? '';
                if (value.isEmpty) return null;
                return RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(value)
                    ? null
                    : 'Start the link with http:// or https://';
              },
            ),
            const SizedBox(height: 12),
            _attachmentRow(),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(_uploading ? 'Uploading file...' : (resubmitting ? 'Update submission' : 'Submit task')),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentRow() {
    if (_fileName.isEmpty) {
      return OutlinedButton.icon(
        onPressed: _sending ? null : _pickFile,
        icon: const Icon(Icons.attach_file_rounded, size: 18),
        label: const Text('Attach a file (PDF, image, zip, doc)'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(46),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.insert_drive_file_outlined, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(_fileName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
          IconButton(
            onPressed: _sending ? null : _removeFile,
            icon: const Icon(Icons.close_rounded, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _readOnlySubmission(OpportunityTask task) {
    return SectionCard(
      title: 'Your submission',
      icon: Icons.upload_file_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.answer.isNotEmpty) Text(task.answer, style: const TextStyle(fontSize: 14, height: 1.4)),
          if (task.submissionLink.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _open(task.submissionLink),
              child: Text(task.submissionLink,
                  style: const TextStyle(color: AppColors.accent, fontSize: 13, decoration: TextDecoration.underline)),
            ),
          ],
          if (task.submissionFileUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
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
          if (!task.hasSubmission)
            const Text('Nothing was submitted.', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
