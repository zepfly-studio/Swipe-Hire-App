import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';
import '../models/candidate.dart';
import '../theme/app_theme.dart';

String candidatePhotoHeroTag(String candidateId) => 'candidate-photo-$candidateId';

/// The recruiter's swipe-deck card: a photo section with status/match
/// badges and a "Watch Intro" bubble, and a white info panel below it
/// (name, meta chips, a colour-coded stat grid, skills).
class CandidateCardFace extends StatelessWidget {
  final Candidate candidate;
  final VoidCallback? onWishlistTap;
  final VoidCallback? onWatchIntro;
  final VoidCallback? onViewResume;

  const CandidateCardFace({
    super.key,
    required this.candidate,
    this.onWishlistTap,
    this.onWatchIntro,
    this.onViewResume,
  });

  /// "Available now" / "Notice: 30 days" from what the candidate actually
  /// entered, or nothing when they left it blank.
  String? get _availability {
    final notice = candidate.noticePeriod.trim();
    if (notice.isEmpty || notice == '-') return null;
    final lower = notice.toLowerCase();
    if (lower.contains('immediate') || lower == '0' || lower.contains('no notice')) return 'Available now';
    return 'Notice: $notice';
  }

  String get _firstName {
    final parts = candidate.name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? candidate.name : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppColors.cardShadow(opacity: 2.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 11, child: _buildPhotoSection()),
          Expanded(flex: 10, child: _buildInfoSection(context)),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(tag: candidatePhotoHeroTag(candidate.id), child: _photoContent()),
        // A faint bottom scrim so the watch-intro bubble stays legible over
        // any photo, without darkening the whole image like the old
        // Tinder-style full-bleed overlay did.
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 90,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black38],
              ),
            ),
          ),
        ),
        if (_availability != null) Positioned(top: 14, left: 14, child: _StatusPill(label: _availability!)),
        if (candidate.matchScore != null)
          Positioned(top: 14, right: 14, child: _MatchBadge(percent: candidate.matchScore!)),
        Positioned.fill(
          child: Align(
            alignment: const Alignment(0.35, -0.15),
            child: _GreetingNote(firstName: _firstName),
          ),
        ),
        if (onWatchIntro != null)
          Positioned(right: 16, bottom: 14, child: _WatchIntroBubble(onTap: onWatchIntro!)),
      ],
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
        child: Container(color: AppColors.surfaceAlt),
      ),
      errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    final hasCurrentSalary = candidate.currentSalaryLpa > 0;
    final stats = <_StatEntry>[
      _StatEntry(Icons.work_history_rounded, 'Experience', candidate.experience, AppColors.accent),
      _StatEntry(Icons.apartment_rounded, 'Current Company', candidate.currentCompany, AppColors.info),
      _StatEntry(Icons.payments_rounded, hasCurrentSalary ? 'Expected CTC' : 'Expected CTC', '₹${candidate.expectedSalaryLpa.toStringAsFixed(1)} LPA', AppColors.like),
      _StatEntry(Icons.event_available_rounded, 'Notice Period', candidate.noticePeriod, AppColors.accentAlt),
      _StatEntry(Icons.location_on_rounded, 'Location', candidate.location, AppColors.info),
      _StatEntry(Icons.school_rounded, 'Qualification', candidate.qualification, AppColors.accent),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    candidate.name,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.verified_rounded, color: AppColors.accent, size: 18),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              candidate.role,
              style: const TextStyle(color: AppColors.accent, fontSize: 14.5, fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _MetaTag(icon: Icons.location_on_outlined, label: candidate.location),
                _MetaTag(icon: Icons.work_outline_rounded, label: candidate.experience),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 10.0;
                // Two chips per row when there's room; one full-width chip
                // per row on a very narrow card (a tiny browser window).
                // Never negative: SizedBox asserts on a negative width.
                final available = constraints.maxWidth.isFinite ? constraints.maxWidth : 0.0;
                final chipWidth = available >= 240 ? (available - spacing) / 2 : available;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: stats.map((s) => SizedBox(width: chipWidth, child: _InfoStatChip(stat: s))).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Top Skills', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
                const Spacer(),
                if (candidate.skills.length > 4)
                  GestureDetector(
                    onTap: () => _showAllSkills(context),
                    child: const Text('View All', style: TextStyle(color: AppColors.accent, fontSize: 12.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                ...candidate.skills.take(4).map((skill) => _SkillChip(label: skill)),
                if (candidate.skills.length > 4) _SkillChip(label: '+${candidate.skills.length - 4}'),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (onViewResume != null)
                  Flexible(
                    child: TextButton.icon(
                      onPressed: onViewResume,
                      icon: const Icon(Icons.description_outlined, size: 15),
                      label: const Text('Resume', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 0)),
                    ),
                  ),
                const Spacer(),
                if (onWishlistTap != null) _WishlistButton(onTap: onWishlistTap!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAllSkills(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('All Skills', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: candidate.skills.map((s) => _SkillChip(label: s)).toList(),
            ),
          ],
        ),
      ),
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
    [AppColors.accent, AppColors.accentAlt],
    [Color(0xFF3F7F6D), Color(0xFF6FA593)],
    [Color(0xFF10B981), AppColors.like],
    [AppColors.info, AppColors.accent],
    [Color(0xFF8DB5A6), AppColors.accentAlt],
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
      // Scaled to whatever box this is dropped into (a 38px header avatar
      // and a 92px profile avatar share this widget) instead of a fixed
      // size meant only for the larger one, which overflowed badly when
      // reused small.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest.shortestSide;
          return Text(
            _initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.42,
              fontWeight: FontWeight.w800,
            ),
          );
        },
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.like, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  final int percent;
  const _MatchBadge({required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 2.4,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.like),
            ),
          ),
          const SizedBox(width: 6),
          Text('$percent% Match', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _GreetingNote extends StatelessWidget {
  final String firstName;
  const _GreetingNote({required this.firstName});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.045,
      child: Text.rich(
        TextSpan(
          children: [
            const TextSpan(text: 'Hey! I\'m\n'),
            TextSpan(text: firstName),
          ],
        ),
        textAlign: TextAlign.right,
        style: GoogleFonts.caveat(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          height: 1.05,
          shadows: const [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 1))],
        ),
      ),
    );
  }
}

class _WatchIntroBubble extends StatelessWidget {
  final VoidCallback onTap;
  const _WatchIntroBubble({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withValues(alpha: 0.4),
              border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          const Text(
            'Watch Intro',
            style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700, shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
          ),
        ],
      ),
    );
  }
}

class _MetaTag extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _StatEntry {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatEntry(this.icon, this.label, this.value, this.color);
}

class _InfoStatChip extends StatelessWidget {
  final _StatEntry stat;
  const _InfoStatChip({required this.stat});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: stat.color.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(9)),
            child: Icon(stat.icon, size: 13, color: stat.color),
          ),
          const SizedBox(width: 8),
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
                  stat.value.isEmpty ? '-' : stat.value,
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

class _SkillChip extends StatelessWidget {
  final String label;
  const _SkillChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            gradient: AppColors.likeGradient,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: AppColors.like.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5)),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, color: Colors.white, size: 14),
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
