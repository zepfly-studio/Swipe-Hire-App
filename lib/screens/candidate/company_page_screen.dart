import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_user.dart';
import '../../models/company.dart';
import '../../services/company_service.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/job_card.dart';
import '../../widgets/section_card.dart';
import '../../widgets/trust_widgets.dart';
import 'job_detail_screen.dart';

/// A company's public page as a candidate sees it: who they are, whether
/// they're verified, and the roles they have open.
class CompanyPageScreen extends StatefulWidget {
  final AppUser user;
  final String companyId;
  const CompanyPageScreen({super.key, required this.user, required this.companyId});

  @override
  State<CompanyPageScreen> createState() => _CompanyPageScreenState();
}

class _CompanyPageScreenState extends State<CompanyPageScreen> {
  CompanyPage? _page;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await CompanyService.instance.fetchPublic(widget.companyId);
      if (!mounted) return;
      setState(() {
        _page = page;
        _loading = false;
      });
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompanyPageScreen: load failed');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _openWebsite(String url) async {
    final opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!opened && mounted) AppToast.error('Could not open the website');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    const Text('Company', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(child: _body()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.accentAlt));
    if (_failed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load this company', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ],
        ),
      );
    }
    final page = _page;
    if (page == null) {
      return const Center(child: Text('This company page is no longer available.', style: TextStyle(color: AppColors.textSecondary)));
    }
    final company = page.company;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        FadeInUp(child: _header(company)),
        if (company.about.isNotEmpty) ...[
          const SizedBox(height: 16),
          FadeInUp(
            delay: const Duration(milliseconds: 40),
            child: SectionCard(
              title: 'About',
              icon: Icons.info_outline_rounded,
              child: Text(company.about, style: const TextStyle(height: 1.5, color: AppColors.textSecondary)),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Text(
          page.jobs.isEmpty ? 'No open roles right now' : 'Open roles (${page.jobs.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final job in page.jobs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: JobCard(
              posting: job,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => JobDetailScreen(user: widget.user, posting: job)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _header(CompanyProfile company) {
    final facts = [
      if (company.industry.isNotEmpty) (Icons.category_outlined, company.industry),
      if (company.size.isNotEmpty) (Icons.groups_outlined, '${company.size} people'),
      if (company.location.isNotEmpty) (Icons.location_on_outlined, company.location),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: company.logoUrl.isEmpty
                      ? InitialsAvatar(name: company.name)
                      : CachedNetworkImage(
                          imageUrl: company.logoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => InitialsAvatar(name: company.name),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanyName(
                      name: company.name,
                      verified: company.isVerified,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    if (company.isVerified)
                      const StatePill(label: 'Verified company', color: AppColors.info, icon: Icons.verified_rounded)
                    else
                      const Text('Not verified yet', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final f in facts)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(f.$1, size: 15, color: AppColors.accentAlt),
                      const SizedBox(width: 5),
                      Text(f.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
              ],
            ),
          ],
          if (company.website.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _openWebsite(company.website),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language_rounded, size: 15, color: AppColors.accent),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      company.website.replaceFirst(RegExp(r'^https?://'), ''),
                      style: const TextStyle(color: AppColors.accent, fontSize: 12.5, decoration: TextDecoration.underline),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
