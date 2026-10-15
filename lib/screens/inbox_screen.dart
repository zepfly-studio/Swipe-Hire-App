import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../models/opportunity.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../services/inbox_service.dart';
import '../services/opportunity_service.dart';
import '../services/recruiter_profile_service.dart';
import '../theme/app_theme.dart';
import '../utils/time_format.dart';
import '../widgets/animated_background.dart';
import '../widgets/app_toast.dart';
import '../widgets/fade_in_up.dart';
import '../models/pair/notification_link.dart';
import '../services/pair_session.dart';
import 'chat_screen.dart';
import 'messages/pair_nav.dart';

/// The bell's list: everything that happened to this account, newest first,
/// with unread ones marked. Tapping one marks it read and, when it belongs
/// to an application, opens that conversation.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  List<AppNotification>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await InboxService.instance.fetch(limit: 60);
      if (!mounted) return;
      setState(() {
        _items = items;
        _error = null;
      });
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'InboxScreen: load failed');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  bool get _hasUnread => _items?.any((n) => !n.read) ?? false;

  Future<void> _markAllRead() async {
    final before = _items;
    if (before == null) return;
    setState(() => _items = before.map((n) => n.asRead()).toList());
    try {
      await InboxService.instance.markRead();
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'InboxScreen: mark all read failed');
      if (!mounted) return;
      setState(() => _items = before);
      AppToast.error('Could not mark them as read', description: 'Check your connection and try again.');
    }
  }

  Future<void> _open(AppNotification n) async {
    if (!n.read) {
      setState(() => _items = _items?.map((x) => x.id == n.id ? x.asRead() : x).toList());
      InboxService.instance.markRead(ids: [n.id]).catchError((Object e, StackTrace s) {
        ErrorReporter.report(e, s, reason: 'InboxScreen: mark read failed');
      });
    }
    if (n.link.isNotEmpty) {
      final target = parseNotificationLink(n.link);
      if (target.kind != NotificationTargetKind.unknown) {
        bool? isCompany;
        try {
          isCompany = await PairSession.instance.isCompany();
        } catch (_) {
          isCompany = null;
        }
        if (!mounted) return;
        if (isCompany != null && PairNav.openTarget(context, target, isCompany: isCompany)) return;
      }
    }
    if (n.opportunityId.isEmpty) return;
    try {
      final opportunities = await OpportunityService.instance.fetchMine();
      Opportunity? match;
      for (final o in opportunities) {
        if (o.id == n.opportunityId) match = o;
      }
      if (match == null || !mounted) return;
      if (match.status == OpportunityStatus.applied) return; // no thread yet
      final uid = AuthService.instance.currentUid;
      final isCandidate = match.candidateUid == uid;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          opportunity: match!,
          currentUid: uid,
          currentName: isCandidate ? match.candidateName : RecruiterProfileService.instance.name,
        ),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      AppToast.error('Could not open that', description: e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    const Expanded(
                      child: Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    if (_hasUnread)
                      TextButton.icon(
                        onPressed: _markAllRead,
                        icon: const Icon(Icons.done_all_rounded, size: 18),
                        label: const Text('Mark all read'),
                      ),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final items = _items;
    if (items == null && _error == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    }
    if (items == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              const Text('Could not load your notifications', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty) {
      return FadeInUp(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Nothing yet.\nTasks, interviews and offers will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) => _NotificationTile(item: items[index], onTap: () => _open(items[index])),
      ),
    );
  }
}

/// Icon + colour per notification type (spec B0: shortlisted = sparkles,
/// message = chat bubble, interview = calendar, hired = party popper,
/// verified = badge, alert = bell, task = clipboard).
({IconData icon, Color color}) _styleFor(String type) => switch (type) {
      'shortlisted' => (icon: Icons.auto_awesome_rounded, color: AppColors.accent),
      'message' => (icon: Icons.chat_bubble_rounded, color: AppColors.accentAlt),
      'hired' => (icon: Icons.celebration_rounded, color: AppColors.like),
      'verified' => (icon: Icons.verified_rounded, color: AppColors.info),
      'alert' => (icon: Icons.notifications_active_rounded, color: AppColors.warning),
      _ => toastStyleOf(toastKindForType(type)),
    };

class _NotificationTile extends StatelessWidget {
  final AppNotification item;
  final VoidCallback onTap;
  const _NotificationTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(item.type);
    return Material(
      color: item.read ? AppColors.surface : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: item.read ? AppColors.border : style.color.withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: style.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(style.icon, size: 20, color: style.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(fontWeight: item.read ? FontWeight.w600 : FontWeight.w800, fontSize: 14),
                    ),
                    if (item.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(item.body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35)),
                    ],
                    const SizedBox(height: 4),
                    Text(timeAgo(item.createdAt), style: const TextStyle(color: AppColors.textTertiary, fontSize: 11.5)),
                  ],
                ),
              ),
              if (!item.read)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 6),
                  child: Container(width: 9, height: 9, decoration: BoxDecoration(color: style.color, shape: BoxShape.circle)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
