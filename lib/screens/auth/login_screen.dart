import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import 'auth_error.dart';
import 'auth_text_field.dart';
import 'google_sign_in_button.dart';
import 'reset_password_screen.dart';
import 'signup_screen.dart';
import '../../widgets/app_toast.dart';

/// Email/password sign-in. On success, [AuthService.authStateChanges] fires
/// and [AuthGate] takes over navigation -- this screen never has to know
/// where to go next.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final profile = await AuthService.instance.signIn(email: _email.text, password: _password.text);
      AnalyticsService.instance.logLogin(role: profile.role.value);
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'LoginScreen: sign-in failed');
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    if (_email.text.trim().isEmpty) {
      _showMessage('Enter your email above first, then tap "Forgot password?".', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final devOtp = await AuthService.instance.sendPasswordReset(_email.text);
      if (!mounted) return;
      setState(() => _loading = false);
      final reset = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(email: _email.text.trim(), devOtp: devOtp)),
      );
      if (reset == true) _showMessage('Password updated. Log in with your new password.');
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'LoginScreen: password reset failed');
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    AppToast.message(message, isError: isError);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FadeInUp(child: _buildLogo()),
                    const SizedBox(height: 36),
                    FadeInUp(
                      delay: const Duration(milliseconds: 60),
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: authFieldDecoration('Email', Icons.email_outlined),
                        validator: emailValidator,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeInUp(
                      delay: const Duration(milliseconds: 100),
                      child: TextFormField(
                        controller: _password,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _submit(),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: authFieldDecoration('Password', Icons.lock_outline).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                        validator: requiredValidator,
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _forgotPassword,
                        child: const Text('Forgot password?', style: TextStyle(color: AppColors.accentAlt)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FadeInUp(
                      delay: const Duration(milliseconds: 140),
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _loading
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : const Text('Log In'),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FadeInUp(
                      delay: const Duration(milliseconds: 170),
                      child: GoogleSignInButton(enabled: !_loading),
                    ),
                    const SizedBox(height: 22),
                    FadeInUp(
                      delay: const Duration(milliseconds: 180),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Don't have an account? ", style: TextStyle(color: AppColors.textSecondary)),
                          GestureDetector(
                            onTap: _loading
                                ? null
                                : () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => const SignupScreen()),
                                    ),
                            child: const Text(
                              'Sign up',
                              style: TextStyle(color: AppColors.accentAlt, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildLogo() {
    return Column(
      children: [
        Image.asset('assets/images/logo_full.png', width: 280, filterQuality: FilterQuality.high),
        const SizedBox(height: 18),
        const Text('Welcome back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Log in to SwipeHire', style: TextStyle(color: AppColors.textSecondary)),
      ],
    );
  }
}
