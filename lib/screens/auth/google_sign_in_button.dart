import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'auth_error.dart';

/// "or" divider plus a "Continue with Google" button.
///
/// For someone who already has an account it signs them in. A first-time
/// Google account has to say whether it is for hiring or for finding a job,
/// so the button asks (unless [role] was already chosen on the screen it
/// sits on) and tries again.
///
/// [onSignedIn] runs after a successful sign-in; the login screen needs
/// nothing (AuthGate takes over), the signup screen uses it to close itself.
class GoogleSignInButton extends StatefulWidget {
  final UserRole? role;
  final VoidCallback? onSignedIn;
  final bool enabled;
  const GoogleSignInButton({super.key, this.role, this.onSignedIn, this.enabled = true});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  bool _busy = false;

  Future<UserRole?> _askRole() {
    return showDialog<UserRole>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('How will you use GlideRecruit?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(UserRole.candidate),
            child: const ListTile(
              leading: Icon(Icons.person_search_rounded, color: AppColors.accent),
              title: Text('I am looking for a job', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Candidate'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(UserRole.recruiter),
            child: const ListTile(
              leading: Icon(Icons.apartment_rounded, color: AppColors.accent),
              title: Text('I am hiring', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Company / recruiter'),
            ),
          ),
        ],
      ),
    );
  }

  /// One round of sign-in; asks for a role if the account is new and none was
  /// given. Null means the person closed Google's window or the role question.
  Future<AppUser?> _attempt(UserRole? role) async {
    try {
      return await AuthService.instance.signInWithGoogle(role: role);
    } on GoogleSignInNeedsRole {
      final chosen = await _askRole();
      if (chosen == null) return null;
      return AuthService.instance.signInWithGoogle(role: chosen);
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final user = await _attempt(widget.role);
      if (user == null || !mounted) return;
      widget.onSignedIn?.call();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final notSetUp = e.code == 'operation-not-allowed' || e.code == 'unauthorized-domain';
      AppToast.error(
        'Google sign-in did not work',
        description: notSetUp ? 'Google sign-in is not turned on for this app yet.' : authErrorMessage(e),
      );
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'GoogleSignInButton: sign-in failed');
      if (!mounted) return;
      AppToast.error('Google sign-in did not work', description: 'Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Row(
          children: [
            Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
            ),
            Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: (_busy || !widget.enabled) ? null : _signIn,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
              : const _GoogleMark(),
          label: Text(_busy ? 'Signing in...' : 'Continue with Google'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            foregroundColor: AppColors.textPrimary,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }
}

/// A simple "G" in Google's blue, so the button needs no image asset.
class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        'G',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: AppColors.googleBlue, height: 1),
      ),
    );
  }
}
