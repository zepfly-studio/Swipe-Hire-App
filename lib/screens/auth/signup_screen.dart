import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../services/auth_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import 'auth_error.dart';
import 'auth_text_field.dart';

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
    setState(() => _loading = true);
    try {
      await AuthService.instance.signUp(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        company: _role == UserRole.recruiter ? _company.text : '',
      );
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
    } catch (_) {
      _showMessage('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
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
                              return value.length < 6 ? 'At least 6 characters' : null;
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
                        const SizedBox(height: 26),
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
