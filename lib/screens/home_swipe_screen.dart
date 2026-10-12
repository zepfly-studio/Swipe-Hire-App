import 'package:flutter/material.dart';
import '../models/candidate.dart';
import '../services/candidate_service.dart';
import '../services/error_reporter.dart';
import '../services/mock_candidates.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/page_transitions.dart';
import '../widgets/swipeable_candidate_card.dart';
import 'resume_screen.dart';
import 'search_screen.dart';
import 'video_intro_screen.dart';

/// Discover tab: nothing but the full-screen swipe deck, plus a small
/// floating Search icon over the card. Wishlist/Shortlist live in their own
/// bottom-nav tabs (see [RootShell]).
class HomeSwipeScreen extends StatefulWidget {
  final VoidCallback onViewWishlist;

  const HomeSwipeScreen({super.key, required this.onViewWishlist});

  @override
  State<HomeSwipeScreen> createState() => _HomeSwipeScreenState();
}

class _HomeSwipeScreenState extends State<HomeSwipeScreen> {
  List<Candidate> _candidates = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCandidates();
  }

  Future<void> _loadCandidates() async {
    List<Candidate> loaded = [];
    try {
      loaded = await CandidateService.instance.fetchCandidates();
    } catch (e, stackTrace) {
      // Offline, or a permissions/config issue -- fall back to sample data
      // so the app stays fully usable.
      ErrorReporter.report(e, stackTrace, reason: 'HomeSwipeScreen: fetchCandidates failed');
    }
    if (loaded.isEmpty) {
      loaded = mockCandidates();
    }
    loaded = loaded
        .where((c) => !WishlistService.instance.hasBeenSwiped(c.id))
        .toList();

    if (!mounted) return;
    setState(() {
      _candidates = loaded;
      _loading = false;
    });
  }

  /// Right swipe just advances to the next candidate without saving
  /// anything and shows no popup. Left swipe passes on the candidate
  /// (persisted so they don't reappear) and shows an undo snackbar.
  void _handleSwipe(Candidate candidate, SwipeDirection direction) async {
    if (direction == SwipeDirection.left) {
      await WishlistService.instance.reject(candidate);
      if (!mounted) return;
      setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
      _showUndoSnackBar('Passed on ${candidate.name}', candidate);
      return;
    }
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
  }

  void _handleWishlistSelect(Candidate candidate) async {
    await WishlistService.instance.shortlist(candidate);
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
    _showUndoSnackBar('Added ${candidate.name} to wishlist', candidate);
  }

  void _showUndoSnackBar(String message, Candidate candidate) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.surfaceAlt,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'UNDO',
            textColor: AppColors.accentAlt,
            onPressed: () => _undo(candidate),
          ),
        ),
      );
  }

  Future<void> _undo(Candidate candidate) async {
    await WishlistService.instance.undoLast(candidate.id);
    if (!mounted) return;
    setState(() {
      if (!_candidates.any((c) => c.id == candidate.id)) {
        _candidates.insert(0, candidate);
      }
    });
  }

  void _openResume(Candidate candidate) {
    pushSmooth(context, ResumeScreen(candidate: candidate));
  }

  void _openVideoIntro(Candidate candidate) {
    pushSmooth(context, VideoIntroScreen(candidate: candidate));
  }

  Future<void> _openSearch() async {
    final selectedId = await pushSmooth<String>(
      context,
      SearchScreen(candidates: List<Candidate>.from(_candidates)),
    );
    if (selectedId == null || !mounted) return;
    setState(() {
      final index = _candidates.indexWhere((c) => c.id == selectedId);
      if (index > 0) {
        final candidate = _candidates.removeAt(index);
        _candidates.insert(0, candidate);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _candidates.isEmpty
                        ? _buildEmptyState()
                        : FadeInUp(child: _buildCardStack()),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: _FloatingIconButton(
                  icon: Icons.search_rounded,
                  tooltip: 'Search candidates',
                  color: AppColors.textPrimary,
                  onTap: (_loading || _candidates.isEmpty) ? null : _openSearch,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCardStack() {
    final visible = _candidates.take(3).toList().reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cardSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            alignment: Alignment.center,
            children: [
              for (int i = 0; i < visible.length; i++)
                _AnimatedDeckSlot(
                  key: ValueKey(visible[i].id),
                  depthFromTop: visible.length - 1 - i,
                  isTop: i == visible.length - 1,
                  child: SizedBox(
                    width: cardSize.width,
                    height: cardSize.height,
                    child: SwipeableCandidateCard(
                      candidate: visible[i],
                      isTopCard: i == visible.length - 1,
                      onSwiped: (direction) => _handleSwipe(visible[i], direction),
                      onSwipeDown: () => _openVideoIntro(visible[i]),
                      onDoubleTap: () => _openResume(visible[i]),
                      onWishlistTap: () => _handleWishlistSelect(visible[i]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: FadeInUp(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_rounded, size: 72, color: AppColors.textSecondary),
              const SizedBox(height: 16),
              const Text(
                'No more candidates right now',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check your shortlist or come back later for new profiles.',
                style: TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: widget.onViewWishlist,
                icon: const Icon(Icons.favorite),
                label: const Text('View wishlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animates a card's resting scale/position smoothly whenever its depth in
/// the stack changes (e.g. it becomes the new top card after a swipe).
class _AnimatedDeckSlot extends StatelessWidget {
  final int depthFromTop;
  final bool isTop;
  final Widget child;

  const _AnimatedDeckSlot({
    super.key,
    required this.depthFromTop,
    required this.isTop,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scale = 1 - (depthFromTop * 0.04);
    final verticalOffset = depthFromTop * 14.0;

    final animated = TweenAnimationBuilder<double>(
      tween: Tween(begin: scale, end: scale),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => Transform.scale(scale: value, child: child),
    );

    final positioned = AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, -verticalOffset, 0),
      child: animated,
    );

    return isTop
        ? positioned
        : IgnorePointer(child: Opacity(opacity: 0.9, child: positioned));
  }
}

class _FloatingIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback? onTap;

  const _FloatingIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  State<_FloatingIconButton> createState() => _FloatingIconButtonState();
}

class _FloatingIconButtonState extends State<_FloatingIconButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _scale = 0.85),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _scale = 1),
      onTapCancel: widget.onTap == null ? null : () => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        child: Tooltip(
          message: widget.tooltip,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
                child: Icon(
                  widget.icon,
                  color: widget.onTap == null ? AppColors.textSecondary.withValues(alpha: 0.4) : widget.color,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
