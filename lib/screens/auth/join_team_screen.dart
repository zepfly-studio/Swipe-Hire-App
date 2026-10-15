import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/team_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/app_toast.dart';
import 'auth_error.dart';
import 'auth_text_field.dart';

/// Joining a company's team with an invite code (or pasted link) and no
/// account yet: step 1 checks the code, step 2 creates the recruiter login.
/// On success [AuthGate] takes over once this screen is popped.
class JoinTeamScreen extends StatefulWidget {
  const JoinTeamScreen({super.key});

  @override
  State<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends State<JoinTeamScreen> {
  final _codeKey = GlobalKey<FormState>();
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _password = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  String? _codeError;

  /// Set once the code checked out (step 2).
  String? _token;
  String _email = '';
  String _company = '';

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    setState(() {
      _code.text = extractInviteToken(text);
      _codeError = null;
    });
  }

  Future<void> _continue() async {
    final token = extractInviteToken(_code.text);
    if (token.isEmpty) {
      setState(() => _codeError = 'Enter your invite code');
      return;
    }
    setState(() {
      _loading = true;
      _codeError = null;
    });
    try {
      final info = await AuthService.instance.inviteInfo(token);
      if (!mounted) return;
      setState(() {
        _token = token;
        _email = (info['email'] as String? ?? '').trim();
        _company = (info['companyName'] as String? ?? '').trim();
      });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _codeError = authErrorMessage(e));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'JoinTeamScreen: invite lookup failed');
      if (mounted) setState(() => _codeError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _join() async {
    final token = _token;
    if (token == null || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await AuthService.instance.acceptInvite(token: token, name: _name.text, password: _password.text);
      if (!mounted) return;
      AppToast.success('Welcome to ${_company.isEmpty ? 'the team' : _company}!');
      // Back to the root route so AuthGate (now signed in) is what shows.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      AppToast.message(authErrorMessage(e), isError: true);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'JoinTeamScreen: accept invite failed');
      AppToast.message('Something went wrong. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
                    const Text('Join a team', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _logo(),
                        const SizedBox(height: 28),
                        if (_token == null) _codeStep() else _detailsStep(),
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

  Widget _logo() {
    return Column(
      children: [
        Image.asset('assets/images/logo_mark.png', width: 88, filterQuality: FilterQuality.high),
        const SizedBox(height: 10),
        const Text(
          'Swipe Hire',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _spinner() => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
      );

  ButtonStyle get _buttonStyle => FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  Widget _codeStep() {
    return Form(
      key: _codeKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Join a team',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Paste the invite code or link your team owner sent you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _loading ? null : _continue(),
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: authFieldDecoration('Invite code', Icons.vpn_key_outlined).copyWith(
              errorText: _codeError,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded, size: 20),
                onPressed: _loading ? null : _paste,
              ),
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loading ? null : _continue,
            style: _buttonStyle,
            child: _loading ? _spinner() : const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _detailsStep() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _company.isEmpty ? 'Join the team' : 'Join $_company',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'as a recruiter · $_email',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          TextFormField(
            initialValue: _email,
            readOnly: true,
            enabled: false,
            style: const TextStyle(color: AppColors.textSecondary),
            decoration: authFieldDecoration('Email', Icons.email_outlined),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _name,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: authFieldDecoration('Your name', Icons.person_outline).copyWith(hintText: 'Your full name'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _password,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _loading ? null : _join(),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: authFieldDecoration('Choose a password', Icons.lock_outline).copyWith(
              hintText: 'At least 8 characters',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            validator: (v) => (v == null || v.length < 8) ? 'Password must be at least 8 characters' : null,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _loading ? null : _join,
            style: _buttonStyle,
            child: _loading ? _spinner() : const Text('Join team'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loading ? null : () => setState(() => _token = null),
            child: const Text('Use a different code', style: TextStyle(color: AppColors.accentAlt)),
          ),
        ],
      ),
    );
  }
}
