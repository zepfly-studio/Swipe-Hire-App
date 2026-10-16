import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/candidate.dart';
import '../../../services/hiring_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_nav.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/page_transitions.dart';
import '../../../widgets/swipe_card.dart';
import '../../resume_screen.dart';
import '../plans/plan_cards.dart';
import '../plans/plans_screen.dart';
import '../wishlist_screen.dart';
import 'confetti_burst.dart';
import 'filters_sheet.dart';
import 'swipe_controller.dart';
import 'swipe_decision.dart';

/// The company's main screen (spec C2): filters, saved searches, a 3-card
/// swipe stack and the action bar. Swiping is locked until a filter is set;
/// every filter applied is saved in the Filters tab.
class SwipeScreen extends StatefulWidget {
  /// Apply this saved search on start.
  final String? initialSearchId;

  const SwipeScreen({super.key, this.initialSearchId});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> with TickerProviderStateMixin {
  late final SwipeController _c;
  late final AnimationController _exit;
  late final AnimationController _enter;
  late final AnimationController _spring;

  double _dx = 0;
  Candidate? _ghost;
  SwipeDir _ghostDir = SwipeDir.right;
  double _ghostStartDx = 0;
  double _enterFrom = 0;

  ({String name, String email})? _flash;
  Timer? _flashTimer;

  @override
  void initState() {
    super.initState();
    _c = SwipeController(service: HiringService.instance)
      ..onEvent = _onEvent
      ..addListener(_rebuild);
    _exit = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 380))..value = 1;
    _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(() {
        if (mounted) setState(() => _dx = _springFrom * (1 - Curves.easeOut.transform(_spring.value)));
      });

    final pendingSearch = AppNav.swipeSearchId.value;
    AppNav.swipeSearchId.value = null;
    _c.init(searchId: pendingSearch ?? widget.initialSearchId);

