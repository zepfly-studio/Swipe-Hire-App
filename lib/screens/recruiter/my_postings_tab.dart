import 'package:flutter/material.dart';
import '../../models/job_posting.dart';
import '../../services/analytics_service.dart';
import '../../services/auth_service.dart';
import '../../services/error_reporter.dart';
import '../../services/job_posting_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/trust_widgets.dart';
import 'applicants_screen.dart';

/// Recruiter's "My Postings" tab: the roles they're hiring for, which show
/// up on every candidate's "Browse Jobs" tab while open. Tap one to edit
/// or open/close it; the floating "+" creates a new one.
class MyPostingsTab extends StatelessWidget {
  const MyPostingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final recruiterUid = AuthService.instance.currentUid;
    return Stack(
      children: [
        StreamBuilder<List<JobPosting>>(
          stream: JobPostingService.instance.streamMyPostings(recruiterUid),
          builder: (context, snapshot) {
            final postings = snapshot.data ?? const [];
            if (postings.isEmpty) {
              return FadeInUp(
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No job postings yet.\nTap "+" to post a role -- every candidate will be able to browse and apply to it.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
              itemCount: postings.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final posting = postings[index];
                return FadeInUp(
                  delay: Duration(milliseconds: 40 * index),
                  child: _PostingTile(
                    posting: posting,
                    onTap: () => _openEditor(context, existing: posting),
                    onApplicants: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ApplicantsScreen(posting: posting)),
                    ),
                  ),
                );
              },
            );
          },
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            onPressed: () => _openEditor(context),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );
  }

  void _openEditor(BuildContext context, {JobPosting? existing}) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _JobPostingEditorScreen(existing: existing)),
    );
  }
}

class _PostingTile extends StatelessWidget {
  final JobPosting posting;
  final VoidCallback onTap;
  final VoidCallback onApplicants;
  const _PostingTile({required this.posting, required this.onTap, required this.onApplicants});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
            boxShadow: AppColors.cardShadow(),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(posting.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                        const SizedBox(height: 2),
                        Text(
                          '${posting.location} · ${posting.employmentType}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: (posting.isOpen ? AppColors.like : AppColors.textSecondary).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: (posting.isOpen ? AppColors.like : AppColors.textSecondary).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      posting.isOpen ? 'Open' : 'Closed',
                      style: TextStyle(
                        color: posting.isOpen ? AppColors.like : AppColors.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (posting.salaryMinLpa > 0 || posting.salaryMaxLpa > 0) ...[
                const SizedBox(height: 8),
                Text(
                  '₹${posting.salaryMinLpa.toStringAsFixed(1)} - ${posting.salaryMaxLpa.toStringAsFixed(1)} LPA',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accentAlt),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: StatePill(
                      label: (posting.applicantsCount ?? 0) == 0
                          ? 'No applicants yet'
                          : '${posting.applicantsCount} applicant${posting.applicantsCount == 1 ? '' : 's'}',
                      color: (posting.applicantsCount ?? 0) == 0 ? AppColors.textSecondary : AppColors.accent,
                      icon: Icons.groups_rounded,
                    ),
                  ),
                  if ((posting.applicantsCount ?? 0) > 0)
                    FilledButton.tonal(
                      onPressed: onApplicants,
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      child: const Text('View applicants'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _JobPostingEditorScreen extends StatefulWidget {
  final JobPosting? existing;
  const _JobPostingEditorScreen({this.existing});

  @override
  State<_JobPostingEditorScreen> createState() => _JobPostingEditorScreenState();
}

class _JobPostingEditorScreenState extends State<_JobPostingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _skills = TextEditingController();
  final _location = TextEditingController();
  final _employmentType = TextEditingController(text: 'Full-time');
  final _salaryMin = TextEditingController();
  final _salaryMax = TextEditingController();
  final _minExperience = TextEditingController();

  bool _saving = false;

  JobPosting? get _existing => widget.existing;
  bool get _isEditMode => _existing != null;

  @override
  void initState() {
    super.initState();
    final existing = _existing;
    if (existing != null) {
      _title.text = existing.title;
      _description.text = existing.description;
      _skills.text = existing.skills.join(', ');
      _location.text = existing.location;
      _employmentType.text = existing.employmentType;
      _salaryMin.text = existing.salaryMinLpa > 0 ? existing.salaryMinLpa.toString() : '';
      _salaryMax.text = existing.salaryMaxLpa > 0 ? existing.salaryMaxLpa.toString() : '';
      _minExperience.text = existing.minExperienceYears > 0 ? existing.minExperienceYears.toString() : '';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _skills.dispose();
    _location.dispose();
    _employmentType.dispose();
    _salaryMin.dispose();
    _salaryMax.dispose();
    _minExperience.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final recruiter = RecruiterProfileService.instance;
    final posting = JobPosting(
      id: _existing?.id ?? '',
      recruiterUid: AuthService.instance.currentUid,
      recruiterName: recruiter.name,
      companyName: recruiter.company.isEmpty ? 'Hiring company' : recruiter.company,
      title: _title.text.trim(),
      description: _description.text.trim(),
      skills: _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      location: _location.text.trim(),
      employmentType: _employmentType.text.trim(),
      salaryMinLpa: double.tryParse(_salaryMin.text.trim()) ?? 0,
      salaryMaxLpa: double.tryParse(_salaryMax.text.trim()) ?? 0,
      minExperienceYears: double.tryParse(_minExperience.text.trim()) ?? 0,
      isOpen: _existing?.isOpen ?? true,
      createdAt: _existing?.createdAt,
    );

    try {
      if (_isEditMode) {
        await JobPostingService.instance.update(posting);
      } else {
        final postingId = await JobPostingService.instance.create(posting);
        AnalyticsService.instance.logJobPosted(jobPostingId: postingId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'MyPostingsTab: save job posting failed');
      if (!mounted) return;
      AppToast.error('Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleOpen() async {
    final existing = _existing;
    if (existing == null) return;
    try {
      await JobPostingService.instance.setOpen(existing.id, !existing.isOpen);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'MyPostingsTab: toggle open failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 20, 0),
              child: Row(
                children: [
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back_rounded)),
                  Expanded(
                    child: Text(
                      _isEditMode ? 'Edit posting' : 'New job posting',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (_isEditMode)
                    TextButton(
                      onPressed: _toggleOpen,
                      child: Text(_existing!.isOpen ? 'Close' : 'Reopen'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _title,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _decoration('Job title', Icons.work_outline_rounded),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _description,
                        maxLines: 4,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _decoration('Description', Icons.notes_rounded),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _skills,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _decoration('Skills required (comma separated)', Icons.auto_awesome_outlined),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _location,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: _decoration('Location', Icons.location_on_outlined),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _employmentType,
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: _decoration('Type', Icons.schedule_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _salaryMin,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: _decoration('Min CTC (LPA)', Icons.payments_outlined),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _salaryMax,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              style: const TextStyle(color: AppColors.textPrimary),
                              decoration: _decoration('Max CTC (LPA)', Icons.payments_outlined),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _minExperience,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: _decoration('Minimum experience (years, 0 = freshers welcome)', Icons.timeline_rounded),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (value.isEmpty) return null;
                          final n = double.tryParse(value);
                          return (n == null || n < 0 || n > 40) ? 'Enter a number of years' : null;
                        },
                      ),
                      const SizedBox(height: 26),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                            : Text(_isEditMode ? 'Save changes' : 'Post job'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
    );
  }
}
