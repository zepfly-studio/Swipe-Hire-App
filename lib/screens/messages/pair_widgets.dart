import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../models/pair/pipeline_stage.dart';
import '../../theme/app_theme.dart';
import '../../widgets/candidate_card_face.dart' show InitialsAvatar;
import '../../widgets/notification_bell.dart';
import '../../widgets/trust_widgets.dart' show StatePill;

/// Round (candidate) or rounded-square (company) avatar with an initials
/// fallback.
class PairAvatar extends StatelessWidget {
  final String name;
  final String url;
  final double size;
  final bool square;
  const PairAvatar({super.key, required this.name, this.url = '', this.size = 44, this.square = false});

  @override
  Widget build(BuildContext context) {
    final radius = square ? BorderRadius.circular(size * 0.28) : BorderRadius.circular(size);
    return ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: size,
        height: size,
        child: url.isEmpty
            ? InitialsAvatar(name: name)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (context, _, _) => InitialsAvatar(name: name),
              ),
      ),
    );
  }
}

/// The coloured pill for a pipeline stage; [candidateView] uses the
/// candidate wording ("Selected", "Closed").
class StagePill extends StatelessWidget {
  final String stage;
  final bool candidateView;
  const StagePill({super.key, required this.stage, this.candidateView = false});

  @override
  Widget build(BuildContext context) {
    return StatePill(
      label: candidateView ? candidateStageLabel(stage) : stageLabel(stage),
      color: stageColor(stage),
    );
  }
}

/// A screen's top row: optional back arrow (when the screen was pushed),
/// title + subtitle, extra [actions] and the notification bell.
class PairHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final bool showBell;
  final VoidCallback? onBack;
  final Widget? badge;

  const PairHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.showBell = true,
    this.onBack,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final back = onBack ?? (canPop ? () => Navigator.of(context).maybePop() : null);
    return Padding(
      padding: EdgeInsets.fromLTRB(back != null ? 4 : 20, 10, 8, 6),
      child: Row(
        children: [
          if (back != null)
            IconButton(onPressed: back, tooltip: 'Back', icon: const Icon(Icons.arrow_back_rounded)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (badge != null) ...[const SizedBox(width: 8), badge!],
                  ],
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.3),
                    ),
                  ),
              ],
            ),
          ),
          ...actions,
          if (showBell) const NotificationBell(),
        ],
      ),
    );
  }
}

/// A count pill next to a title.
class CountPill extends StatelessWidget {
  final int count;
  const CountPill({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$count', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: AppColors.primary)),
    );
  }
}

class PairEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PairEmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 38, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                style: FilledButton.styleFrom(minimumSize: const Size(160, 46)),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PairErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const PairErrorState({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 48, color: AppColors.textSecondary),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(minimumSize: const Size(140, 44)),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline red error text used inside modals.
class InlineError extends StatelessWidget {
  final String text;
  const InlineError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.reject.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.reject.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: const TextStyle(color: AppColors.reject, fontSize: 13, height: 1.3)),
    );
  }
}

/// Opens a rounded bottom sheet that rises above the keyboard.
Future<T?> showPairSheet<T>(BuildContext context, WidgetBuilder builder, {bool full = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * (full ? 0.95 : 0.9)),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: builder(ctx),
    ),
  );
}

/// Standard modal layout: title, subtitle, close button, scrolling [child]
/// and an optional pinned [footer].
class PairSheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? footer;
  const PairSheetFrame({super.key, required this.title, this.subtitle, required this.child, this.footer});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          subtitle!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.3),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: child,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: footer,
          ),
      ],
    );
  }
}
