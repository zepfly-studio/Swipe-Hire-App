import 'package:flutter/material.dart';
import '../../models/pair/chat_models.dart';
import '../../services/api_client.dart';
import '../../services/pair_chat_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/inputs/form_blocks.dart';
import '../../widgets/trust_widgets.dart';
import 'pair_widgets.dart';

/// Whether [c] matches the picker's search text (name or role/subtitle).
bool contactMatches(PairContact c, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return c.person.name.toLowerCase().contains(q) || c.person.subtitle.toLowerCase().contains(q);
}

/// "New message": pick someone you may chat with. Returns the chosen contact.
Future<PairContact?> showNewMessageSheet(BuildContext context, {required bool isCompany}) {
  return showPairSheet<PairContact>(
    context,
    (_) => _NewMessageBody(isCompany: isCompany),
    full: true,
  );
}

class _NewMessageBody extends StatefulWidget {
  final bool isCompany;
  const _NewMessageBody({required this.isCompany});

  @override
  State<_NewMessageBody> createState() => _NewMessageBodyState();
}

class _NewMessageBodyState extends State<_NewMessageBody> {
  List<PairContact>? _contacts;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final list = await PairChatService.instance.contacts();
      if (!mounted) return;
      setState(() => _contacts = list);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final contacts = _contacts;
    final filtered = contacts?.where((c) => contactMatches(c, _query)).toList() ?? const <PairContact>[];
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: PairSheetFrame(
        title: 'New message',
        subtitle: widget.isCompany ? 'Candidates you shortlisted' : 'Companies that contacted you',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: fieldDecoration(
                hintText: 'Search by name or role',
                prefix: const Icon(Icons.search_rounded, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              PairErrorState(message: _error!, onRetry: _load)
            else if (contacts == null)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator(color: AppColors.accentAlt)),
              )
            else if (contacts.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  widget.isCompany
                      ? 'Shortlist a candidate first, then you can message them.'
                      : 'No company has contacted you yet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No one matches “${_query.trim()}”.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              )
            else
              for (final c in filtered)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => Navigator.of(context).pop(c),
                  leading: PairAvatar(
                    name: c.person.name,
                    url: c.person.avatarUrl,
                    size: 42,
                    square: !widget.isCompany,
                  ),
                  title: CompanyName(
                    name: c.person.name,
                    verified: c.person.verified,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                  subtitle: c.person.subtitle.isEmpty
                      ? null
                      : Text(c.person.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.isCompany && c.stage.isNotEmpty) StagePill(stage: c.stage),
                      if (c.hasChat) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: AppColors.textSecondary),
                      ],
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
