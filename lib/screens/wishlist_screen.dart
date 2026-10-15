import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/candidate.dart';
import '../services/wishlist_service.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';
import '../widgets/page_transitions.dart';
import 'resume_screen.dart';
import 'video_intro_screen.dart';

/// Wishlist tab: candidates saved via the card's Wishlist button (or a
/// left swipe). From here the recruiter promotes a candidate to the
/// final [ShortlistScreen] -- still a local, no-backend stage -- which is
/// where the actual push into the real Hiring > Pipeline happens.
/// Swiping a tile away instead drops them back into the swipe deck.
class WishlistScreen extends StatelessWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'Wishlist',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: WishlistService.instance.listenableShortlist(),
                  builder: (context, _, _) {
                    final wishlisted = WishlistService.instance.getShortlisted();
                    if (wishlisted.isEmpty) {
                      return FadeInUp(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No candidates in your wishlist yet.\nSwipe left on a profile (or tap its heart button) to add them here.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: wishlisted.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final candidate = wishlisted[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 50 * index),
                          child: _WishlistTile(
                            candidate: candidate,
                            onRemove: () => WishlistService.instance.undoLast(candidate.id),
                            onPromote: () => WishlistService.instance.moveToShortlist(candidate),
                            onResume: () => pushSmooth(context, ResumeScreen(candidate: candidate)),
                            onVideo: () => pushSmooth(context, VideoIntroScreen(candidate: candidate)),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WishlistTile extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback onRemove;
  final VoidCallback onPromote;
  final VoidCallback onResume;
  final VoidCallback onVideo;

  const _WishlistTile({
    required this.candidate,
    required this.onRemove,
    required this.onPromote,
    required this.onResume,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(candidate.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: AppColors.rejectGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.onPrimary),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppColors.cardShadow(),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 60,
                height: 60,
                child: Hero(
                  tag: candidatePhotoHeroTag(candidate.id),
                  child: candidate.photoUrl.isEmpty
                      ? InitialsAvatar(name: candidate.name)
                      : CachedNetworkImage(
                          imageUrl: candidate.photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text('${candidate.role} · ${candidate.experience}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(onPressed: onResume, icon: const Icon(Icons.description_outlined), tooltip: 'Resume', iconSize: 20),
            IconButton(onPressed: onVideo, icon: const Icon(Icons.play_circle_outline), tooltip: 'Intro video', iconSize: 20),
            IconButton(
              onPressed: onPromote,
              icon: const Icon(Icons.playlist_add_check_rounded, color: AppColors.like),
              tooltip: 'Move to Shortlist',
              iconSize: 22,
            ),
          ],
        ),
      ),
    );
  }
}
