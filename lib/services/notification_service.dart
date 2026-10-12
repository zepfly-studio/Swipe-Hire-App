import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'error_reporter.dart';

/// Registers the signed-in device for push notifications -- saves its FCM
/// token to `users/{uid}.fcmToken`, which the `notifyCandidateOnOpportunityChange`
/// Cloud Function reads to push a notification whenever a recruiter
/// changes a candidate's [Opportunity] status (shortlisted, interview
/// scheduled, offered, ...).
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
        await _saveToken(uid, token);
      }
      _messaging.onTokenRefresh.listen((newToken) => _saveToken(uid, newToken));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'NotificationService: init failed');
    }
  }

  Future<void> _saveToken(String uid, String token) {
    return FirebaseFirestore.instance.collection('users').doc(uid).update({'fcmToken': token});
  }
}
