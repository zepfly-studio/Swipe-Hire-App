import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../models/opportunity.dart';
import '../services/chat_service.dart';
import '../services/error_reporter.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/app_toast.dart';

/// Real-time chat tied to one [Opportunity] -- available to a recruiter
/// and the candidate they shortlisted (or moved further) once there's
/// something to actually discuss (an applied-but-untouched candidate has
/// no chat entry point; see [HiringPipelineScreen]/[CandidateApplicationTile]).
/// `.snapshots()` on the messages subcollection is what makes this live;
/// no separate chat server involved.
class ChatScreen extends StatefulWidget {
  final Opportunity opportunity;

  /// Whoever opened this screen -- either side of the opportunity.
  final String currentUid;
  final String currentName;

  const ChatScreen({
    super.key,
    required this.opportunity,
    required this.currentUid,
    required this.currentName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  String get _otherPartyName =>
      widget.currentUid == widget.opportunity.candidateUid ? widget.opportunity.recruiterName : widget.opportunity.candidateName;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _controller.clear();
    try {
      await ChatService.instance.sendMessage(
        opportunityId: widget.opportunity.id,
        senderUid: widget.currentUid,
        senderName: widget.currentName,
        text: text,
      );
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'ChatScreen: sendMessage failed');
      if (mounted) {
        AppToast.error('Message not sent. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    SizedBox(width: 36, height: 36, child: ClipOval(child: InitialsAvatar(name: _otherPartyName))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_otherPartyName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis),
                          Text(widget.opportunity.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: ChatService.instance.streamMessages(widget.opportunity.id),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? const <ChatMessage>[];
                    if (messages.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No messages yet. Say hello!',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      );
                    }
                    _scrollToBottomSoon();
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      itemCount: messages.length,
                      itemBuilder: (context, index) => _MessageBubble(
                        message: messages[index],
                        isMine: messages[index].senderUid == widget.currentUid,
                      ),
                    );
                  },
                ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: const TextStyle(color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: AppColors.accent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _sending ? null : _send,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                    : const Icon(Icons.send_rounded, color: AppColors.onPrimary, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  const _MessageBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _SystemCard(message: message);
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        decoration: BoxDecoration(
          color: isMine ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMine ? 16 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 16),
          ),
          border: isMine ? null : Border.all(color: AppColors.border),
        ),
        child: Text(
          message.text,
          style: TextStyle(color: isMine ? AppColors.onPrimary : AppColors.textPrimary, fontSize: 14),
        ),
      ),
    );
  }
}

/// The automatic messages the task and interview flow posts into the
/// thread, shown as a labelled card instead of an ordinary chat bubble.
class _SystemCard extends StatelessWidget {
  final ChatMessage message;
  const _SystemCard({required this.message});

  @override
  Widget build(BuildContext context) {
    final isInterview = message.kind == 'interview';
    final color = isInterview ? AppColors.warning : AppColors.accent;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isInterview ? Icons.event_available_rounded : Icons.assignment_outlined, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                isInterview ? 'INTERVIEW' : 'TASK',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
              ),
              const Spacer(),
              Text(message.senderName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(message.text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.4)),
        ],
      ),
    );
  }
}
