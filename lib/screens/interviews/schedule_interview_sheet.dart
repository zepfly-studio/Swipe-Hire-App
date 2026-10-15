import 'package:flutter/material.dart';
import '../../models/pair/interview.dart';
import '../../services/api_client.dart';
import '../../services/interview_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/inputs/form_blocks.dart';
import '../messages/pair_inputs.dart';
import '../messages/pair_widgets.dart';

/// Opens the ScheduleInterviewModal. Resolves to true when an invite was sent.
Future<bool> showScheduleInterviewSheet(
  BuildContext context, {
  required String candidateId,
  required String candidateName,
  String? jobId,
}) async {
  final sent = await showPairSheet<bool>(
    context,
    (_) => ScheduleInterviewSheet(candidateId: candidateId, candidateName: candidateName, jobId: jobId),
    full: true,
  );
  return sent == true;
}

class ScheduleInterviewSheet extends StatefulWidget {
  final String candidateId;
  final String candidateName;
  final String? jobId;
  const ScheduleInterviewSheet({super.key, required this.candidateId, required this.candidateName, this.jobId});

  @override
  State<ScheduleInterviewSheet> createState() => _ScheduleInterviewSheetState();
}

class _ScheduleInterviewSheetState extends State<ScheduleInterviewSheet> {
  late List<DateTime?> _slots;
  int _duration = 30;
  String _mode = 'video';
  final _link = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _slots = defaultInterviewSlots(DateTime.now());
  }

  @override
  void dispose() {
    _link.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _firstName {
    final parts = widget.candidateName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? widget.candidateName : parts.first;
  }

  Future<void> _pick(int index) async {
    final current = _slots[index] ?? DateTime.now().add(const Duration(days: 1));
    final picked = await pickPairDateTime(context, initial: current);
    if (picked != null && mounted) setState(() => _slots[index] = picked);
  }

  Future<void> _send() async {
    final problem = validateInterviewForm(
      slots: _slots,
      mode: _mode,
      location: _address.text,
      now: DateTime.now(),
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final link = _link.text.trim();
    if (_mode == 'video' && link.isNotEmpty && !link.startsWith('https://')) {
      setState(() => _error = 'Meeting link must start with https://');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await InterviewService.instance.create(
        candidateId: widget.candidateId,
        jobId: widget.jobId,
        slots: slotsToIso(_slots),
        durationMins: _duration,
        mode: _mode,
        location: _address.text,
        meetingLink: link,
        note: _note.text,
      );
      if (!mounted) return;
      AppToast.success('Interview invite sent to $_firstName');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = interviewErrorText(e.message);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PairSheetFrame(
      title: 'Schedule interview',
      subtitle: 'With ${widget.candidateName} · they pick the time that suits them',
      footer: FilledButton(
        onPressed: _sending ? null : _send,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        child: _sending
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Text('Send invite'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldBlock(
            label: 'Time options (up to 3)',
            child: Column(
              children: [
                for (var i = 0; i < _slots.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DateTimeField(
                      value: _slots[i],
                      onTap: () => _pick(i),
                      onRemove: _slots.length > 1 ? () => setState(() => _slots.removeAt(i)) : null,
                    ),
                  ),
                if (_slots.length < 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        final last = _slots.whereType<DateTime>().fold<DateTime?>(
                              null,
                              (a, b) => a == null || b.isAfter(a) ? b : a,
                            ) ??
                            DateTime.now();
                        setState(() => _slots.add(DateTime(last.year, last.month, last.day + 1, 11)));
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add another time'),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          FormFieldBlock(
            label: 'Duration',
            child: ChipSelect(
              options: [for (final d in kInterviewDurations) '$d'],
              value: '$_duration',
              labels: {for (final d in kInterviewDurations) '$d': '$d min'},
              onChanged: (v) => setState(() => _duration = int.parse(v)),
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Interview type',
            child: ChipSelect(
              options: kInterviewModes,
              value: _mode,
              labels: {for (final m in kInterviewModes) m: interviewModeLabel(m)},
              onChanged: (v) => setState(() => _mode = v),
            ),
          ),
          const SizedBox(height: 16),
          if (_mode == 'video')
            FormFieldBlock(
              label: 'Meeting link',
              hint: "Leave empty and we'll create a free Jitsi video room for you",
              child: TextField(
                controller: _link,
                keyboardType: TextInputType.url,
                decoration: fieldDecoration(hintText: 'https://meet.google.com/...'),
              ),
            ),
          if (_mode == 'in-person')
            FormFieldBlock(
              label: 'Office address',
              child: TextField(
                controller: _address,
                maxLength: 200,
                decoration: fieldDecoration(hintText: '2nd floor, Tower B, Malviya Nagar, Jaipur'),
              ),
            ),
          if (_mode != 'phone') const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Note for the candidate',
            hint: 'Optional',
            child: TextField(
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: fieldDecoration(hintText: 'Please bring your portfolio'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            InlineError(_error!),
          ],
        ],
      ),
    );
  }
}
