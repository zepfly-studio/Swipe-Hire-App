import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import 'auth_error.dart';
import 'dev_otp_banner.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../widgets/app_toast.dart';

const _resendCooldown = Duration(seconds: 45);

/// Shown right after [SignupScreen]'s form is filled in and before the
/// account is actually created -- [AuthService.sendSignupOtp] has already
/// been called for [email] by the time this screen is pushed. Pops `true`
/// once the code is confirmed via [AuthService.verifySignupOtp], which is
/// SignupScreen's signal to go ahead and call [AuthService.signUp]. Used for
/// both candidate and recruiter signups; the role doesn't affect this step.
class OtpVerifyScreen extends StatefulWidget {
  final String email;

  /// The code itself while the backend runs without an email provider
  /// (shown via [DevOtpBanner]); empty once codes are really emailed.
  final String devOtp;
  const OtpVerifyScreen({super.key, required this.email, this.devOtp = ''});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();
  late String _devOtp = widget.devOtp;
  bool _verifying = false;
  bool _resending = false;
  Timer? _cooldownTimer;
  Duration _remaining = _resendCooldown;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _otp.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _remaining = _resendCooldown;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _remaining -= const Duration(seconds: 1));
      if (_remaining <= Duration.zero) timer.cancel();
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _verifying = true);
    try {
      await AuthService.instance.verifySignupOtp(email: widget.email, otp: _otp.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'otp_verify_screen');
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      final otp = await AuthService.instance.sendSignupOtp(widget.email);
      if (!mounted) return;
      setState(() => _devOtp = otp);
      _showMessage('A new code was sent to ${widget.email}.');
      _startCooldown();
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'otp_verify_screen');
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
    final canResend = _remaining <= Duration.zero && !_resending;
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
                    const Text('Verify your email', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                          child: const Icon(Icons.mark_email_read_outlined, color: Colors.white, size: 36),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          "Enter the code we sent you",
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                        ),
                        const SizedBox(height: 8),
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
                            children: [
                              const TextSpan(text: "We've emailed a 6-digit code to "),
                              TextSpan(text: widget.email, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 10),
                          decoration: const InputDecoration(
                            counterText: '',
                            filled: true,
                            fillColor: AppColors.surface,
                            hintText: '••••••',
                            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(14)), borderSide: BorderSide.none),
                          ),
                          validator: (value) {
                            final v = value?.trim() ?? '';
                            if (v.isEmpty) return 'Required';
                            return v.length == 6 ? null : 'Enter the 6-digit code';
                          },
                          onFieldSubmitted: (_) => _verify(),
                        ),
                        const SizedBox(height: 22),
                        FilledButton(
                          onPressed: _verifying ? null : _verify,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _verifying
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Text('Verify & create account'),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: canResend ? _resend : null,
                            child: Text(
                              canResend ? 'Resend code' : 'Resend code in ${_remaining.inSeconds}s',
                            ),
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
