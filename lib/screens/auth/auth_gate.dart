import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/in_app_notifier.dart';
import '../../services/inbox_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../candidate/candidate_root_shell.dart';
import '../candidate/onboarding/candidate_onboarding_screen.dart';
import '../recruiter/onboarding/company_onboarding_screen.dart';
import '../root_shell.dart';
import 'login_screen.dart';

/// Root router shown after the splash screen: signed-out users see the
/// login/signup flow; signed-in users are routed to the recruiter's
/// [RootShell] or the candidate's [CandidateRootShell] by their stored role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) return const LoginScreen();
        return _SignedInGate(key: ValueKey(user.uid), uid: user.uid);
      },
    );
  }
}

/// Loads the signed-in account's profile once (not on every rebuild) and
/// picks the right home screen. A network failure shows a retry screen; only
/// a session the server no longer accepts signs the user out.
class _SignedInGate extends StatefulWidget {
  final String uid;
  const _SignedInGate({super.key, required this.uid});

  @override
  State<_SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<_SignedInGate> {
  late Future<AppUser?> _profile = _load();

  Future<AppUser?> _load() async {
    final profile = await AuthService.instance.fetchProfileWithRetry(
      widget.uid,
    );
    if (profile == null) {
      // No valid session behind this Firebase user -- start over.
      await AuthService.instance.signOut();
      return null;
    }
    if (profile.profileComplete) {
      NotificationService.instance.initForSignedInUser(profile.uid);
      InAppNotifier.instance.start(profile.uid);
      InboxService.instance.start(profile.uid);
    }
    return profile;
  }

  void _retry() => setState(() => _profile = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUser?>(
      future: _profile,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          return _ConnectionProblemScreen(
            message: error is ApiException
                ? error.message
                : 'Something went wrong while loading your account.',
            onRetry: _retry,
          );
        }
        final profile = snapshot.data;
        if (profile == null) return const _LoadingScreen();
        if (!profile.profileComplete) {
          // Candidates get the 4-step onboarding, companies the 2-step one.
          return profile.role == UserRole.candidate
              ? CandidateOnboardingScreen(user: profile)
              : CompanyOnboardingScreen(userName: profile.name);
        }
        return profile.role == UserRole.recruiter
            ? const RootShell()
            : CandidateRootShell(user: profile);
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AnimatedBackdrop(
        child: Center(
          child: CircularProgressIndicator(color: AppColors.accentAlt),
        ),
      ),
    );
  }
}

class _ConnectionProblemScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ConnectionProblemScreen({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 56,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'We could not reach GlideRecruit',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => AuthService.instance.signOut(),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
