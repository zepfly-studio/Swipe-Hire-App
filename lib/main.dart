import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/error_reporter.dart';
import 'services/recruiter_profile_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_toast.dart';

Future<void> main() async {
  if (kIsWeb && ErrorReporter.sentryWebDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) => options.dsn = ErrorReporter.sentryWebDsn,
      appRunner: _runApp,
    );
  } else {
    await _runApp();
  }
}

Future<void> _runApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, stackTrace) {
    // Already initialized (e.g. hot restart), or genuinely unreachable
    // (first boot while offline) -- auth/candidate data simply won't load
    // until connectivity returns.
    debugPrint('[main] Firebase.initializeApp failed: $e\n$stackTrace');
  }

  if (kIsWeb) {
    // Crashlytics has no web implementation -- Sentry (above) covers web
    // instead, when configured; this still catches Flutter framework
    // errors and forwards them there.
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (ErrorReporter.sentryWebDsn.isNotEmpty) {
        Sentry.captureException(details.exception, stackTrace: details.stack);
      }
    };
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      if (ErrorReporter.sentryWebDsn.isNotEmpty) Sentry.captureException(error, stackTrace: stackTrace);
      return true;
    };
  } else {
    FlutterError.onError = ErrorReporter.recordFlutterError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
      return true;
    };
  }

  await _activateAppCheck();

  await Hive.initFlutter();
  await RecruiterProfileService.instance.init();

  runApp(const HiringApp());
}

/// Starts attaching App Check tokens to Firebase requests -- this alone
/// doesn't block anything; a service only rejects unattested requests
/// once "Enforce" is turned on for it in the Firebase console (see
/// docs/app-check-setup.md before flipping that on). A release build uses
/// the real attestation providers (Play Integrity / App Attest); a debug
/// build uses the debug provider instead, since Play Integrity/App Attest
/// need a signed, Play-Store-registered (or TestFlight) build to pass --
/// it prints a token to the device log on first run, which must be
/// registered in the console's App Check > Apps > "Manage debug tokens"
/// to be accepted. Web is skipped entirely for now: it needs a reCAPTCHA
/// v3 site key registered in the console first, and activating with a
/// placeholder key could make every Firebase call on web start failing.
Future<void> _activateAppCheck() async {
  if (kIsWeb) return;
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider: kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
    );
  } catch (e, stackTrace) {
    ErrorReporter.report(e, stackTrace, reason: 'App Check activation failed');
  }
}

class HiringApp extends StatelessWidget {
  const HiringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwipeHire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: AppToastHost.builder,
      home: const SplashScreen(),
    );
  }
}



