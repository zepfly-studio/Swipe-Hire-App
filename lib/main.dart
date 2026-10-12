import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/recruiter_profile_service.dart';
import 'services/wishlist_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (_) {
    // Already initialized (e.g. hot restart), or genuinely unreachable
    // (first boot while offline) -- auth/candidate data simply won't load
    // until connectivity returns.
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
