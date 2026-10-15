import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import 'auth_error.dart';
import 'auth_text_field.dart';
import 'dev_otp_banner.dart';
import '../../widgets/app_toast.dart';

/// Second step of "Forgot password?" on [LoginScreen] --
/// [AuthService.sendPasswordReset] has already been called for [email] by
/// the time this is pushed. Pops `true` once [AuthService.resetPassword]
/// accepts the code and the new password.
class ResetPasswordScreen extends StatefulWidget {
  final String email;
  final String devOtp;
  const ResetPasswordScreen({super.key, required this.email, this.devOtp = ''});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  late String _devOtp = widget.devOtp;
  bool _submitting = false;
  bool _resending = false;
  bool _obscure = true;

  @override
  void dispose() {
    _otp.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await AuthService.instance.resetPassword(email: widget.email, otp: _otp.text, newPassword: _password.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'reset_password_screen');
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final otp = await AuthService.instance.sendPasswordReset(widget.email);
      if (!mounted) return;
      setState(() => _devOtp = otp);
      _showMessage('A new code was sent to ${widget.email}.');
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'reset_password_screen');
      _showMessage('Could not resend the code. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _resending = false);
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Text('Reset password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: const Icon(Icons.lock_reset_rounded, color: AppColors.onPrimary, size: 36),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Enter the code and a new password',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
                            children: [
                              const TextSpan(text: "We've emailed a 6-digit code to "),
                              TextSpan(
                                text: widget.email,
                                style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                              const TextSpan(text: '. It expires in 10 minutes.'),
                            ],
                          ),
                        ),
                        DevOtpBanner(otp: _devOtp),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _otp,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          textAlign: TextAlign.center,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                          decoration: const InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.surface,
                            hintText: '••••••',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.all(Radius.circular(14)),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return 'Required';
                            return v.length == 6 ? null : 'Enter the 6-digit code';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: authFieldDecoration('New password', Icons.lock_outline).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Required';
                            return value.length < 8 ? 'At least 8 characters' : null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _confirmPassword,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          style: const TextStyle(color: AppColors.textPrimary),
                          decoration: authFieldDecoration('Confirm new password', Icons.lock_outline),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Required';
                            return value != _password.text ? 'Passwords do not match' : null;
                          },
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _submitting ? null : _submit,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary))
                              : const Text('Reset password'),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: _resending ? null : _resend,
                            child: const Text('Resend code'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
