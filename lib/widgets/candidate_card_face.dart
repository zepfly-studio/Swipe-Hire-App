import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../models/candidate.dart';
import '../theme/app_theme.dart';

String candidatePhotoHeroTag(String candidateId) => 'candidate-photo-$candidateId';

class CandidateCardFace extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback? onWishlistTap;

  const CandidateCardFace({super.key, required this.candidate, this.onWishlistTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: AppColors.accentGradient,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 30, offset: const Offset(0, 16)),
        ],
      ),
      padding: const EdgeInsets.all(2.4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildPhoto(),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87, Colors.black87],
                  stops: [0.0, 0.34, 1.0],
                ),
              ),
            ),
            Positioned(
              left: 18,
              top: 18,
              child: _ExperienceBadge(experience: candidate.experience),
            ),
            Positioned(
              top: 18,
              right: 18,
              child: _SwipeDownHint(),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 20,
              child: _InfoBlock(candidate: candidate, onWishlistTap: onWishlistTap),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoto() {
    return Hero(
      tag: candidatePhotoHeroTag(candidate.id),
      child: _photoContent(),
    );
  }

  Widget _photoContent() {
    if (candidate.photoUrl.isEmpty) {
      return InitialsAvatar(name: candidate.name);
    }
    return CachedNetworkImage(
      imageUrl: candidate.photoUrl,
      fit: BoxFit.cover,
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: AppColors.surfaceAlt,
        highlightColor: AppColors.surface,
        period: const Duration(milliseconds: 1400),
        child: Container(color: Colors.white),
      ),
      errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
    );
  }
}

/// Colorful initials avatar shown whenever a candidate has no photo or their
/// photo fails to load (e.g. no network) -- a nicer fallback than a generic
/// grey person icon.
class InitialsAvatar extends StatelessWidget {
  final String name;
  const InitialsAvatar({super.key, required this.name});

  static const List<List<Color>> _palettes = [
    [Color(0xFF7C5CFF), Color(0xFF3DDAD7)],
    [Color(0xFFFF6B9D), Color(0xFFFFA36B)],
    [Color(0xFF34D399), Color(0xFF22C55E)],
    [Color(0xFF60A5FA), Color(0xFF7C5CFF)],
    [Color(0xFFFFA36B), Color(0xFFFF5C72)],
  ];

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palettes[name.hashCode.abs() % _palettes.length];
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 64,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ExperienceBadge extends StatelessWidget {
  final String experience;
  const _ExperienceBadge({required this.experience});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 14, color: AppColors.accentAlt),
          const SizedBox(width: 6),
          Text(
            experience,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback? onWishlistTap;
  const _InfoBlock({required this.candidate, required this.onWishlistTap});

  @override
  Widget build(BuildContext context) {
    final hasCurrentSalary = candidate.currentSalaryLpa > 0;

    final stats = <_StatEntry>[
      _StatEntry(Icons.work_history_outlined, 'Experience', candidate.experience),
      _StatEntry(Icons.apartment_rounded, 'Current company', candidate.currentCompany),
      if (hasCurrentSalary)
        _StatEntry(Icons.account_balance_wallet_outlined, 'Current CTC',
            '₹${candidate.currentSalaryLpa.toStringAsFixed(1)} LPA'),
      _StatEntry(Icons.payments_outlined, 'Expected CTC',
          '₹${candidate.expectedSalaryLpa.toStringAsFixed(1)} LPA'),
      _StatEntry(Icons.event_available_outlined, 'Notice period', candidate.noticePeriod),
      _StatEntry(Icons.location_on_outlined, 'Location', candidate.location),
      _StatEntry(Icons.school_outlined, 'Qualification', candidate.qualification),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${candidate.name}, ${candidate.age}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            const Icon(Icons.work_outline, size: 15, color: AppColors.accentAlt),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                candidate.role,
                style: const TextStyle(color: AppColors.accentAlt, fontSize: 14.5, fontWeight: FontWeight.w700),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final chipWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: stats
                  .map((s) => SizedBox(width: chipWidth, child: _InfoStatChip(stat: s)))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: candidate.skills
              .take(3)
              .map((skill) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      skill,
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Double-tap · resume    Swipe up/down · intro video',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (onWishlistTap != null) ...[
              const SizedBox(width: 10),
              _WishlistButton(onTap: onWishlistTap!),
            ],
          ],
        ),
      ],
    );
  }
}

class _StatEntry {
  final IconData icon;
  final String label;
  final String value;
  const _StatEntry(this.icon, this.label, this.value);
}

class _InfoStatChip extends StatelessWidget {
  final _StatEntry stat;
  const _InfoStatChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(stat.icon, size: 14, color: AppColors.accentAlt),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.label,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  stat.value,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WishlistButton extends StatefulWidget {
  final VoidCallback onTap;
  const _WishlistButton({required this.onTap});

  @override
  State<_WishlistButton> createState() => _WishlistButtonState();
}

class _WishlistButtonState extends State<_WishlistButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: AppColors.likeGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: AppColors.like.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 6)),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 15),
              SizedBox(width: 6),
              Text(
                'Wishlist',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwipeDownHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.unfold_more_rounded, color: Colors.white70, size: 20),
    );
  }
}
