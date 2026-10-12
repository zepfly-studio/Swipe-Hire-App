import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Single place every `catch` block reports through, instead of the
/// `catch (_) {}` pattern this app used to swallow errors with. Always
/// prints to the debug console (so errors are visible while developing),
/// and forwards to Crashlytics on mobile where that's supported --
/// Crashlytics has no web implementation, so [kIsWeb] guards every call
/// into it rather than letting it throw/no-op unpredictably there.
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
