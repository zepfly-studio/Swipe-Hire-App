import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';

/// Shown by [AuthGate] for any signed-in account whose email isn't
/// verified yet. "I've verified" reloads the Firebase user -- since
/// [AuthService.authStateChanges] is backed by `userChanges()`, a reload
/// that actually flips `emailVerified` makes AuthGate rebuild past this
/// screen on its own; no manual navigation needed here.
class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _resending = false;
  bool _checking = false;

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await AuthService.instance.resendVerificationEmail();
      _showMessage('Verification email sent to ${widget.email}');
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'VerifyEmailScreen: resend failed');
      _showMessage('Could not send the email right now. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _checkVerified() async {
    setState(() => _checking = true);
    try {
      await AuthService.instance.reloadUser();
      if (AuthService.instance.currentUser?.emailVerified != true && mounted) {
        _showMessage("Still not verified -- check your inbox (and spam folder).", isError: true);
      }
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'VerifyEmailScreen: reload failed');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.reject : AppColors.surfaceAlt,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: FadeInUp(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: AppColors.accentGradient,
                        borderRadius: BorderRadius.circular(26),
                        boxShadow: [
                          BoxShadow(color: AppColors.accent.withValues(alpha: 0.45), blurRadius: 26, offset: const Offset(0, 10)),
                        ],
                      ),
                      child: const Icon(Icons.mark_email_unread_outlined, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 22),
                    const Text('Verify your email', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 10),
                    Text(
                      "We've sent a verification link to\n${widget.email}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: _checking ? null : _checkVerified,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _checking
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Text("I've verified -- Continue"),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _resending ? null : _resend,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: _resending
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                          : const Text('Resend email'),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () => AuthService.instance.signOut(),
                      child: const Text('Use a different account', style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
