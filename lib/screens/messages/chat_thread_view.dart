import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/pair/chat_models.dart';
import '../../models/pair/pair_format.dart';
import '../../models/pair/pair_person.dart';
import '../../services/api_client.dart';
import '../../services/pair_chat_service.dart';
import '../../services/visible_poller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/trust_widgets.dart';
import '../candidate/company_page_screen.dart';
import '../interviews/schedule_interview_sheet.dart';
import 'pair_widgets.dart';

/// One conversation: header, messages (polled every 4 s while visible) and
/// the composer. Opening it marks the other side's messages read (the server
/// does that on `GET /chats/:id`).
class ChatThreadView extends StatefulWidget {
  /// The other side's user id.
  final String userId;
  final bool isCompany;

  /// Known details of the other side while the first fetch is in flight.
  final PairPerson? preview;

  /// Pipeline stage of the pair (company header pill), if known.
  final String stage;

  /// The signed-in account; used to open a company page from the header.
  final AppUser? user;
  final VoidCallback onBack;

  /// Called after a message was sent (so the list can refresh).
  final VoidCallback? onSent;

  const ChatThreadView({
    super.key,
    required this.userId,
    required this.isCompany,
    required this.onBack,
    this.preview,
    this.stage = '',
    this.user,
    this.onSent,
  });

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  static const int _maxLength = 2000;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final VisiblePoller _poller;

  PairThread? _thread;
  final List<PairMessage> _pending = [];
  String? _loadError;
  String? _sendError;
  bool _sending = false;
  int _localId = 0;

  @override
  void initState() {
    super.initState();
    _poller = VisiblePoller(interval: const Duration(seconds: 4), onTick: () => _fetch())..start();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _poller.setVisible(TickerMode.valuesOf(context).enabled);
  }

