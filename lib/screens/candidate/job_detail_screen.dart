import 'package:flutter/material.dart';
import '../../models/app_user.dart';
import '../../models/job_posting.dart';
import '../../services/error_reporter.dart';
import '../../services/job_posting_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';

/// Full detail of one [JobPosting] -- apply, or save it for later. Reached
/// from either the "Browse Jobs" or "Saved" tab.
class JobDetailScreen extends StatefulWidget {
  final AppUser user;
  final JobPosting posting;
  const JobDetailScreen({super.key, required this.user, required this.posting});

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  bool? _applied;
  bool _applying = false;
  bool? _saved;
  bool _savingToggle = false;

  @override
  void initState() {
    super.initState();
    JobPostingService.instance.hasApplied(widget.user.uid, widget.posting.id).then((applied) {
      if (mounted) setState(() => _applied = applied);
    });
    JobPostingService.instance.streamSavedJobIds(widget.user.uid).first.then((ids) {
      if (mounted) setState(() => _saved = ids.contains(widget.posting.id));
    });
  }

  Future<void> _toggleSave() async {
    if (_savingToggle || _saved == null) return;
    setState(() => _savingToggle = true);
    try {
      if (_saved!) {
        await JobPostingService.instance.unsaveJob(widget.user.uid, widget.posting.id);
      } else {
        await JobPostingService.instance.saveJob(widget.user.uid, widget.posting.id);
      }
      if (mounted) setState(() => _saved = !_saved!);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'JobDetailScreen: toggle save failed');
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await JobPostingService.instance.apply(
        posting: widget.posting,
        candidateUid: widget.user.uid,
        candidateName: widget.user.name,
      );
      if (!mounted) return;
      setState(() {
        _applied = true;
        _applying = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Application sent!'),
          backgroundColor: AppColors.surfaceAlt,
          behavior: SnackBarBehavior.floating,
        ));
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'JobDetailScreen: apply failed');
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not apply. Please try again.'), backgroundColor: AppColors.reject),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final posting = widget.posting;
    return Scaffold(
      body: AnimatedBackdrop(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                    const Spacer(),
                    IconButton(
                      onPressed: _saved == null ? null : _toggleSave,
                      icon: Icon(
                        _saved == true ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                        color: _saved == true ? AppColors.accentAlt : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FadeInUp(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(posting.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            Text(
                              posting.companyName,
                              style: const TextStyle(color: AppColors.accentAlt, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      FadeInUp(
                        delay: const Duration(milliseconds: 40),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (posting.location.isNotEmpty) _chip(Icons.location_on_outlined, posting.location),
                            if (posting.employmentType.isNotEmpty) _chip(Icons.schedule_outlined, posting.employmentType),
                            if (posting.salaryMinLpa > 0 || posting.salaryMaxLpa > 0)
                              _chip(Icons.payments_outlined, '₹${posting.salaryMinLpa.toStringAsFixed(1)}-${posting.salaryMaxLpa.toStringAsFixed(1)} LPA'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      FadeInUp(
                        delay: const Duration(milliseconds: 80),
                        child: SectionCard(
                          title: 'Description',
                          icon: Icons.notes_rounded,
                          child: Text(posting.description, style: const TextStyle(height: 1.5, color: AppColors.textSecondary)),
                        ),
                      ),
                      if (posting.skills.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        FadeInUp(
                          delay: const Duration(milliseconds: 120),
                          child: SectionCard(
                            title: 'Skills',
                            icon: Icons.auto_awesome_outlined,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: posting.skills
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
                      const SizedBox(height: 26),
                      FadeInUp(
                        delay: const Duration(milliseconds: 160),
                        child: FilledButton(
                          onPressed: (_applied == true || _applying || _applied == null) ? null : _apply,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _applying
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : Text(_applied == true ? 'Applied' : 'Apply Now'),
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

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.cardShadow(),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.accentAlt),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
