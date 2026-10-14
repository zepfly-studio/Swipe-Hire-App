import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:sonner_toast/sonner_toast.dart';
import '../theme/app_theme.dart';

/// What a toast is about; decides its icon and accent colour.
enum ToastKind { success, error, warning, info, task, interview, offer, message }

/// The icon and colour a kind is drawn with -- shared with the inbox so a
/// notification looks the same in the toast and in the list.
({IconData icon, Color color}) toastStyleOf(ToastKind kind) => switch (kind) {
      ToastKind.success => (icon: Icons.check_circle_rounded, color: AppColors.like),
      ToastKind.error => (icon: Icons.error_rounded, color: AppColors.reject),
      ToastKind.warning => (icon: Icons.warning_amber_rounded, color: AppColors.warning),
      ToastKind.info => (icon: Icons.info_rounded, color: AppColors.info),
      ToastKind.task => (icon: Icons.assignment_rounded, color: AppColors.accent),
      ToastKind.interview => (icon: Icons.event_available_rounded, color: AppColors.warning),
      ToastKind.offer => (icon: Icons.card_giftcard_rounded, color: AppColors.like),
      ToastKind.message => (icon: Icons.chat_bubble_rounded, color: AppColors.accentAlt),
    };

/// Which kind a backend notification `type` is drawn as.
ToastKind toastKindForType(String? type) => switch (type) {
      'task' || 'task_reminder' || 'task_review' || 'task_submitted' || 'review_reminder' || 'taskAssigned' || 'taskSubmitted' =>
        ToastKind.task,
      'interviewScheduled' ||
      'interview' ||
      'interview_reminder' ||
      'interview_confirmed' ||
      'interview_reschedule' =>
        ToastKind.interview,
      'offered' || 'hired' || 'offer_accepted' => ToastKind.offer,
      'chat_message' => ToastKind.message,
      'rejected' || 'withdrawn' || 'offer_declined' => ToastKind.warning,
      _ => ToastKind.info,
    };

/// Every in-app notification in SwipeHire goes through here: form feedback
/// ("Profile saved"), errors, and the notifications that arrive while the
/// app is open (a new task, an interview, a chat message). It draws one
/// consistent card on top of [sonner_toast]'s stacking, swipe-to-dismiss and
/// hover-to-expand behaviour.
///
/// Call it from anywhere -- no BuildContext needed. The overlay is mounted
/// once, by [AppToastHost.builder] in `MaterialApp.builder`; before that
/// exists (or in a test that doesn't mount it) calls are silently ignored.
class AppToast {
  AppToast._();

  static final Map<String, DateTime> _recent = {};

  /// Same message twice within this window is shown once, so a failing
  /// background refresh can't stack ten identical toasts.
  static const Duration _dedupeWindow = Duration(seconds: 2);

  /// sonner_toast builds each toast's id from the clock in microseconds, so
  /// two toasts created in the same instant share an id and one vanishes.
  /// Before each toast we wait (a few microseconds at most, up to a
  /// millisecond on the web) until the clock has moved past the previous
  /// toast's id.
  static int _lastToastMicros = 0;

  static void _emit(void Function() show) {
    while (DateTime.now().microsecondsSinceEpoch <= _lastToastMicros) {}
    show();
    _lastToastMicros = DateTime.now().microsecondsSinceEpoch;
  }

  static void success(String title, {String? description, Duration? duration}) =>
      _show(ToastKind.success, title, description, duration);

  static void error(String title, {String? description, Duration? duration}) =>
      _show(ToastKind.error, title, description, duration ?? const Duration(seconds: 5));

  static void warning(String title, {String? description, Duration? duration}) =>
      _show(ToastKind.warning, title, description, duration);

  static void info(String title, {String? description, Duration? duration}) =>
      _show(ToastKind.info, title, description, duration);

  /// For form helpers that carry an `isError` flag.
  static void message(String text, {bool isError = false}) =>
      isError ? error(text) : success(text);

  /// A toast with one button, e.g. "Added to wishlist" + UNDO.
  static void action(
    String title, {
    String? description,
    required String actionLabel,
    required VoidCallback onAction,
    ToastKind kind = ToastKind.info,
    Duration duration = const Duration(seconds: 5),
  }) =>
      _show(kind, title, description, duration, actionLabel: actionLabel, onAction: onAction);

  /// A notification that arrived while the app is open. [type] is the
  /// `type`/`status` the backend puts on pushes and in-app events.
  static void notification({
    required String title,
    String? body,
    String? type,
    VoidCallback? onTap,
  }) {
    _show(toastKindForType(type), title, body, const Duration(seconds: 7), onTap: onTap);
  }

  static void _show(
    ToastKind kind,
    String title,
    String? description,
    Duration? duration, {
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
  }) {
    final text = title.trim();
    if (text.isEmpty) return;

    final key = '${kind.name}|$text|${description ?? ''}';
    final now = DateTime.now();
    final last = _recent[key];
    if (last != null && now.difference(last) < _dedupeWindow) return;
    _recent[key] = now;
    _recent.removeWhere((_, t) => now.difference(t) > const Duration(seconds: 30));

    _emit(() => Sonner.toast(
          duration: duration ?? const Duration(milliseconds: 3500),
          builder: (context, dismiss) => _ToastCard(
            kind: kind,
            title: text,
            description: description,
            actionLabel: actionLabel,
            onAction: onAction == null
                ? null
                : () {
                    onAction();
                    dismiss();
                  },
            onTap: onTap == null
                ? null
                : () {
                    onTap();
                    dismiss();
                  },
            onClose: dismiss,
          ),
        ));
  }
}

/// Mounts the toast overlay above the whole app (above dialogs and bottom
/// sheets too). Use as `MaterialApp(builder: AppToastHost.builder)`.
class AppToastHost {
  AppToastHost._();

  static const double _maxWidth = 420;

  static Widget builder(BuildContext context, Widget? child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth - 24, _maxWidth).clamp(120.0, _maxWidth);
        final top = MediaQuery.paddingOf(context).top;
        return Stack(
          fit: StackFit.expand,
          children: [
            child ?? const SizedBox.shrink(),
            SonnerOverlay(
              key: Sonner.overlayKey,
              config: SonnerConfig(
                alignment: Alignment.topCenter,
                width: width,
                outerPadding: EdgeInsets.only(top: top + 10),
                maxVisibleToasts: 3,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ToastCard extends StatelessWidget {
  final ToastKind kind;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final VoidCallback onClose;

  const _ToastCard({
    required this.kind,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final style = toastStyleOf(kind);
    final icon = style.icon;
    final color = style.color;
    final hasDescription = description != null && description!.trim().isNotEmpty;

    return Semantics(
      liveRegion: true,
      label: hasDescription ? '$title. $description' : title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF15151F).withValues(alpha: 0.12), blurRadius: 22, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            crossAxisAlignment: hasDescription ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3),
                    ),
                    if (hasDescription) ...[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.35),
                      ),
                    ],
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: Text(actionLabel!, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              // No IconButton/tooltip here: the toast overlay sits above the
              // Navigator, and tooltips need an Overlay ancestor.
              Semantics(
                button: true,
                label: 'Dismiss',
                child: InkResponse(
                  onTap: onClose,
                  radius: 20,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.close_rounded, size: 18, color: AppColors.textTertiary),
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
