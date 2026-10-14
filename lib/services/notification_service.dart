import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import '../widgets/app_toast.dart';
import 'error_reporter.dart';

/// Registers the signed-in device for push notifications -- saves its FCM
/// token to the backend (`PUT /users/me/fcm-token`), which the backend
/// reads to push a notification whenever a recruiter changes a candidate's
/// [Opportunity] status, a candidate applies, or either side sends a chat
/// message.
///
/// Web is skipped entirely: `getToken()` there needs a VAPID key
/// registered in the Firebase console first (Cloud Messaging > Web
/// configuration), which hasn't been done -- calling it without one
/// would just fail on every page load.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _initializedForUid;

  Future<void> initForSignedInUser(String uid) async {
    if (kIsWeb || _initializedForUid == uid) return;
    _initializedForUid = uid;
    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) {
        await _saveToken(token);
      }
      _messaging.onTokenRefresh.listen(_saveToken);

      // A push that arrives while the app is open isn't shown by the OS, so
      // show it as an in-app toast instead.
      FirebaseMessaging.onMessage.listen((message) {
        final title = message.notification?.title;
        if (title == null || title.isEmpty) return;
        AppToast.notification(
          title: title,
          body: message.notification?.body,
          type: message.data['type'] ?? message.data['status'],
        );
      });
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'NotificationService: init failed');
    }
  }

  Future<void> _saveToken(String token) async {
    try {
      await ApiClient.instance.put('/users/me/fcm-token', body: {'token': token});
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'NotificationService: save token failed');
    }
  }
}
