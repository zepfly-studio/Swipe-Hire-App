import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/app_notification.dart';
import 'api_client.dart';
import 'error_reporter.dart';
import 'polling.dart';

/// The notification bell and the unread chat badge.
///
/// [summary] holds the two counts every badge in the app listens to. It is
/// refreshed on a timer while someone is signed in, and straight after any
/// write the app makes ([DataRefresh]), so a badge clears the moment the
/// chat or inbox is opened.
class InboxService {
  InboxService._internal({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final InboxService instance = InboxService._internal();

  @visibleForTesting
  factory InboxService.test(ApiClient api) => InboxService._internal(api: api);

  static const Duration _interval = Duration(seconds: 15);

  final ApiClient _api;
  final ValueNotifier<InboxSummary> summary = ValueNotifier(const InboxSummary());

  Timer? _timer;
  String? _uid;
  bool _refreshing = false;

  void start(String uid) {
    if (_uid == uid && _timer != null) return;
    stop();
    _uid = uid;
    DataRefresh.instance.addListener(_onDataChanged);
    refreshSummary();
    _timer = Timer.periodic(_interval, (_) => refreshSummary());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_uid != null) DataRefresh.instance.removeListener(_onDataChanged);
    _uid = null;
    summary.value = const InboxSummary();
  }

  void _onDataChanged() => refreshSummary();

  Future<void> refreshSummary() async {
    if (_uid == null || _refreshing) return;
    _refreshing = true;
    try {
      final res = await _api.get('/notifications/summary');
      if (_uid != null) summary.value = InboxSummary.fromMap(res);
    } catch (e, stackTrace) {
      // A flaky connection must never surface as an error.
      ErrorReporter.report(e, stackTrace, reason: 'InboxService: summary refresh failed');
    } finally {
      _refreshing = false;
    }
  }

  Future<List<AppNotification>> fetch({int limit = 50}) async {
    final res = await _api.get('/notifications', query: {'limit': '$limit'});
    return (res['notifications'] as List? ?? const [])
        .map((e) => AppNotification.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Marks [ids] -- or everything, when null -- as read.
  Future<void> markRead({List<String>? ids}) async {
    await _api.post('/notifications/read', body: {'ids': ?ids});
    await refreshSummary();
  }
}
