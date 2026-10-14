import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Single place every `catch` block reports through, instead of the
/// `catch (_) {}` pattern this app used to swallow errors with. Always
/// prints to the debug console (so errors are visible while developing),
/// and forwards to Crashlytics on mobile where that's supported --
/// Crashlytics has no web implementation, so web instead forwards to
/// Sentry (when [sentryWebDsn] is configured; see docs/sentry-setup.md).
class ErrorReporter {
  ErrorReporter._();

  /// Set from sentry.io and wired up in `main.dart`'s `SentryFlutter.init`
  /// call -- empty by default so this never tries reporting to a
  /// nonexistent project.
  static const String sentryWebDsn = '';

  static void report(Object error, StackTrace stackTrace, {String? reason}) {
    debugPrint('[ErrorReporter]${reason == null ? '' : ' $reason:'} $error\n$stackTrace');
    if (kIsWeb) {
      if (sentryWebDsn.isNotEmpty) Sentry.captureException(error, stackTrace: stackTrace);
      return;
    }
    FirebaseCrashlytics.instance.recordError(error, stackTrace, reason: reason);
  }

  static void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kIsWeb) return;
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }
}