  @override
  void didUpdateWidget(covariant ChatThreadView old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId) {
      setState(() {
        _thread = null;
        _pending.clear();
        _loadError = null;
      });
      _poller.pokeNow();
    }
  }

  @override
  void dispose() {
    _poller.dispose();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _differs(List<PairMessage> a, List<PairMessage> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].read != b[i].read) return true;
    }
    return false;
  }

  Future<void> _fetch() async {
    final userId = widget.userId;
    try {
      final t = await PairChatService.instance.thread(userId);
      if (!mounted || userId != widget.userId) return;
      final first = _thread == null;
      final previous = _thread?.messages ?? const <PairMessage>[];
      final changed = first || _differs(previous, t.messages);
      final nearBottom = !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.offset < 160;
      final gotIncoming = !first && t.messages.length > previous.length && !t.messages.last.mine;
      setState(() {
        _thread = t;
        _loadError = null;
        // A pending bubble is confirmed once the server list has caught up.
        if (_pending.isNotEmpty && t.messages.isNotEmpty && t.messages.last.mine) _pending.clear();
      });
      if (changed && (first || nearBottom || !gotIncoming)) _scrollToEnd(animate: !first);
      if (first || gotIncoming) ChatUnreadPoller.instance.refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_thread == null) setState(() => _loadError = e.message);
    } catch (_) {
      if (mounted && _thread == null) setState(() => _loadError = 'Could not load this chat.');
    }
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      } else {
        _scroll.jumpTo(end);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending) return;
    if (text.isEmpty) {
      setState(() => _sendError = 'Message cannot be empty');
      return;
    }
    if (text.length > _maxLength) {
      setState(() => _sendError = 'Message is too long (max $_maxLength characters)');
      return;
    }
    final local = PairMessage(id: 'local-${_localId++}', text: text, mine: true, at: DateTime.now(), pending: true);
    setState(() {
      _sending = true;
      _sendError = null;
      _pending.add(local);
      _controller.clear();
    });
    _scrollToEnd();
    try {
      final sent = await PairChatService.instance.send(widget.userId, text);
      if (!mounted) return;
      setState(() {
        _pending.removeWhere((m) => m.id == local.id);
        final t = _thread;
        if (t != null && sent.id.isNotEmpty && !t.messages.any((m) => m.id == sent.id)) {
          _thread = PairThread(person: t.person, messages: [...t.messages, sent]);
        }
        _sending = false;
      });
      widget.onSent?.call();
      _scrollToEnd();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _pending.removeWhere((m) => m.id == local.id);
        _controller.text = text;
        _controller.selection = TextSelection.collapsed(offset: text.length);
        _sendError = e.message;
        _sending = false;
      });
    }
  }

  PairPerson get _person => _thread?.person ?? widget.preview ?? PairPerson(id: widget.userId, name: 'Chat');

  void _openCompanyPage() {
    final user = widget.user;
    if (widget.isCompany || user == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CompanyPageScreen(user: user, companyId: widget.userId),
    ));
  }

  Future<void> _scheduleInterview() async {
    final p = _person;
    await showScheduleInterviewSheet(context, candidateId: p.id, candidateName: p.name);
  }

  Widget _header() {
    final p = _person;
    final tappable = !widget.isCompany && widget.user != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 6),
      child: Row(
        children: [
          IconButton(onPressed: widget.onBack, tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: tappable ? _openCompanyPage : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    PairAvatar(name: p.name, url: p.avatarUrl, size: 40, square: !widget.isCompany),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CompanyName(
                            name: p.name,
                            verified: p.verified,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            tappable ? 'Tap for company details' : p.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.isCompany) ...[
            if (widget.stage.isNotEmpty) Padding(padding: const EdgeInsets.only(right: 6), child: StagePill(stage: widget.stage)),
            IconButton(
              onPressed: _scheduleInterview,
              tooltip: 'Interview',
              icon: const Icon(Icons.event_available_rounded, color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _messages() {
    final thread = _thread;
    if (thread == null) {
      if (_loadError != null) {
        return PairErrorState(message: _loadError!, onRetry: () {
          setState(() => _loadError = null);
          _fetch();
        });
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    final all = [...thread.messages, ..._pending];
    if (all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            widget.isCompany ? 'Say hello to ${_person.firstName} \u{1F44B}' : 'No messages yet. Say hello!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5),
          ),
        ),
      );
    }
    final breaks = dayBreaks(all);
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      itemCount: all.length,
      itemBuilder: (context, i) {
        final m = all[i];
        return Column(
          children: [
            if (breaks[i] && m.at != null) _DaySeparator(label: formatPairDay(m.at!)),
            _Bubble(message: m),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _controller.text.trim().isNotEmpty && !_sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(),
        const Divider(height: 1),
        Expanded(child: _messages()),
        if (_sendError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
            child: Text(_sendError!, style: const TextStyle(color: AppColors.reject, fontSize: 12.5)),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: _maxLength,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Type a message…',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surface,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: canSend ? _send : null,
                  tooltip: 'Send',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.3),
                    minimumSize: const Size(46, 46),
                  ),
                  icon: _sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary),
                        )
                      : const Icon(Icons.send_rounded, color: AppColors.onPrimary, size: 20),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DaySeparator extends StatelessWidget {
  final String label;
  const _DaySeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final PairMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final mine = message.mine;
    final maxWidth = MediaQuery.of(context).size.width * 0.8;
    final textColor = mine ? AppColors.onPrimary : AppColors.textPrimary;
    final metaColor = mine ? AppColors.onPrimaryMuted : AppColors.textSecondary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          gradient: mine ? AppColors.accentGradient : null,
          color: mine ? null : AppColors.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(message.text, style: TextStyle(color: textColor, fontSize: 14.5, height: 1.35)),
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.at != null)
                  Text(formatPairClock(message.at!), style: TextStyle(color: metaColor, fontSize: 10.5)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.pending
                        ? Icons.schedule_rounded
                        : (message.read ? Icons.done_all_rounded : Icons.done_rounded),
                    size: 13,
                    color: metaColor,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
