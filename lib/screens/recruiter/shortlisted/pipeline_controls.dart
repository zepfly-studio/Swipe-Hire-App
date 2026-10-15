import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/candidate.dart';
import '../../../models/pair/pipeline_stage.dart';
import '../../../services/api_client.dart';
import '../../../services/pipeline_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../interviews/schedule_interview_sheet.dart';
import '../../messages/pair_nav.dart';
import '../../tasks/send_task_sheet.dart';

/// The stage / private-notes / action-buttons box of the candidate modal.
class PipelineControls extends StatefulWidget {
  final Candidate candidate;
  final ValueChanged<String> onStageChanged;
  final ValueChanged<String> onNotesChanged;

  /// A task or interview was sent from here (the parent refreshes its tasks).
  final VoidCallback onTaskSent;
  final VoidCallback onInterviewSent;

  const PipelineControls({
    super.key,
    required this.candidate,
    required this.onStageChanged,
    required this.onNotesChanged,
    required this.onTaskSent,
    required this.onInterviewSent,
  });

  @override
  State<PipelineControls> createState() => _PipelineControlsState();
}

class _PipelineControlsState extends State<PipelineControls> {
  late String _stage;
  late String _savedNotes;
  late final TextEditingController _notes;
  final _focus = FocusNode();
  bool _savingNotes = false;

  Candidate get _c => widget.candidate;

  @override
  void initState() {
    super.initState();
    _stage = _c.stage.isEmpty ? 'shortlisted' : _c.stage;
    _savedNotes = _c.notes;
    _notes = TextEditingController(text: _c.notes);
    _notes.addListener(() => setState(() {}));
    _focus.addListener(() {
      if (!_focus.hasFocus) _saveNotes();
    });
  }

  @override
  void dispose() {
    // Closing the modal while the box is focused still saves.
    if (_dirty && !_savingNotes && _c.swipeId.isNotEmpty) {
      final text = _notes.text;
      unawaited(PipelineService.instance.setNotes(_c.swipeId, text).then((_) {
        widget.onNotesChanged(text);
      }).catchError((Object _) {}));
    }
    _focus.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _dirty => _notes.text != _savedNotes;

  Future<void> _saveNotes() async {
    if (!_dirty || _savingNotes || _c.swipeId.isEmpty) return;
    final text = _notes.text;
    _savingNotes = true;
    try {
      await PipelineService.instance.setNotes(_c.swipeId, text);
      _savedNotes = text;
      widget.onNotesChanged(text);
      if (mounted) {
        setState(() {});
        AppToast.success('Notes saved');
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not save the notes', description: e.message);
    } finally {
      _savingNotes = false;
    }
  }

  Future<void> _setStage(String next) async {
    if (next == _stage || _c.swipeId.isEmpty) return;
    final previous = _stage;
    setState(() => _stage = next); // optimistic
    try {
      await PipelineService.instance.setStage(_c.swipeId, next);
      widget.onStageChanged(next);
      AppToast.success('Moved to ${stageLabel(next)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _stage = previous);
      AppToast.error('Could not change the stage', description: e.message);
    }
  }

  Future<void> _sendTask() async {
    final sent = await showSendTaskSheet(
      context,
      candidateId: _c.id,
      candidateName: _c.name,
      jobId: _c.jobId.isEmpty ? null : _c.jobId,
    );
    if (!sent || !mounted) return;
    if (_stage == 'shortlisted' || _stage == 'contacted') {
      setState(() => _stage = 'task');
      widget.onStageChanged('task');
    }
    widget.onTaskSent();
  }

  Future<void> _interview() async {
    final sent = await showScheduleInterviewSheet(
      context,
      candidateId: _c.id,
      candidateName: _c.name,
      jobId: _c.jobId.isEmpty ? null : _c.jobId,
    );
    if (!sent || !mounted) return;
    if (_stage != 'hired' && _stage != 'rejected') {
      setState(() => _stage = 'interview');
      widget.onStageChanged('interview');
    }
    widget.onInterviewSent();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldBlock(
            label: 'Stage',
            child: ChipSelect(
              options: kPipelineStages,
              value: _stage,
              labels: {for (final s in kPipelineStages) s: stageLabel(s)},
              onChanged: _setStage,
            ),
          ),
          const SizedBox(height: 14),
          FormFieldBlock(
            label: 'Private notes',
            hint: _dirty ? 'Saves when you tap outside the box' : null,
            child: TextField(
              controller: _notes,
              focusNode: _focus,
              maxLength: 2000,
              minLines: 3,
              maxLines: 6,
              textInputAction: TextInputAction.done,
              onTapOutside: (_) => _focus.unfocus(),
              decoration: fieldDecoration(hintText: 'Only your team can see these notes'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => PairNav.openChat(context, _c.id, isCompany: true),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                  label: const Text('Message'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _sendTask,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.assignment_outlined, size: 17),
                  label: const Text('Send task'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _interview,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 46), padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.event_available_rounded, size: 17),
                  label: const Text('Interview'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
