import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../candidate/candidate_root_shell.dart';
import '../root_shell.dart';
import 'complete_profile_screen.dart';
import 'login_screen.dart';
import 'verify_email_screen.dart';

/// Root router shown after the splash screen: signed-out users see the
/// login/signup flow; signed-in users are routed to the recruiter's
/// [RootShell] or the candidate placeholder based on their stored role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  /// Temporarily off so any email can sign in without clicking a
  /// verification link -- [VerifyEmailScreen] and the send/resend/reload
  /// plumbing in [AuthService] are still fully wired up, so turning this
  /// back on later is a one-line flip.
  static const bool requireEmailVerification = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        if (requireEmailVerification && !user.emailVerified) {
          return VerifyEmailScreen(email: user.email ?? '');
        }
        return FutureBuilder<AppUser?>(
          key: ValueKey(user.uid),
          future: AuthService.instance.fetchProfileWithRetry(user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen();
            }
            final profile = profileSnapshot.data;
            if (profile == null) {
              // Still missing after retrying -- a genuinely stale/corrupt
              // sign-in (not just a signup whose Firestore write hadn't
              // landed yet). Sign out rather than stranding the user on a
              // blank screen.
              AuthService.instance.signOut();
              return const _LoadingScreen();
            }
            if (!profile.profileComplete) {
              return CompleteProfileScreen(user: profile);
            }
            return profile.role == UserRole.recruiter
                ? const RootShell()
                : CandidateRootShell(user: profile);
          },
        );
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
        child: Center(child: CircularProgressIndicator(color: AppColors.accentAlt)),
      ),
    );
  }
}
