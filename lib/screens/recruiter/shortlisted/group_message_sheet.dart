import 'package:flutter/material.dart';
import '../../../models/candidate.dart';
import '../../../services/api_client.dart';
import '../../../services/pair_chat_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../messages/pair_widgets.dart';

/// Who a group message reached.
class GroupMessageResult {
  final int sent;
  final Set<String> sentIds;
  const GroupMessageResult({required this.sent, required this.sentIds});
}

/// Opens the GroupMessageModal for [recipients] (already de-duplicated by
/// person). Resolves to the result, or null when dismissed / nothing sent.
Future<GroupMessageResult?> showGroupMessageSheet(BuildContext context, List<Candidate> recipients) {
  return showPairSheet<GroupMessageResult>(
    context,
    (_) => GroupMessageSheet(recipients: recipients),
    full: true,
  );
}

class GroupMessageSheet extends StatefulWidget {
  final List<Candidate> recipients;
  const GroupMessageSheet({super.key, required this.recipients});

  @override
  State<GroupMessageSheet> createState() => _GroupMessageSheetState();
}

class _GroupMessageSheetState extends State<GroupMessageSheet> {
  late List<Candidate> _to;
  final _text = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _to = List.of(widget.recipients);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (_to.isEmpty) {
      setState(() => _error = 'Choose at least one candidate');
      return;
    }
    if (text.isEmpty) {
      setState(() => _error = 'Write a message first');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final ids = [for (final c in _to) c.id];
      final res = await PairChatService.instance.sendBulk(ids, text);
      if (!mounted) return;
      final sentIds = ids.where((id) => !res.skipped.contains(id)).toSet();
      final n = res.sent > 0 ? res.sent : sentIds.length;
      AppToast.success('Message sent to $n candidate${n == 1 ? '' : 's'}');
      Navigator.of(context).pop(GroupMessageResult(sent: n, sentIds: sentIds));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = _to.length;
    return PairSheetFrame(
      title: 'Message $n candidate${n == 1 ? '' : 's'}',
      subtitle: 'Each one gets it as a private chat message and an email.',
      footer: FilledButton(
        onPressed: _sending ? null : _send,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        child: _sending
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
            : Text('Send to $n candidate${n == 1 ? '' : 's'}'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldBlock(
            label: 'To',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _to)
                  InputChip(
                    avatar: PairAvatar(name: c.name, url: c.photoUrl, size: 22),
                    label: Text(c.name, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    onDeleted: _to.length > 1 ? () => setState(() => _to.remove(c)) : null,
                    backgroundColor: AppColors.surface,
                    side: BorderSide(color: AppColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FormFieldBlock(
            label: 'Message',
            child: TextField(
              controller: _text,
              maxLength: 2000,
              minLines: 5,
              maxLines: 8,
              decoration: fieldDecoration(
                hintText: 'Hi! Thanks for your interest in the role.\n'
                    'We would like to invite you for an interview next week. Please reply with your availability.',
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Candidates will see your company name with this message, and can reply in Messages.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
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
