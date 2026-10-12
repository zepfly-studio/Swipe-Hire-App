import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/candidate.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';

class VideoIntroScreen extends StatefulWidget {
  final Candidate candidate;
  const VideoIntroScreen({super.key, required this.candidate});

  @override
  State<VideoIntroScreen> createState() => _VideoIntroScreenState();
}

class _VideoIntroScreenState extends State<VideoIntroScreen> {
  VideoPlayerController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final url = widget.candidate.introVideoUrl;
    if (url.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    try {
      final controller = url.startsWith('http')
          ? VideoPlayerController.networkUrl(Uri.parse(url))
          : VideoPlayerController.asset(url);
      await controller.initialize();
      controller
        ..setLooping(true)
        ..play();
      if (!mounted) return;
      setState(() => _controller = controller);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;
    final stats = <_StatChip>[
      _StatChip(Icons.school_outlined, candidate.qualification),
      _StatChip(Icons.apartment_rounded, candidate.currentCompany),
      if (candidate.currentSalaryLpa > 0)
        _StatChip(Icons.account_balance_wallet_outlined,
            'Current: ₹${candidate.currentSalaryLpa.toStringAsFixed(1)} LPA'),
      _StatChip(Icons.payments_outlined, 'Expected: ₹${candidate.expectedSalaryLpa.toStringAsFixed(1)} LPA'),
      _StatChip(Icons.badge_outlined, 'Notice: ${candidate.noticePeriod}'),
      _StatChip(Icons.location_on_outlined, candidate.location),
    ];

    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${candidate.name} – Intro',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FadeInUp(
                        child: Container(
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 24,
                                  offset: const Offset(0, 14)),
                            ],
                          ),
                          child: Hero(
                            tag: candidatePhotoHeroTag(candidate.id),
                            child: AspectRatio(
                              aspectRatio: 16 / 9,
                              child: _buildVideoArea(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeInUp(
                        delay: const Duration(milliseconds: 60),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(candidate.name,
                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${candidate.role} · ${candidate.experience}',
                                    style: const TextStyle(color: AppColors.accentAlt, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (int i = 0; i < stats.length; i++)
                            FadeInUp(delay: Duration(milliseconds: 60 + 30 * i), child: stats[i]),
                        ],
                      ),
                      const SizedBox(height: 22),
                      FadeInUp(
                        delay: const Duration(milliseconds: 220),
                        child: _SectionCard(
                          title: 'About',
                          child: Text(candidate.about,
                              style: const TextStyle(height: 1.5, color: AppColors.textSecondary)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FadeInUp(
                        delay: const Duration(milliseconds: 260),
                        child: _SectionCard(
                          title: 'All Skills',
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: candidate.skills
                                .map((s) => Chip(
                                      label: Text(s),
                                      backgroundColor: AppColors.surfaceAlt,
                                      labelStyle: const TextStyle(color: AppColors.textPrimary),
                                      side: const BorderSide(color: AppColors.border),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_controller != null && _controller!.value.isInitialized) {
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          VideoPlayer(_controller!),
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black54],
                stops: [0.6, 1.0],
              ),
            ),
          ),
          VideoProgressIndicator(
            _controller!,
            allowScrubbing: true,
            colors: const VideoProgressColors(
              playedColor: AppColors.accentAlt,
              bufferedColor: Colors.white24,
              backgroundColor: Colors.white12,
            ),
          ),
          Positioned(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
              child: IconButton(
                key: ValueKey(_controller!.value.isPlaying),
                iconSize: 56,
                color: Colors.white70,
                icon: Icon(_controller!.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                onPressed: () {
                  setState(() {
                    _controller!.value.isPlaying
                        ? _controller!.pause()
                        : _controller!.play();
                  });
                },
              ),
            ),
          ),
        ],
      );
    }
    if (_failed) {
      return Container(
        color: AppColors.surfaceAlt,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_off_outlined, size: 48, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text('No intro video available', style: TextStyle(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    return Container(
      color: AppColors.surfaceAlt,
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _StatChip(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.accentAlt),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.accentAlt)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
