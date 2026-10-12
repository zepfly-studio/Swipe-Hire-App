import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/candidate.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_background.dart';
import '../widgets/candidate_card_face.dart';
import '../widgets/fade_in_up.dart';

class ResumeScreen extends StatelessWidget {
  final Candidate candidate;
  const ResumeScreen({super.key, required this.candidate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgTop,
      body: candidate.resumeUrl.isNotEmpty
          ? _PdfBody(candidate: candidate)
          : AnimatedBackdrop(
              child: CustomScrollView(
                slivers: [
                  _buildHeaderSliver(context),
                  SliverToBoxAdapter(
                    child: _FallbackResumeView(candidate: candidate),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderSliver(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      stretch: true,
      expandedHeight: 220,
      backgroundColor: AppColors.bgTop,
      title: Text('${candidate.name} – Resume'),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: candidatePhotoHeroTag(candidate.id),
              child: candidate.photoUrl.isEmpty
                  ? InitialsAvatar(name: candidate.name)
                  : CachedNetworkImage(
                      imageUrl: candidate.photoUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => InitialsAvatar(name: candidate.name),
                    ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppColors.bgTop],
                  stops: [0.3, 1.0],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfBody extends StatelessWidget {
  final Candidate candidate;
  const _PdfBody({required this.candidate});

  Future<void> _download(BuildContext context) async {
    final uri = Uri.parse(candidate.resumeUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the resume link')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          title: Text('${candidate.name} – Resume'),
          actions: [
            IconButton(
              onPressed: () => _download(context),
              icon: const Icon(Icons.download_rounded),
              tooltip: 'Download resume',
            ),
          ],
        ),
        Expanded(
          child: SfPdfViewer.network(
            candidate.resumeUrl,
            canShowScrollHead: true,
          ),
        ),
      ],
    );
  }
}

/// Shown when no real resume file (Firebase Storage URL) is attached yet,
/// so recruiters still see a structured summary instead of a blank screen.
class _FallbackResumeView extends StatelessWidget {
  final Candidate candidate;
  const _FallbackResumeView({required this.candidate});

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      Text(candidate.name, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(candidate.role,
          style: const TextStyle(color: AppColors.accentAlt, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 22),
      _section('About', candidate.about),
      _section('Qualification', candidate.qualification),
      _section('Experience', candidate.experience),
      _section('Current Company', candidate.currentCompany),
      if (candidate.currentSalaryLpa > 0)
        _section('Current CTC', '₹${candidate.currentSalaryLpa.toStringAsFixed(1)} LPA'),
      _section('Expected CTC', '₹${candidate.expectedSalaryLpa.toStringAsFixed(1)} LPA'),
      _section('Notice Period', candidate.noticePeriod),
      _section('Location', candidate.location),
      const SizedBox(height: 8),
      const Text('Skills', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      const SizedBox(height: 10),
      Wrap(
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
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
        ),
        child: const Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.accentAlt, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'No resume file attached yet. Upload a PDF to Firebase Storage and set resumeUrl on this candidate to show it here.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < sections.length; i++)
              FadeInUp(delay: Duration(milliseconds: 40 * i), child: sections[i]),
          ],
        ),
      ),
    );
  }

  Widget _section(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.accentAlt)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, height: 1.4)),
        ],
      ),
    );
  }
}
