import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/error_reporter.dart';
import 'services/recruiter_profile_service.dart';
import 'services/wishlist_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e, stackTrace) {
    // Already initialized (e.g. hot restart), or genuinely unreachable
    // (first boot while offline) -- auth/candidate data simply won't load
    // until connectivity returns.
    debugPrint('[main] Firebase.initializeApp failed: $e\n$stackTrace');
  }

  // Crashlytics has no web implementation -- only wire it up on mobile.
  if (!kIsWeb) {
    FlutterError.onError = ErrorReporter.recordFlutterError;
    PlatformDispatcher.instance.onError = (error, stackTrace) {
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true);
      return true;
    };
  }

  await WishlistService.instance.init();
  await RecruiterProfileService.instance.init();

  runApp(const HiringApp());
}

class HiringApp extends StatelessWidget {
  const HiringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SwipeHire',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const SplashScreen(),
    );
  }
}
