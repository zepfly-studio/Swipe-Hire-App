import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/candidate.dart';
import '../services/candidate_service.dart';
import '../services/error_reporter.dart';
import '../services/mock_candidates.dart';
import '../services/recruiter_profile_service.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/page_transitions.dart';
import '../widgets/swipeable_candidate_card.dart';
import 'resume_screen.dart';
import 'search_screen.dart';
import 'video_intro_screen.dart';

/// Discover tab: a header (brand + search + recruiter avatar), a queue
/// stats bar, the swipe deck, and an explicit row of Pass/Watch/Wishlist
/// buttons below it (the same actions the swipe gestures already trigger,
/// for recruiters who'd rather tap than drag).
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

  // Pagination state for the real (Firestore-backed) deck -- `null`
  // lastDoc + hasMore=true means "haven't fetched a page yet". Once we
  // fall back to the local mock sample (no real candidates exist), there's
  // nothing to paginate, so _hasMore stays false.
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _usingMockFallback = false;

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
      final page = await CandidateService.instance.fetchCandidatesPage();
      loaded = page.candidates;
      _lastDoc = page.lastDoc;
      _hasMore = page.hasMore;
    } catch (e, stackTrace) {
      // Offline, or a permissions/config issue -- fall back to sample data
      // so the app stays fully usable.
      ErrorReporter.report(e, stackTrace, reason: 'HomeSwipeScreen: fetchCandidatesPage failed');
    }
    if (loaded.isEmpty && !_hasMore) {
      loaded = mockCandidates();
      _usingMockFallback = true;
    }
    loaded = loaded.where((c) => !WishlistService.instance.hasBeenSwiped(c.id)).toList();

    if (!mounted) return;
    setState(() {
      _candidates = loaded;
      _loading = false;
    });
  }

  Future<void> _maybeLoadMore() async {
    if (_usingMockFallback || !_hasMore || _loadingMore || _candidates.length >= _lowWaterMark) return;
    _loadingMore = true;
    try {
      final page = await CandidateService.instance.fetchCandidatesPage(startAfter: _lastDoc);
      _lastDoc = page.lastDoc;
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

  /// Right swipe just advances to the next candidate without saving
  /// anything and shows no popup. Left swipe passes on the candidate
  /// (persisted so they don't reappear) and shows an undo snackbar.
  void _handleSwipe(Candidate candidate, SwipeDirection direction) async {
    if (direction == SwipeDirection.left) {
      await WishlistService.instance.reject(candidate);
      if (!mounted) return;
      setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
      _showUndoSnackBar('Passed on ${candidate.name}', candidate);
      _maybeLoadMore();
      return;
    }
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
    _maybeLoadMore();
  }

  void _handleWishlistSelect(Candidate candidate) async {
    await WishlistService.instance.shortlist(candidate);
    if (!mounted) return;
    setState(() => _candidates.removeWhere((c) => c.id == candidate.id));
    _showUndoSnackBar('Added ${candidate.name} to wishlist', candidate);
    _maybeLoadMore();
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
          child: Column(
            children: [
              FadeInUp(child: _buildHeader()),
              const SizedBox(height: 10),
              FadeInUp(delay: const Duration(milliseconds: 40), child: _buildStatsBar()),
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : _candidates.isEmpty
                        ? _buildEmptyState()
                        : FadeInUp(delay: const Duration(milliseconds: 80), child: _buildCardStack()),
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
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(gradient: AppColors.accentGradient, borderRadius: BorderRadius.circular(13)),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
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
          SizedBox(width: 38, height: 38, child: ClipOval(child: InitialsAvatar(name: displayName))),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    final upcoming = _candidates.skip(1).take(3).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow(),
        ),
        child: Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.like, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_candidates.length}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                const Text('Candidates', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            if (upcoming.isNotEmpty) ...[
              SizedBox(
                width: 22.0 * upcoming.length + 10,
                height: 30,
                child: Stack(
                  children: [
                    for (int i = 0; i < upcoming.length; i++)
                      Positioned(
                        left: i * 18.0,
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.surface, width: 2)),
                          child: ClipOval(child: InitialsAvatar(name: upcoming[i].name)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            OutlinedButton.icon(
              onPressed: (_loading || _candidates.isEmpty) ? null : _openSearch,
              icon: const Icon(Icons.tune_rounded, size: 15),
              label: const Text('Filters', style: TextStyle(fontSize: 12.5)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
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
