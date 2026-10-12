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

/// Shortlist tab: candidates promoted from the Wishlist for final hiring
/// consideration. Swiping a tile away (or tapping the undo icon) sends the
/// candidate back to the Wishlist rather than discarding them.
class ShortlistScreen extends StatelessWidget {
  const ShortlistScreen({super.key});

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
                  'Shortlist',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(
                child: ValueListenableBuilder(
                  valueListenable: WishlistService.instance.listenableFinalShortlist(),
                  builder: (context, _, _) {
                    final shortlisted = WishlistService.instance.getFinalShortlist();
                    if (shortlisted.isEmpty) {
                      return FadeInUp(
                        child: const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32),
                            child: Text(
                              'No one shortlisted yet.\nMove a candidate here from your Wishlist when you\'re ready to move forward with them.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: shortlisted.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final candidate = shortlisted[index];
                        return FadeInUp(
                          delay: Duration(milliseconds: 50 * index),
                          child: _ShortlistTile(
                            candidate: candidate,
                            onDemote: () => WishlistService.instance.demoteToWishlist(candidate),
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

class _ShortlistTile extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback onDemote;
  final VoidCallback onResume;
  final VoidCallback onVideo;

  const _ShortlistTile({
    required this.candidate,
    required this.onDemote,
    required this.onResume,
    required this.onVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(candidate.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDemote(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: AppColors.accentGradient,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.undo_rounded, color: Colors.white),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.like.withValues(alpha: 0.4)),
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
                  Row(
                    children: [
                      const Icon(Icons.verified_rounded, size: 14, color: AppColors.like),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(candidate.name,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${candidate.role} · ${candidate.experience}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(onPressed: onResume, icon: const Icon(Icons.description_outlined), tooltip: 'Resume', iconSize: 20),
            IconButton(onPressed: onVideo, icon: const Icon(Icons.play_circle_outline), tooltip: 'Intro video', iconSize: 20),
            IconButton(
              onPressed: onDemote,
              icon: const Icon(Icons.undo_rounded, color: AppColors.accentAlt),
              tooltip: 'Move back to Wishlist',
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }
}
