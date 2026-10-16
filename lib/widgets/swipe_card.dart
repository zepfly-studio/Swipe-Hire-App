import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/candidate.dart';
import '../theme/app_theme.dart';
import '../utils/salary.dart';
import 'candidate_card_face.dart' show InitialsAvatar;
import 'candidate_details.dart';

/// A candidate card on the company swipe stack: avatar, name, headline,
/// wishlist heart, match % and chips (experience, expected salary,
/// "Negotiable") and -- on the top card -- the details first, then all the
/// skills, then the intro video and, last, the resume (double-tap opens it).
///
/// It is one tall card: the first screen is the candidate's details and
/// skills; a quick swipe up jumps straight to the intro video ([videoKey]
/// marks it for the swipe screen), and a slow drag scrolls through the rest.
///
/// Drag stamps and tint are drawn by the swipe screen, not here.
class SwipeCardView extends StatelessWidget {
  final Candidate candidate;

  /// The top card renders the live PDF and everything below it; cards flying
  /// off or behind are light placeholders.
  final bool isTop;
  final VoidCallback? onOpenResume;
  final VoidCallback? onToggleWishlist;

  /// Height of the area the card scrolls in. When given, the resume is sized
  /// so the skills fit on the first screen.
  final double? viewportHeight;
  final GlobalKey? videoKey;

  const SwipeCardView({
    super.key,
    required this.candidate,
    this.viewportHeight,
    this.videoKey,
    this.isTop = true,
    this.onOpenResume,
    this.onToggleWishlist,
  });

  double? _resumeHeight() {
    final v = viewportHeight;
    if (v == null || !isTop) return null;
    return (v - 120).clamp(320.0, 520.0);
  }

  static Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final exp = salaryRangeLabel(c.expectedSalaryLpa, c.expectedSalaryMaxLpa ?? 0);
    final expChip = candidateExperienceChip(c);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: ClipOval(
                  child: c.photoUrl.isEmpty
                      ? InitialsAvatar(name: c.name)
                      : CachedNetworkImage(
                          imageUrl: c.photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => InitialsAvatar(name: c.name),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.15),
                    ),
                    if (c.role.trim().isNotEmpty && c.role.trim() != '-')
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          c.role,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
              if (onToggleWishlist != null)
                IconButton.filledTonal(
                  tooltip: c.wishlisted ? 'Remove from wishlist' : 'Add to wishlist',
                  onPressed: onToggleWishlist,
                  style: IconButton.styleFrom(
                    backgroundColor: c.wishlisted ? AppColors.reject.withValues(alpha: 0.12) : AppColors.surfaceAlt,
                    fixedSize: const Size(44, 44),
                  ),
                  icon: Icon(
                    c.wishlisted ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: c.wishlisted ? AppColors.reject : AppColors.textPrimary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (c.matchScore != null) MatchBadge(score: c.matchScore!),
              if (c.location.trim().isNotEmpty && c.location.trim() != '-')
                _InfoChip(icon: Icons.place_outlined, label: c.location),
              if (expChip.isNotEmpty) _InfoChip(icon: Icons.work_outline_rounded, label: expChip),
              if (exp.isNotEmpty) _InfoChip(icon: Icons.currency_rupee_rounded, label: exp.replaceFirst('₹', '')),
              if (c.salaryNegotiable) const _InfoChip(icon: Icons.handshake_outlined, label: 'Negotiable', good: true),
            ],
          ),
          if (isTop) ...[
            const SizedBox(height: 16),
            CandidateDetails(candidate: c, showSkills: false, showVideo: false),
            if (c.skills.isNotEmpty) ...[
              const SizedBox(height: 18),
              _title('SKILLS'),
              SkillChips(candidate: c),
            ],
            const SizedBox(height: 14),
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_double_arrow_up_rounded, size: 20, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text(
                    'Swipe up for the intro video',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Column(
              key: videoKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _title('INTRO VIDEO'),
                if (c.introVideoUrl.isNotEmpty)
                  IntroVideo(url: c.introVideoUrl)
                else
                  Container(
                    height: 90,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
                    child: const Text(
                      'No intro video added',
                      style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _title('RESUME'),
          ] else
            const SizedBox(height: 14),
          _ResumePreview(candidate: c, live: isTop, onOpen: onOpenResume, height: _resumeHeight()),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  /// Highlights a positive fact (salary is negotiable).
  final bool good;
  const _InfoChip({required this.icon, required this.label, this.good = false});

  @override
  Widget build(BuildContext context) {
    final color = good ? AppColors.likeText : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: good ? AppColors.like.withValues(alpha: 0.12) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: good ? color : null),
            ),
          ),
        ],
      ),
    );
  }
}

/// First page of the resume on white with a double-tap hint: aspect 1:1.3,
/// or a fixed [height] when the card knows its viewport.
class _ResumePreview extends StatelessWidget {
  final Candidate candidate;
  final bool live;
  final VoidCallback? onOpen;
  final double? height;
  const _ResumePreview({required this.candidate, required this.live, this.onOpen, this.height});

  Widget _sized(Widget child) =>
      height == null ? AspectRatio(aspectRatio: 1 / 1.3, child: child) : SizedBox(height: height, child: child);

  @override
  Widget build(BuildContext context) {
    final hasPdf = candidate.resumeUrl.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onOpen,
      child: _sized(
        Container(
          decoration: BoxDecoration(
            color: AppColors.onPrimary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasPdf && live)
                IgnorePointer(
                  child: SfPdfViewer.network(
                    candidate.resumeUrl,
                    pageLayoutMode: PdfPageLayoutMode.single,
                    canShowScrollHead: false,
                    canShowPaginationDialog: false,
                    enableDoubleTapZooming: false,
                    enableTextSelection: false,
                    interactionMode: PdfInteractionMode.pan,
                  ),
                )
              else
                Center(child: Icon(Icons.description_outlined, size: 56, color: AppColors.textTertiary)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.scrim.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasPdf ? '⤢ Double-tap to open resume' : 'No resume file · double-tap for summary',
                      style: const TextStyle(color: AppColors.onPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
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
