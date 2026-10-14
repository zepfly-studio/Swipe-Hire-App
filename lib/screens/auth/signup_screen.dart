import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../legal/privacy_policy_screen.dart';
import '../legal/terms_of_service_screen.dart';
import 'auth_error.dart';
import 'auth_text_field.dart';
import 'google_sign_in_button.dart';
import 'otp_verify_screen.dart';
import '../../widgets/app_toast.dart';

/// Account creation. The first thing a new user picks is their role --
/// [UserRole.candidate] (looking for a job) or [UserRole.recruiter] (a
/// company/person hiring) -- which permanently decides which experience
/// [AuthGate] routes them into after this.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _company = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  UserRole _role = UserRole.recruiter;
  bool _loading = false;
  bool _obscure = true;
  bool _agreedToTerms = false;

  @override
  void dispose() {
    _name.dispose();
    _company.dispose();
    _email.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      _showMessage('Please agree to the Terms & Privacy Policy to continue.', isError: true);
      return;
    }
    setState(() => _loading = true);
    try {
      // Email OTP gate -- both roles go through the same step, since it
      // only verifies the email address, not anything role-specific.
      final devOtp = await AuthService.instance.sendSignupOtp(_email.text);
      if (!mounted) return;
      setState(() => _loading = false);
      final verified = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => OtpVerifyScreen(email: _email.text.trim(), devOtp: devOtp)),
      );
      if (verified != true || !mounted) return;
      setState(() => _loading = true);

      await AuthService.instance.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        company: _role == UserRole.recruiter ? _company.text : '',
      );
      AnalyticsService.instance.logSignUp(role: _role.value);
      AnalyticsService.instance.setUserRole(_role.value);
      if (_role == UserRole.recruiter) {
        // Pre-fill the recruiter's editable profile tab so it isn't blank
        // the first time they open it.
        await RecruiterProfileService.instance.save(
          name: _name.text.trim(),
          designation: '',
          company: _company.text.trim(),
          email: _email.text.trim(),
          phone: '',
        );
      }
      if (!mounted) return;
      _showMessage('Account created!');
      await Future.delayed(const Duration(milliseconds: 500));
      // This screen was pushed on top of AuthGate via Navigator.push, so
      // AuthGate reacting to the new sign-in (and swapping in
      // CompleteProfileScreen underneath) doesn't make it visible on its
      // own -- this screen is still covering it until popped.
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      _showMessage(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'SignupScreen: sign-up failed');
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    const Text('Create account', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
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
                        const Text(
                          "I'm here to...",
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                        const SizedBox(height: 10),
                        FadeInUp(child: _buildRoleSelector()),
                        const SizedBox(height: 22),
                        FadeInUp(
                          delay: const Duration(milliseconds: 40),
                          child: TextFormField(
                            controller: _name,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: authFieldDecoration('Full name', Icons.person_outline),
                            validator: requiredValidator,
                          ),
                        ),
                        if (_role == UserRole.recruiter) ...[
                          const SizedBox(height: 14),
                          FadeInUp(
                            delay: const Duration(milliseconds: 60),
                            child: TextFormField(
                              controller: _company,
                              textInputAction: TextInputAction.next,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: authFieldDecoration('Company name', Icons.apartment_rounded),
                              validator: requiredValidator,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 80),
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
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: authFieldDecoration('Password', Icons.lock_outline).copyWith(
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
                        ),
                        const SizedBox(height: 14),
                        FadeInUp(
                          delay: const Duration(milliseconds: 120),
                          child: TextFormField(
                            controller: _confirmPassword,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            style: const TextStyle(color: AppColors.textPrimary),
                            decoration: authFieldDecoration('Confirm password', Icons.lock_outline),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Required';
                              return value != _password.text ? 'Passwords do not match' : null;
                            },
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeInUp(
                          delay: const Duration(milliseconds: 150),
                          child: _buildTermsCheckbox(),
                        ),
                        const SizedBox(height: 18),
                        FadeInUp(
                          delay: const Duration(milliseconds: 160),
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
                                : const Text('Create account'),
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeInUp(
                          delay: const Duration(milliseconds: 180),
                          child: GoogleSignInButton(
                            role: _role,
                            enabled: !_loading,
                            // Signup was pushed on top of AuthGate; close it so
                            // the screen AuthGate shows for the user is visible.
                            onSignedIn: () {
                              if (mounted) Navigator.of(context).pop();
                            },
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

  Widget _buildTermsCheckbox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _agreedToTerms,
            onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
            child: RichText(
              key: const Key('signup_terms_richtext'),
              text: TextSpan(
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  TextSpan(
                    text: 'Terms of Service',
                    style: const TextStyle(color: AppColors.accentAlt, fontWeight: FontWeight.w700),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const TermsOfServiceScreen())),
                  ),
                  const TextSpan(text: ' and '),
                  TextSpan(
                    text: 'Privacy Policy',
                    style: const TextStyle(color: AppColors.accentAlt, fontWeight: FontWeight.w700),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen())),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoleSelector() {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            icon: Icons.apartment_rounded,
            title: 'Hire talent',
            subtitle: 'Company / recruiter',
            selected: _role == UserRole.recruiter,
            onTap: () => setState(() => _role = UserRole.recruiter),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            icon: Icons.person_search_rounded,
            title: 'Find a job',
            subtitle: 'Candidate',
            selected: _role == UserRole.candidate,
            onTap: () => setState(() => _role = UserRole.candidate),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: selected ? AppColors.accentAlt : AppColors.border, width: selected ? 1.6 : 1),
          ),
          child: Column(
            children: [
              Icon(icon, color: selected ? AppColors.accentAlt : AppColors.textSecondary, size: 26),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5), textAlign: TextAlign.center),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11.5), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
