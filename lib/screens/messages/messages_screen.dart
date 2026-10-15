import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/pair/chat_models.dart';
import '../../models/pair/pair_format.dart';
import '../../models/pair/pair_person.dart';
import '../../services/api_client.dart';
import '../../services/pair_chat_service.dart';
import '../../services/pair_session.dart';
import '../../services/visible_poller.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_nav.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/trust_widgets.dart';
import 'chat_thread_view.dart';
import 'new_message_sheet.dart';
import 'pair_nav.dart';
import 'pair_widgets.dart';

/// Conversations + chat thread for BOTH roles (company <-> candidate).
class MessagesScreen extends StatefulWidget {
  /// Open the thread with this user id straight away (candidate id for a
  /// company, company id for a candidate).
  final String? initialWithUserId;

  /// Whether the signed-in account is a company. When null the screen asks
  /// the backend once (shells that know the role should pass it).
  final bool? isCompany;

  const MessagesScreen({super.key, this.initialWithUserId, this.isCompany});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  late final VisiblePoller _poller;
  bool? _isCompany;
  AppUser? _user;

  List<PairConversation>? _conversations;
  String? _error;
  String? _openId;
  PairPerson? _openPreview;
  String _openStage = '';
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _isCompany = widget.isCompany;
    _openId = widget.initialWithUserId;
    _poller = VisiblePoller(interval: const Duration(seconds: 10), onTick: _loadList)..start();
    AppNav.openChatWith.addListener(_onOpenChatRequest);
    _resolveUser();
    // A request that was set before this screen was built.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onOpenChatRequest());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _poller.setVisible(_visible && _openId == null);
  }

  @override
  void dispose() {
    AppNav.openChatWith.removeListener(_onOpenChatRequest);
    _poller.dispose();
    super.dispose();
  }

  Future<void> _resolveUser() async {
    try {
      final user = await PairSession.instance.user();
      if (!mounted) return;
      setState(() {
        _user = user;
        _isCompany ??= user == null ? false : user.role == UserRole.recruiter;
      });
    } catch (_) {
      if (mounted && _isCompany == null) setState(() => _isCompany = false);
    }
  }

  void _onOpenChatRequest() {
    final id = AppNav.openChatWith.value;
    if (id == null || id.isEmpty || !mounted) return;
    AppNav.openChatWith.value = null;
    _openThread(id);
  }

  Future<void> _loadList() async {
    try {
      final list = await PairChatService.instance.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = list;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (_conversations == null) setState(() => _error = e.message);
    } catch (_) {
      if (mounted && _conversations == null) setState(() => _error = 'Could not load your messages.');
    }
  }

  void _openThread(String id, {PairPerson? preview, String stage = ''}) {
    setState(() {
      _openId = id;
      _openPreview = preview;
      _openStage = stage;
      // Opening a chat marks it read: clear its badge right away.
      _conversations = _conversations
          ?.map((c) => c.person.id == id && c.unread > 0 ? c.withUnread(0) : c)
          .toList();
    });
    _poller.setVisible(false);
  }

  void _closeThread() {
    setState(() => _openId = null);
    _poller.setVisible(_visible);
    _poller.pokeNow();
    ChatUnreadPoller.instance.refresh();
  }

  Future<void> _newMessage() async {
    final contact = await showNewMessageSheet(context, isCompany: _isCompany ?? false);
    if (contact != null && mounted) {
      _openThread(contact.person.id, preview: contact.person, stage: contact.stage);
    }
  }

  PairPerson? _previewFor(String id) {
    for (final c in _conversations ?? const <PairConversation>[]) {
      if (c.person.id == id) return c.person;
    }
    return null;
  }

  String? _stageFor(String id) {
    for (final c in _conversations ?? const <PairConversation>[]) {
      if (c.person.id == id) return c.stage;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isCompany = _isCompany;
    final inThread = _openId != null;
    return PopScope(
      canPop: !(inThread && _visible),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inThread) _closeThread();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: AnimatedBackdrop(
          child: SafeArea(
            child: isCompany == null
                ? const Center(child: CircularProgressIndicator(color: AppColors.accentAlt))
                : inThread
                    ? ChatThreadView(
                        userId: _openId!,
                        isCompany: isCompany,
                        preview: _openPreview ?? _previewFor(_openId!),
                        stage: _openStage.isNotEmpty ? _openStage : (_stageFor(_openId!) ?? ''),
                        user: _user,
                        onBack: _closeThread,
                        onSent: _loadList,
                      )
                    : _listBody(isCompany),
          ),
        ),
      ),
    );
  }

  Widget _listBody(bool isCompany) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PairHeader(
          title: 'Messages',
          actions: [
            TextButton.icon(
              onPressed: _newMessage,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('New message'),
            ),
          ],
        ),
        Expanded(child: _list(isCompany)),
      ],
    );
  }

  Widget _list(bool isCompany) {
    final items = _conversations;
    if (items == null) {
      if (_error != null) {
        return PairErrorState(
          message: _error!,
          onRetry: () {
            setState(() => _error = null);
            _loadList();
          },
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    if (items.isEmpty) {
      return PairEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'No conversations yet',
        message: isCompany
            ? 'Message a candidate from your Shortlisted page, or tap New message.'
            : 'When a company messages you, the chat shows up here.',
        actionLabel: isCompany ? 'Open shortlisted' : null,
        onAction: isCompany ? () => PairNav.openShortlisted(context) : null,
      );
    }
    return RefreshIndicator(
      onRefresh: _loadList,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) => _ConversationTile(
          conversation: items[i],
          isCompany: isCompany,
          onTap: () => _openThread(items[i].person.id, preview: items[i].person, stage: items[i].stage),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final PairConversation conversation;
  final bool isCompany;
  final VoidCallback onTap;
  const _ConversationTile({required this.conversation, required this.isCompany, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    final preview = c.lastText.isEmpty ? c.person.subtitle : (c.lastMine ? 'You: ${c.lastText}' : c.lastText);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: unread ? AppColors.primary.withValues(alpha: 0.4) : AppColors.border),
          ),
          child: Row(
            children: [
              PairAvatar(name: c.person.name, url: c.person.avatarUrl, size: 48, square: !isCompany),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanyName(
                      name: c.person.name,
                      verified: c.person.verified,
                      style: TextStyle(fontSize: 15, fontWeight: unread ? FontWeight.w800 : FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: unread ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    conversationTime(c.lastAt ?? c.updatedAt),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: unread ? AppColors.primary : AppColors.textTertiary,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (unread)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        c.unread > 99 ? '99+' : '${c.unread}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.onPrimary, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    )
                  else
                    const SizedBox(height: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
