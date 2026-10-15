import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Central error reporting: debug console on every platform,
/// Firebase Crashlytics on mobile. Web errors are logged locally.
class ErrorReporter {
  ErrorReporter._();

  static void report(Object error, StackTrace stackTrace, {String? reason}) {
    debugPrint('[ErrorReporter]${reason == null ? '' : ' $reason:'} $error\n$stackTrace');
    if (kIsWeb) return;
    FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
  }

  static void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kIsWeb) return;
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }
}
