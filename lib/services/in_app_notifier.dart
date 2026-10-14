import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import '../models/app_notification.dart';
import '../widgets/app_toast.dart';
import 'error_reporter.dart';
import 'inbox_service.dart';

/// Of [fetched], the unread notifications that haven't been shown as a toast
/// yet (oldest first). Pure, so the rule can be tested without a timer.
List<AppNotification> unseenNotifications({
  required Set<String> seen,
  required List<AppNotification> fetched,
}) {
  final fresh = fetched.where((n) => !n.read && !seen.contains(n.id)).toList();
  return fresh.reversed.toList(); // the API sends newest first
}

/// Shows a toast when a new notification lands in the inbox while the app is
/// open. Push covers phones (shown as a toast by [NotificationService] while
/// the app is in the foreground); this is what gives the web build -- which
/// has no push -- the same live updates.
///
/// The backend's inbox is the single source of truth, so the toast, the bell
/// and the push can never disagree about what happened.
class InAppNotifier {
  InAppNotifier._();
  static final InAppNotifier instance = InAppNotifier._();

  static const Duration _interval = Duration(seconds: 10);

  /// More than this many arriving at once are summarised in one toast.
  static const int _maxToastsPerRefresh = 3;

  Timer? _timer;
  String? _uid;
  final Set<String> _seen = {};
  bool _baselined = false;
  bool _busy = false;

  @visibleForTesting
  bool enabledOverride = false;

  bool get _enabled => kIsWeb || enabledOverride;

  void start(String uid) {
    if (!_enabled) return;
    if (_uid == uid && _timer != null) return;
    stop();
    _uid = uid;
    _tick();
    _timer = Timer.periodic(_interval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _uid = null;
    _seen.clear();
    _baselined = false;
    _busy = false;
  }

  Future<void> _tick() async {
    final uid = _uid;
    if (_busy || uid == null) return;
    _busy = true;
    try {
      final fetched = await InboxService.instance.fetch(limit: 15);
      if (_uid != uid) return; // signed out / switched account mid-request

      if (!_baselined) {
        // What was already waiting when the app opened is the bell's job,
        // not a pop-up storm.
        _seen.addAll(fetched.map((n) => n.id));
        _baselined = true;
        return;
      }

      final fresh = unseenNotifications(seen: _seen, fetched: fetched);
      _seen.addAll(fetched.map((n) => n.id));
      if (fresh.isEmpty) return;
      _show(fresh);
      unawaited(InboxService.instance.refreshSummary());
    } catch (e, stackTrace) {
      // A flaky connection must never surface as an error toast.
      ErrorReporter.report(e, stackTrace, reason: 'InAppNotifier: refresh failed');
    } finally {
      _busy = false;
    }
  }

  void _show(List<AppNotification> fresh) {
    if (fresh.length > _maxToastsPerRefresh) {
      AppToast.notification(
        title: '${fresh.length} new notifications',
        body: 'Open the bell to see what happened.',
      );
      return;
    }
    for (final n in fresh) {
      AppToast.notification(title: n.title, body: n.body, type: n.type);
    }
  }
}
