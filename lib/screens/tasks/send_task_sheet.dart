import 'package:flutter/material.dart';
import '../../models/pair/hiring_task.dart';
import '../../services/api_client.dart';
import '../../services/hiring_task_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/inputs/form_blocks.dart';
import '../messages/pair_inputs.dart';
import '../messages/pair_widgets.dart';

/// Opens the SendTaskModal. Resolves to true when a task was sent.
Future<bool> showSendTaskSheet(
  BuildContext context, {
  required String candidateId,
  required String candidateName,
  String? jobId,
}) async {
  final sent = await showPairSheet<bool>(
    context,
    (_) => SendTaskSheet(candidateId: candidateId, candidateName: candidateName, jobId: jobId),
    full: true,
  );
  return sent == true;
}

class SendTaskSheet extends StatefulWidget {
  final String candidateId;
  final String candidateName;
  final String? jobId;
  const SendTaskSheet({super.key, required this.candidateId, required this.candidateName, this.jobId});

  @override
  State<SendTaskSheet> createState() => _SendTaskSheetState();
}

class _SendTaskSheetState extends State<SendTaskSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _link = TextEditingController();
  DateTime _due = deadlinePreset(3);
  int? _preset = 3;

  String? _titleError;
  String? _descError;
  String? _linkError;
  String? _dueError;
  String? _formError;
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _link.dispose();
    super.dispose();
  }

  String get _firstName {
    final parts = widget.candidateName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? widget.candidateName : parts.first;
  }

  Future<void> _pickDue() async {
    final picked = await pickPairDateTime(
      context,
      initial: _due,
      last: DateTime.now().add(const Duration(days: 31)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _due = picked;
      _preset = null;
    });
  }

  Future<void> _send() async {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final link = checkTaskLink(_link.text, invalidMessage: 'Please enter a valid reference link');
    setState(() {
      _titleError = title.isEmpty ? 'Give the task a title' : null;
      _descError = description.isEmpty ? 'Describe what they should build' : null;
      _linkError = link.error;
      _dueError = validateTaskDeadline(_due);
      _formError = null;
    });
    if (_titleError != null || _descError != null || _linkError != null || _dueError != null) return;
    setState(() => _sending = true);
    try {
      await HiringTaskService.instance.create(
        candidateId: widget.candidateId,
        jobId: widget.jobId,
        title: title,
        description: description,
        briefUrl: link.url ?? '',
        dueAt: _due,
      );
      if (!mounted) return;
      AppToast.success('Task sent to $_firstName');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _formError = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PairSheetFrame(
      title: 'Send a task',
      subtitle: 'To ${widget.candidateName} · they submit a live link and GitHub repo before the deadline',
      footer: FilledButton(
        onPressed: _sending ? null : _send,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        child: _sending
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
            : const Text('Send task'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldBlock(
            label: 'Task title',
            required: true,
            error: _titleError,
            child: TextField(
              controller: _title,
              maxLength: 120,
              decoration: fieldDecoration(hintText: 'Build a to-do app with login', hasError: _titleError != null),
            ),
          ),
          const SizedBox(height: 12),
          FormFieldBlock(
            label: 'What should they build?',
            required: true,
            error: _descError,
            hint: 'Requirements, tech stack, what you will check',
            child: TextField(
              controller: _description,
              maxLength: 5000,
              minLines: 5,
              maxLines: 8,
              decoration: fieldDecoration(
                hintText: '- React front end, any backend\n- Users can add, edit and delete tasks\n'
                    '- Deploy it and share the live link + GitHub repo',
                hasError: _descError != null,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FormFieldBlock(
            label: 'Reference link',
            error: _linkError,
            hint: 'Optional: a brief, Figma design or doc',
            child: TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: fieldDecoration(hintText: 'https://figma.com/…', hasError: _linkError != null),
            ),
          ),
          const SizedBox(height: 12),
          FormFieldBlock(
            label: 'Deadline',
            error: _dueError,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChipSelect(
                  options: const ['1', '3', '7'],
                  value: _preset == null ? '' : '$_preset',
                  labels: const {'1': '1 day', '3': '3 days', '7': '1 week'},
                  onChanged: (v) => setState(() {
                    _preset = int.parse(v);
                    _due = deadlinePreset(_preset!);
                  }),
                ),
                const SizedBox(height: 10),
                DateTimeField(value: _due, onTap: _pickDue, hasError: _dueError != null),
              ],
            ),
          ),
          if (_formError != null) ...[
            const SizedBox(height: 12),
            InlineError(_formError!),
          ],
        ],
      ),
    );
  }
}
