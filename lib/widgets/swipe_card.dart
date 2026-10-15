import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/candidate.dart';
import '../theme/app_theme.dart';
import 'candidate_card_face.dart' show InitialsAvatar;
import 'candidate_details.dart';

/// A candidate card on the company swipe stack: avatar, name, headline,
/// wishlist heart, chips, the first page of the resume (double-tap opens it)
/// and -- on the top card -- the intro video and details below.
///
/// Drag stamps and tint are drawn by the swipe screen, not here.
class SwipeCardView extends StatelessWidget {
  final Candidate candidate;

  /// The top card shows the PDF preview and [CandidateDetails]; cards
  /// behind it are light placeholders.
  final bool isTop;
  final VoidCallback? onOpenResume;
  final VoidCallback? onToggleWishlist;

  const SwipeCardView({
    super.key,
    required this.candidate,
    this.isTop = true,
    this.onOpenResume,
    this.onToggleWishlist,
  });

  @override
  Widget build(BuildContext context) {
    final c = candidate;
    final exp = candidateExpectedSalaryLabel(c);
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
            ],
          ),
          const SizedBox(height: 14),
          _ResumePreview(candidate: c, live: isTop, onOpen: onOpenResume),
          if (isTop) ...[
            const SizedBox(height: 14),
            const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: AppColors.textSecondary),
                  SizedBox(width: 4),
                  Text(
                    'Scroll down for intro video & details',
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            CandidateDetails(candidate: c),
          ],
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// First page of the resume on white (aspect 1:1.3) with a double-tap hint.
class _ResumePreview extends StatelessWidget {
  final Candidate candidate;
  final bool live;
  final VoidCallback? onOpen;
  const _ResumePreview({required this.candidate, required this.live, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final hasPdf = candidate.resumeUrl.isNotEmpty;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onOpen,
      child: AspectRatio(
        aspectRatio: 1 / 1.3,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
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
                Center(
                  child: Icon(Icons.description_outlined, size: 56, color: AppColors.textTertiary),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 10,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      hasPdf ? '⤢ Double-tap to open resume' : 'No resume file · double-tap for summary',
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
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
