import 'package:flutter/material.dart';

import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/inputs/form_blocks.dart';

/// Client-side checks for the change-password form. Keys are the form fields
/// (`current`, `next`, `confirm`); an empty map means the form can be sent.
Map<String, String> validatePasswordChange({
  required String current,
  required String next,
  required String confirm,
}) {
  final errors = <String, String>{};
  if (current.isEmpty) errors['current'] = 'Enter your current password';
  if (next.length < 8) errors['next'] = 'New password must be at least 8 characters';
  if (confirm != next) errors['confirm'] = 'Passwords do not match';
  return errors;
}

/// Account security (both roles): change the password and sign out of every
/// device.
class AccountSecurityScreen extends StatefulWidget {
  /// For tests; the app uses [AuthService.instance].
  final AuthService? authService;

  const AccountSecurityScreen({super.key, this.authService});

  @override
  State<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends State<AccountSecurityScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _showCurrent = false;
  bool _showNext = false;
  Map<String, String> _errors = {};
  bool _saving = false;
  bool _loggingOut = false;

  AuthService get _auth => widget.authService ?? AuthService.instance;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (_saving) return;
    final errors = validatePasswordChange(current: _current.text, next: _next.text, confirm: _confirm.text);
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      await _auth.changePassword(current: _current.text, next: _next.text);
      if (!mounted) return;
      _current.clear();
      _next.clear();
      _confirm.clear();
      setState(() => _saving = false);
      AppToast.success('Password changed. Other devices have been logged out.');
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.body['field'];
      setState(() {
        _saving = false;
        if (field == 'current' || field == 'next') {
          _errors = {field as String: e.message};
        }
      });
      if (field != 'current' && field != 'next') {
        AppToast.error('Could not change your password', description: e.message);
      }
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AccountSecurityScreen: change password failed');
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error('Could not change your password', description: 'Check your connection and try again.');
    }
  }

  Future<void> _logoutAll() async {
    if (_loggingOut) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out of all devices'),
        content: const Text('Log out of Swipe Hire on all devices, including this one?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out', style: TextStyle(color: AppColors.reject)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final navigator = Navigator.of(context);
    setState(() => _loggingOut = true);
    try {
      await _auth.logoutAllDevices();
      // Signed out: drop every pushed screen so the login screen shows.
      navigator.popUntil((route) => route.isFirst);
      AppToast.success('Logged out of all devices');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      AppToast.error('Could not log out of all devices', description: e.message);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'AccountSecurityScreen: logout all failed');
      if (!mounted) return;
      setState(() => _loggingOut = false);
      AppToast.error('Could not log out of all devices', description: 'Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      appBar: AppBar(title: const Text('Account security')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            const Text('Change password', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'Changing your password logs you out on your other devices.',
              style: TextStyle(color: AppColors.textSecondary, height: 1.4, fontSize: 13),
            ),
            const SizedBox(height: 16),
            _passwordField(
              label: 'Current password',
              field: 'current',
              controller: _current,
              visible: _showCurrent,
              onToggle: () => setState(() => _showCurrent = !_showCurrent),
              autofill: AutofillHints.password,
            ),
            const SizedBox(height: 14),
            _passwordField(
              label: 'New password',
              field: 'next',
              controller: _next,
              visible: _showNext,
              onToggle: () => setState(() => _showNext = !_showNext),
              autofill: AutofillHints.newPassword,
              hint: 'At least 8 characters',
            ),
            const SizedBox(height: 14),
            _passwordField(
              label: 'Confirm new password',
              field: 'confirm',
              controller: _confirm,
              visible: _showNext,
              onToggle: null,
              autofill: AutofillHints.newPassword,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving ? null : _changePassword,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                    )
                  : const Text('Update password'),
            ),
            const SizedBox(height: 32),
            const Divider(height: 1),
            const SizedBox(height: 20),
            const Text(
              'Used Swipe Hire on a shared or lost device?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _loggingOut ? null : _logoutAll,
              icon: const Icon(Icons.devices_other_rounded, color: AppColors.reject),
              label: const Text('Log out of all devices', style: TextStyle(color: AppColors.reject)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                side: const BorderSide(color: AppColors.reject),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordField({
    required String label,
    required String field,
    required TextEditingController controller,
    required bool visible,
    required VoidCallback? onToggle,
    required String autofill,
    String? hint,
  }) {
    return FormFieldBlock(
      label: label,
      error: _errors[field],
      child: TextField(
        key: Key('field-$field'),
        controller: controller,
        obscureText: !visible,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: [autofill],
        decoration: fieldDecoration(
          hintText: hint,
          hasError: _errors.containsKey(field),
          suffix: onToggle == null
              ? null
              : IconButton(
                  tooltip: visible ? 'Hide password' : 'Show password',
                  onPressed: onToggle,
                  icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                ),
        ),
        onChanged: (_) {
          if (_errors.containsKey(field)) setState(() => _errors.remove(field));
        },
      ),
    );
  }
}
