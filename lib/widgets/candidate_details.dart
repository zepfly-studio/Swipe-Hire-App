import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/candidate.dart';
import '../theme/app_theme.dart';
import '../utils/salary.dart';

/// "Fresher" or "N yrs exp" for a card chip.
String candidateExperienceChip(Candidate c) {
  final raw = c.experience.trim();
  final lower = raw.toLowerCase();
  if (raw.isEmpty || raw == '-') return '';
  if (lower.contains('fresher') || raw == '0') return 'Fresher';
  final n = RegExp(r'\d+(\.\d+)?').firstMatch(raw)?.group(0);
  if (n == null) return raw;
  final v = double.tryParse(n) ?? 0;
  if (v <= 0) return 'Fresher';
  return '$n ${v == 1 ? 'yr' : 'yrs'} exp';
}

/// "₹6–8 LPA · Negotiable" (range only when max > min).
String candidateExpectedSalaryLabel(Candidate c) =>
    salaryRangeLabel(c.expectedSalaryLpa, c.expectedSalaryMaxLpa ?? 0, negotiable: c.salaryNegotiable);

/// Match badge colours: >= 75 green, >= 45 amber, otherwise grey.
({Color fg, Color bg}) matchBadgeColors(int score) {
  if (score >= 75) return (fg: AppColors.matchHighText, bg: AppColors.matchHigh.withValues(alpha: 0.12));
  if (score >= 45) return (fg: AppColors.matchMid, bg: AppColors.matchMid.withValues(alpha: 0.12));
  return (fg: AppColors.matchLow, bg: AppColors.surfaceAlt);
}

/// "NN% match".
class MatchBadge extends StatelessWidget {
  final int score;
  const MatchBadge({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final c = matchBadgeColors(score);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        '$score% match',
        style: TextStyle(color: c.fg, fontWeight: FontWeight.w800, fontSize: 12.5),
      ),
    );
  }
}

/// Section "Skills", "Details" grid, "About" and -- last -- the intro video;
/// used inside the wishlist sheet and the swipe card's second page (which
/// shows the skills and the video itself, so turns them off). The video only
/// loads when played.
class CandidateDetails extends StatelessWidget {
  final Candidate candidate;
  final bool showSkills;
  final bool showVideo;
  const CandidateDetails({super.key, required this.candidate, this.showSkills = true, this.showVideo = true});

  static String _lpa(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  List<(String, String)> _rows() {
    final c = candidate;
    String clean(String s) => (s.trim() == '-') ? '' : s.trim();
    final exp = clean(c.experience);
    return [
      ('Job title', clean(c.role)),
      ('Experience', exp),
      ('Expected salary', candidateExpectedSalaryLabel(c)),
      ('Current salary', c.currentSalaryLpa > 0 ? '₹${_lpa(c.currentSalaryLpa)} LPA' : ''),
      ('Notice period', clean(c.noticePeriod)),
      ('Current / last company', clean(c.currentCompany)),
      ('Current / last role', clean(c.currentPost)),
      ('Qualification', clean(c.qualification)),
      ('Degree', clean(c.degree)),
      ('College', clean(c.college)),
      ('Graduation year', c.graduationYear?.toString() ?? ''),
      ('Location', clean(c.location)),
      ('Open to cities', c.preferredLocations.join(', ')),
      ('Work mode', c.workModes.map(_workMode).join(', ')),
      ('Job type', c.jobTypes.map(_jobType).join(', ')),
    ].where((r) => r.$2.isNotEmpty).toList();
  }

  static String _workMode(String v) => switch (v) {
        'hybrid' => 'Hybrid',
        'remote' => 'Remote',
        _ => 'On-site',
      };

  static String _jobType(String v) => switch (v) {
        'part-time' => 'Part-time',
        'internship' => 'Internship',
        'contract' => 'Contract',
        _ => 'Full-time',
      };

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text.toUpperCase(),
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
    final rows = _rows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSkills && c.skills.isNotEmpty) ...[
          _title('Skills'),
          SkillChips(candidate: c),
          const SizedBox(height: 18),
        ],
        if (rows.isNotEmpty) ...[
          _title('Details'),
          LayoutBuilder(
            builder: (context, box) {
              final colWidth = (box.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final r in rows)
                    SizedBox(
                      width: colWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.$1, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                          const SizedBox(height: 2),
                          Text(r.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
        ],
        if (c.about.trim().isNotEmpty) ...[
          _title('About'),
          Text(c.about.trim(), style: const TextStyle(fontSize: 14, height: 1.45)),
          const SizedBox(height: 18),
        ],
        if (showVideo && c.introVideoUrl.isNotEmpty) ...[
          _title('Intro video'),
          IntroVideo(url: c.introVideoUrl),
        ],
      ],
    );
  }
}

/// The candidate's skills as chips; skills the job asked for are ticked.
/// [max] caps the chips (the rest collapse into "+N").
class SkillChips extends StatelessWidget {
  final Candidate candidate;
  final int? max;
  const SkillChips({super.key, required this.candidate, this.max});

  @override
  Widget build(BuildContext context) {
    final skills = candidate.skills;
    final matched = candidate.matchedSkills.map((s) => s.toLowerCase()).toSet();
    final shown = max == null ? skills : skills.take(max!).toList();
    final hidden = skills.length - shown.length;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in shown) _SkillChip(label: s, matched: matched.contains(s.toLowerCase())),
        if (hidden > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              '+$hidden',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool matched;
  const _SkillChip({required this.label, required this.matched});

  @override
  Widget build(BuildContext context) {
    final color = matched ? AppColors.likeText : AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: matched ? AppColors.like.withValues(alpha: 0.12) : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: matched ? AppColors.like.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Text(
        matched ? '✓ $label' : label,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// A video that loads only when the recruiter taps play, so a stack of
/// cards does not open several network streams at once.
class IntroVideo extends StatefulWidget {
  final String url;
  const IntroVideo({super.key, required this.url});

  @override
  State<IntroVideo> createState() => _IntroVideoState();
}

class _IntroVideoState extends State<IntroVideo> {
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      c.setLooping(true);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _toggle() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: AppColors.mediaBg,
        constraints: const BoxConstraints(maxHeight: 440),
        child: AspectRatio(
          aspectRatio: c != null && c.value.isInitialized ? c.value.aspectRatio.clamp(0.5, 1.8) : 16 / 9,
          child: c == null
              ? InkWell(
                  onTap: _start,
                  child: Center(
                    child: _loading
                        ? const CircularProgressIndicator(color: AppColors.onPrimary)
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.play_circle_fill_rounded, size: 56, color: AppColors.onPrimary),
                              const SizedBox(height: 6),
                              Text(
                                _failed ? 'Could not play. Tap to retry' : 'Tap to play intro video',
                                style: const TextStyle(color: AppColors.onPrimaryMuted, fontSize: 12.5),
                              ),
                            ],
                          ),
                  ),
                )
              : GestureDetector(
                  onTap: _toggle,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(c),
                      if (!c.value.isPlaying)
                        const Center(child: Icon(Icons.play_arrow_rounded, size: 64, color: AppColors.onPrimaryMuted)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