    HiringService.savedFiltersChanged.addListener(_onSavedFiltersChanged);
    AppNav.swipeSearchId.addListener(_onSearchRequest);
  }

  double _springFrom = 0;

  @override
  void dispose() {
    HiringService.savedFiltersChanged.removeListener(_onSavedFiltersChanged);
    AppNav.swipeSearchId.removeListener(_onSearchRequest);
    _flashTimer?.cancel();
    _exit.dispose();
    _enter.dispose();
    _spring.dispose();
    _c.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onSavedFiltersChanged() {
    _c.reloadSearches();
    _c.reloadActiveFilter();
  }

  void _onSearchRequest() {
    final id = AppNav.swipeSearchId.value;
    if (id == null) return;
    AppNav.swipeSearchId.value = null;
    _c.applySearchById(id);
  }

  // -- events -------------------------------------------------------------

  void _onEvent(SwipeEvent e) {
    if (!mounted) return;
    switch (e.type) {
      case SwipeEventType.paywall:
        showPaywall(context);
      case SwipeEventType.toast:
        AppToast.success(e.message);
      case SwipeEventType.errorToast:
        AppToast.error(e.message, duration: e.duration);
      case SwipeEventType.shortlisted:
        final name = (e.candidate?.name ?? '').trim().split(RegExp(r'\s+')).first;
        _flashTimer?.cancel();
        setState(() => _flash = (name: name, email: e.email));
        _flashTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _flash = null);
        });
      case SwipeEventType.undone:
        _enterFrom = e.action == 'right' ? 1 : -1;
        _enter.forward(from: 0);
        AppToast.success(e.message, duration: const Duration(seconds: 4));
    }
  }

  // -- gestures -----------------------------------------------------------

  void _onDragUpdate(DragUpdateDetails d) {
    if (_exit.isAnimating) return;
    _spring.stop();
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    final dir = swipeDecision(dx: _dx, velocityX: d.velocity.pixelsPerSecond.dx);
    if (dir == null) {
      _springFrom = _dx;
      _spring.forward(from: 0);
    } else {
      _commit(dir);
    }
  }

  void _commit(SwipeDir dir) {
    final card = _c.top;
    if (card == null) return;
    if (_c.balance <= 0) {
      // The controller opens the paywall; the card stays.
      _springFrom = _dx;
      _spring.forward(from: 0);
      _c.swipe(dir);
      return;
    }
    setState(() {
      _ghost = card;
      _ghostDir = dir;
      _ghostStartDx = _dx;
      _dx = 0;
    });
    _exit.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _ghost = null);
    });
    _c.swipe(dir);
  }

  void _openResume(Candidate c) => pushSmooth(context, ResumeScreen(candidate: c));

  Future<void> _openFilters() async {
    final next = await showFiltersSheet(context, initial: _c.filters, controller: _c);
    if (next != null) await _c.setFilters(next);
  }

  // -- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _FilterRow(controller: _c, onOpenFilters: _openFilters),
            if (_c.searches.isNotEmpty) _SearchChips(controller: _c),
            Expanded(child: _cardArea()),
            if (_c.viewState == SwipeViewState.ready) _actionBar(),
          ],
        ),
        if (_flash != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Stack(
                children: [
                  const ConfettiBurst(),
                  Align(
                    alignment: const Alignment(0, -0.35),
                    child: _ShortlistFlash(name: _flash!.name, email: _flash!.email),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _cardArea() {
    switch (_c.viewState) {
      case SwipeViewState.loading:
        return const Center(child: CircularProgressIndicator());
      case SwipeViewState.needsFilter:
        return _EmptyState(
          icon: Icons.tune_rounded,
          title: 'Add a filter to see candidates',
          text: 'Choose who you are looking for (city, experience, skills...). '
              'No candidates are shown until you apply a filter.',
          primaryLabel: 'Add filter',
          onPrimary: _openFilters,
        );
      case SwipeViewState.error:
        return _EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load candidates',
          text: _c.feedError ?? 'Please try again.',
          primaryLabel: 'Try again',
          onPrimary: _c.retry,
        );
      case SwipeViewState.outOfSwipes:
        return _EmptyState(
          icon: Icons.bolt_rounded,
          title: "You're out of swipes",
          text: 'Get more swipes to keep discovering great candidates.',
          primaryLabel: 'See plans',
          onPrimary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlansScreen())),
        );
      case SwipeViewState.noFilterMatch:
        return _EmptyState(
          icon: Icons.filter_alt_off_outlined,
          title: 'No more candidates for these filters',
          text: 'Try widening them, or review your wishlist.',
          secondaryLabel: 'Open wishlist',
          onSecondary: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WishlistScreen())),
          primaryLabel: 'Edit filters',
          onPrimary: _openFilters,
        );
      case SwipeViewState.ready:
        return _stack();
    }
  }

  Widget _stack() {
    final top = _c.top!;
    final stack = _c.stack;
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth;
        final children = <Widget>[];

        // Cards behind (depth 2 then 1): decorated placeholders peeking out.
        for (final depth in [2, 1]) {
          if (stack.length > depth) {
            children.add(Positioned(
              left: 14.0 * depth,
              right: 14.0 * depth,
              top: 8,
              bottom: 28 - 12.0 * depth,
              child: _BehindCard(name: stack[depth].name),
            ));
          }
        }

        // The card that was just swiped, flying off.
        final ghost = _ghost;
        if (ghost != null) {
          children.add(Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 28,
            child: AnimatedBuilder(
              animation: _exit,
              builder: (context, child) {
                final t = Curves.easeIn.transform(_exit.value);
                final target = (_ghostDir == SwipeDir.right ? 1 : -1) * width * 1.4;
                final x = _ghostStartDx + (target - _ghostStartDx) * t;
                return Opacity(
                  opacity: (1 - t * 0.6).clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(x, 0),
                    child: Transform.rotate(angle: swipeRotation(x), child: child),
                  ),
                );
              },
              child: IgnorePointer(
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: SwipeCardView(candidate: ghost, isTop: false),
                ),
              ),
            ),
          ));
        }

        // The top card: drags sideways to pass / shortlist; swiping the whole
        // card up scrolls it: resume, skills, then the intro video.
        children.add(Positioned(
          left: 0,
          right: 0,
          top: 0,
          bottom: 28,
          child: GestureDetector(
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            child: AnimatedBuilder(
              animation: _enter,
              builder: (context, child) {
                final fly = _enterFrom * width * (1 - Curves.easeOutCubic.transform(_enter.value));
                final x = _dx + fly;
                return Transform.translate(
                  offset: Offset(x, 0),
                  child: Transform.rotate(angle: swipeRotation(x), child: child),
                );
              },
              child: TweenAnimationBuilder<double>(
                key: ValueKey('top-${top.id}'),
                tween: Tween(begin: 0.85, end: 1),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, alignment: Alignment.topCenter, child: child),
                child: Stack(
                  children: [
                    SingleChildScrollView(
                      key: ValueKey('scroll-${top.id}'),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: SwipeCardView(
                        candidate: top,
                        viewportHeight: box.maxHeight - 28,
                        onOpenResume: () => _openResume(top),
                        onToggleWishlist: () => _c.toggleWishlist(top),
                      ),
                    ),
                    if (_dx != 0) ...[
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: (_dx > 0 ? AppColors.like : AppColors.reject)
                                    .withValues(alpha: swipeTintOpacity(_dx)),
                                borderRadius: BorderRadius.circular(22),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 36,
                        left: _dx > 0 ? 32 : null,
                        right: _dx < 0 ? 32 : null,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: swipeStampOpacity(_dx),
                            child: _Stamp(
                              label: _dx > 0 ? 'SHORTLIST' : 'PASS',
                              color: _dx > 0 ? AppColors.like : AppColors.reject,
                              angle: _dx > 0 ? -12 : 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ));

        return Stack(clipBehavior: Clip.none, children: children);
      },
    );
  }

  Widget _actionBar() {
    final top = _c.top;
    final enabled = top != null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow(),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundButton(
                tooltip: 'Undo last swipe',
                icon: Icons.undo_rounded,
                color: AppColors.warning,
                size: 48,
                onTap: _c.canUndo ? _c.undo : null,
              ),
              const SizedBox(width: 12),
              _RoundButton(
                tooltip: 'Pass',
                icon: Icons.close_rounded,
                color: AppColors.reject,
                size: 64,
                onTap: enabled ? () => _commit(SwipeDir.left) : null,
              ),
              const SizedBox(width: 12),
              _RoundButton(
                tooltip: top?.wishlisted == true ? 'Remove from wishlist' : 'Add to wishlist',
                icon: top?.wishlisted == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: AppColors.wishlist,
                size: 48,
                filled: top?.wishlisted == true,
                onTap: enabled ? () => _c.toggleWishlist(top) : null,
              ),
              const SizedBox(width: 12),
              _RoundButton(
                tooltip: 'Shortlist',
                icon: Icons.verified_rounded,
                color: AppColors.like,
                size: 64,
                onTap: enabled ? () => _commit(SwipeDir.right) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- pieces ---------------------------------------------------------------

class _FilterRow extends StatelessWidget {
  final SwipeController controller;
  final VoidCallback onOpenFilters;
  const _FilterRow({required this.controller, required this.onOpenFilters});

  @override
  Widget build(BuildContext context) {
    final count = controller.filters.activeCount;
    final locked = controller.viewState == SwipeViewState.needsFilter;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: onOpenFilters,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 40),
              side: BorderSide(color: count > 0 || locked ? AppColors.primary : AppColors.border),
            ),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(locked ? 'Set filters' : 'Filters'),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
                    child: Text('$count', style: const TextStyle(color: AppColors.onPrimary, fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (count > 0)
            TextButton(onPressed: controller.clearFilters, child: const Text('Clear filters'))
          else
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const WishlistScreen())),
              icon: const Icon(Icons.favorite_border_rounded, size: 18),
              label: const Text('Wishlist'),
            ),
        ],
      ),
    );
  }
}

