import 'package:flutter/material.dart';
import '../models/candidate.dart';
import '../services/analytics_service.dart';
import '../services/candidate_service.dart';
import '../services/error_reporter.dart';
import '../services/recruiter_profile_service.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/notification_bell.dart';
import '../widgets/page_transitions.dart';
import '../widgets/swipeable_candidate_card.dart';
import 'recruiter/deck_filters_sheet.dart';
import 'resume_screen.dart';
import 'search_screen.dart';
import 'video_intro_screen.dart';
import '../widgets/app_toast.dart';

/// Discover tab: a header (brand + search + recruiter avatar) and the
/// swipe deck -- swipe left (or tap the card's heart button) to wishlist
/// a candidate, swipe right to pass.
class HomeSwipeScreen extends StatefulWidget {
  final VoidCallback onViewWishlist;

  const HomeSwipeScreen({super.key, required this.onViewWishlist});

  @override
  State<HomeSwipeScreen> createState() => _HomeSwipeScreenState();
}

class _HomeSwipeScreenState extends State<HomeSwipeScreen> {
  List<Candidate> _candidates = [];
  bool _loading = true;
  bool _loadingMore = false;

  // Pagination cursor (the last candidate id of the previous page) --
  // `null` cursor + hasMore=true means "haven't fetched a page yet".
  String? _cursor;
  bool _hasMore = true;

  /// What the recruiter narrowed the deck down to; applied by the server.
  CandidateFilters _filters = const CandidateFilters();

  /// Below this many un-swiped cards left in the deck, fetch the next page
  /// so the recruiter never actually runs dry mid-swipe.
  static const int _lowWaterMark = 5;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
  }

  Future<void> _loadFirstPage() async {
    List<Candidate> loaded = [];
    try {
      // The funnel (wishlist/shortlist/rejected) comes from the backend on
      // sign-in; wait for it so already-swiped cards never flash in.
      await WishlistService.instance.ensureLoaded();
      final page = await CandidateService.instance.fetchCandidatesPage(filters: _filters);
      loaded = page.candidates;
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'HomeSwipeScreen: fetchCandidatesPage failed');
    }
    loaded = loaded.where((c) => !WishlistService.instance.hasBeenSwiped(c.id)).toList();

    if (!mounted) return;
    setState(() {
      _candidates = loaded;
      _loading = false;
    });
  }

  Future<void> _maybeLoadMore() async {
    if (!_hasMore || _loadingMore || _candidates.length >= _lowWaterMark) return;
    _loadingMore = true;
    try {
      final page = await CandidateService.instance.fetchCandidatesPage(startAfter: _cursor, filters: _filters);
      _cursor = page.nextCursor;
      _hasMore = page.hasMore;
      final fresh = page.candidates
          .where((c) => !WishlistService.instance.hasBeenSwiped(c.id) && !_candidates.any((existing) => existing.id == c.id))
          .toList();
      if (!mounted) return;
      setState(() => _candidates.addAll(fresh));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'HomeSwipeScreen: load more candidates failed');
    } finally {
      _loadingMore = false;
    }
  }

  /// Left swipe (right-to-left) adds the candidate to the wishlist -- same
  /// action as tapping the card's heart button ([_handleWishlistSelect]),
  /// just reachable as a gesture too. Right swipe passes on the candidate
  /// (persisted so they don't reappear). Both show an undo snackbar.
  void _handleSwipe(Candidate candidate, SwipeDirection direction) async {
    if (direction == SwipeDirection.left) {
      _handleWishlistSelect(candidate);
      return;
    }
    await WishlistService.instance.reject(candidate);
    AnalyticsService.instance.logCandidateSwipe(action: 'pass');
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
    _showUndoToast('Passed on ${candidate.name}', candidate);
    _maybeLoadMore();
  }

  void _handleWishlistSelect(Candidate candidate) async {
    await WishlistService.instance.shortlist(candidate);
    AnalyticsService.instance.logCandidateSwipe(action: 'wishlist');
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
    _showUndoToast('Added ${candidate.name} to wishlist', candidate);
    _maybeLoadMore();
  }

  void _showUndoToast(String message, Candidate candidate) {
    AppToast.action(
      message,
      actionLabel: 'UNDO',
      onAction: () => _undo(candidate),
      duration: const Duration(seconds: 4),
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

  Future<void> _openFilters() async {
    final result = await showDeckFiltersSheet(context, current: _filters);
    if (result == null || !mounted || result == _filters) return;
    setState(() {
      _filters = result;
      _loading = true;
      _cursor = null;
      _hasMore = true;
      _candidates = [];
    });
    await _loadFirstPage();
  }

  Future<void> _clearFilters() async {
    setState(() {
      _filters = const CandidateFilters();
      _loading = true;
      _cursor = null;
      _hasMore = true;
      _candidates = [];
    });
    await _loadFirstPage();
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
          child: Column(
            children: [
              FadeInUp(child: _buildHeader()),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : _candidates.isEmpty
                        ? _buildEmptyState()
                        : FadeInUp(delay: const Duration(milliseconds: 60), child: _buildCardStack()),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final recruiter = RecruiterProfileService.instance;
    final displayName = recruiter.name.trim().isEmpty ? 'Recruiter' : recruiter.name.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: Image.asset('assets/images/icon_mark.png', filterQuality: FilterQuality.high),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SwipeHire', style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                Text('Recruiter', style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          _HeaderIconButton(
            icon: Icons.search_rounded,
            onTap: (_loading || _candidates.isEmpty) ? null : _openSearch,
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: _filters.activeCount > 0,
            label: Text('${_filters.activeCount}'),
            backgroundColor: AppColors.accentAlt,
            child: _HeaderIconButton(icon: Icons.tune_rounded, onTap: _openFilters),
          ),
          const SizedBox(width: 4),
          const NotificationBell(),
          SizedBox(width: 38, height: 38, child: ClipOval(child: InitialsAvatar(name: displayName))),
        ],
      ),
    );
  }

  Widget _buildCardStack() {
    final visible = _candidates.take(3).toList().reversed.toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
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
              Text(
                _filters.activeCount > 0 ? 'No candidates match these filters' : 'No more candidates right now',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _filters.activeCount > 0
                    ? 'Loosen a filter to see more people.'
                    : 'Check your shortlist or come back later for new profiles.',
                style: const TextStyle(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_filters.activeCount > 0)
                FilledButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded),
                  label: const Text('Clear filters'),
                )
              else
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

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, size: 19, color: onTap == null ? AppColors.textSecondary.withValues(alpha: 0.4) : AppColors.textPrimary),
        ),
      ),
    );
  }
}
