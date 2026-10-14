import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/error_reporter.dart';
import '../theme/app_theme.dart';
import 'app_toast.dart';

/// "Email me important updates": turns the emails that go with notifications
/// (task assigned, interview scheduled, offers...) on or off. Saves the
/// moment it is switched, and puts the switch back if that fails.
class EmailToggleTile extends StatefulWidget {
  final bool initialValue;
  const EmailToggleTile({super.key, required this.initialValue});

  @override
  State<EmailToggleTile> createState() => _EmailToggleTileState();
}

class _EmailToggleTileState extends State<EmailToggleTile> {
  late bool _value = widget.initialValue;
  bool _saving = false;

  @override
  void didUpdateWidget(EmailToggleTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The profile finished loading after this was first drawn.
    if (!_saving && oldWidget.initialValue != widget.initialValue) _value = widget.initialValue;
  }

  Future<void> _set(bool enabled) async {
    final previous = _value;
    setState(() {
      _value = enabled;
      _saving = true;
    });
    try {
      await AuthService.instance.setEmailNotifications(enabled);
      if (!mounted) return;
      AppToast.success(
        enabled ? 'Email updates on' : 'Email updates off',
        description: enabled ? 'We will email you about important changes.' : 'You will still see everything in the app.',
      );
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'EmailToggleTile: save failed');
      if (!mounted) return;
      setState(() => _value = previous);
      AppToast.error('Could not change that', description: 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // A Material (not a decorated box) so the tile's ink and background show.
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SwitchListTile(
        value: _value,
        onChanged: _saving ? null : _set,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        secondary: const Icon(Icons.mark_email_unread_outlined, color: AppColors.accentAlt, size: 20),
        title: const Text('Email me important updates', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: const Text('Tasks, interviews and offers', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ),
    );
  }
}