class _SearchChips extends StatelessWidget {
  final SwipeController controller;
  const _SearchChips({required this.controller});

  @override
  Widget build(BuildContext context) {
    final items = controller.searches.take(6).toList();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) => ActionChip(
          avatar: const Icon(Icons.bookmark_border_rounded, size: 16),
          label: Text(items[i].name),
          onPressed: () => controller.applySavedSearch(items[i]),
        ),
      ),
    );
  }
}

class _BehindCard extends StatelessWidget {
  final String name;
  const _BehindCard({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(opacity: 0.6),
      ),
      alignment: Alignment.topCenter,
      padding: const EdgeInsets.only(top: 18),
      child: Text(
        name,
        style: const TextStyle(color: AppColors.textTertiary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  final String label;
  final Color color;
  final double angle;
  const _Stamp({required this.label, required this.color, required this.angle});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.onPrimary.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: 3),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 26, letterSpacing: 1.5),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final double size;
  final bool filled;
  final VoidCallback? onTap;

  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.size,
    this.filled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = enabled ? color : AppColors.textTertiary;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        enabled: enabled,
        child: Material(
          color: filled && enabled ? c.withValues(alpha: 0.16) : c.withValues(alpha: 0.09),
          shape: CircleBorder(side: BorderSide(color: c.withValues(alpha: 0.35), width: 1.5)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: c, size: size * 0.5),
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortlistFlash extends StatelessWidget {
  final String name;
  final String email;
  const _ShortlistFlash({required this.name, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 32),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.like.withValues(alpha: 0.5)),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '✓ ${name.isEmpty ? 'Candidate' : name} shortlisted!',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.likeText),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(email, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.text,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                if (secondaryLabel != null)
                  OutlinedButton(
                    onPressed: onSecondary,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(120, 46)),
                    child: Text(secondaryLabel!),
                  ),
                if (primaryLabel != null)
                  FilledButton(
                    onPressed: onPrimary,
                    style: FilledButton.styleFrom(minimumSize: const Size(120, 46)),
                    child: Text(primaryLabel!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
