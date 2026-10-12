import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/data_export_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import 'login_screen.dart';

/// "Export my data": builds the account's full JSON export and shows it in
/// a dialog with a one-tap copy -- the simplest data-portability option
/// that works identically on every platform (no platform-specific file
/// saving), good enough for a basic privacy-compliance gesture.
Future<void> showExportDataDialog(BuildContext context) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ExportProgressDialog(),
  );

  try {
    final data = await DataExportService.exportMyData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    if (!context.mounted) return;
    Navigator.of(context).pop(); // close the progress dialog
    await showDialog(
      context: context,
      builder: (_) => _ExportResultDialog(json: json),
    );
  } catch (e, stackTrace) {
    ErrorReporter.report(e, stackTrace, reason: 'exportMyData failed');
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not prepare your data export. Please try again.'), backgroundColor: AppColors.reject),
    );
  }
}

class _ExportProgressDialog extends StatelessWidget {
  const _ExportProgressDialog();

  @override
  Widget build(BuildContext context) {
    return const AlertDialog(
      backgroundColor: AppColors.surface,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accentAlt)),
          SizedBox(width: 16),
          Text('Preparing your data...'),
        ],
      ),
    );
  }
}

class _ExportResultDialog extends StatelessWidget {
  final String json;
  const _ExportResultDialog({required this.json});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Your data'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: json));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied to clipboard'), backgroundColor: AppColors.surfaceAlt),
            );
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy'),
        ),
      ],
    );
  }
}

/// "Delete account": confirms, deletes every Firestore doc + the Firebase
/// Auth account itself. Transparently handles the `requires-recent-login`
/// case Firebase Auth throws on an old session by prompting for the
/// password and retrying once.
Future<void> confirmAndDeleteAccount(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Delete your account?'),
      content: const Text(
        'This permanently deletes your profile and account. This cannot be undone.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.reject),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await AuthService.instance.deleteAccount();
  } on FirebaseAuthException catch (e) {
    if (e.code != 'requires-recent-login') {
      if (context.mounted) _showDeleteError(context);
      return;
    }
    if (!context.mounted) return;
    final password = await _promptPassword(context);
    if (password == null || !context.mounted) return;
    try {
      await AuthService.instance.reauthenticateWithPassword(password);
      await AuthService.instance.deleteAccount();
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'deleteAccount retry after reauth failed');
      if (context.mounted) _showDeleteError(context);
      return;
    }
  } catch (e, stackTrace) {
    ErrorReporter.report(e, stackTrace, reason: 'deleteAccount failed');
    if (context.mounted) _showDeleteError(context);
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

void _showDeleteError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not delete your account. Please try again.'), backgroundColor: AppColors.reject),
  );
}

Future<String?> _promptPassword(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Confirm your password'),
      content: TextField(
        controller: controller,
        obscureText: true,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(controller.text), child: const Text('Confirm')),
      ],
    ),
  );
  controller.dispose();
  return (result == null || result.isEmpty) ? null : result;
}
