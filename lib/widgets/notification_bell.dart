import 'package:flutter/material.dart';
import '../models/app_notification.dart';
import '../screens/inbox_screen.dart';
import '../services/inbox_service.dart';
import '../services/pair_chat_service.dart';
import '../theme/app_theme.dart';

/// The bell in a screen's header: opens the inbox, with a count of what's
/// unread. Listens to [InboxService.summary], so it clears as soon as the
/// inbox is read.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InboxSummary>(
      valueListenable: InboxService.instance.summary,
      builder: (context, summary, _) {
        final n = summary.unreadNotifications;
        return IconButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxScreen())),
          tooltip: n > 0 ? '$n unread notifications' : 'Notifications',
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text(n > 99 ? '99+' : '$n'),
            backgroundColor: AppColors.like,
            child: const Icon(Icons.notifications_none_rounded, color: AppColors.textPrimary),
          ),
        );
      },
    );
  }
}

/// A bottom-navigation icon that shows how many chat messages are unread
/// (`GET /chats/unread-count`, polled every 15 s while a badge is on screen).
class UnreadChatIcon extends StatefulWidget {
  final IconData icon;
  const UnreadChatIcon({super.key, required this.icon});

  @override
  State<UnreadChatIcon> createState() => _UnreadChatIconState();
}

class _UnreadChatIconState extends State<UnreadChatIcon> {
  @override
  void initState() {
    super.initState();
    ChatUnreadPoller.instance.acquire();
  }

  @override
  void dispose() {
    ChatUnreadPoller.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    return ValueListenableBuilder<int>(
      valueListenable: ChatUnreadPoller.instance.count,
      builder: (context, n, _) {
        return Badge(
          isLabelVisible: n > 0,
          label: Text(n > 99 ? '99+' : '$n'),
          backgroundColor: AppColors.like,
          child: Icon(icon),
        );
      },
    );
  }
}
