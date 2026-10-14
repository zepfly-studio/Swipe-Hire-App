import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../models/company.dart';
import '../../services/api_client.dart';
import '../../services/cloudinary_service.dart';
import '../../services/company_service.dart';
import '../../services/error_reporter.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_background.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart';
import '../../widgets/fade_in_up.dart';
import '../../widgets/section_card.dart';

const _sizes = ['1-10', '11-50', '51-200', '201-1000', '1000+'];

/// The recruiter's company page: what candidates see when they tap the
/// company name on a job. A website on the same domain as the recruiter's
/// work email verifies the company automatically; otherwise they can ask for
/// a manual review.
class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _website = TextEditingController();
  final _industry = TextEditingController();
  final _location = TextEditingController();
  final _about = TextEditingController();

  CompanyProfile? _saved;
  String _size = '';
  String _logoUrl = '';
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _website.dispose();
    _industry.dispose();
    _location.dispose();
    _about.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final company = await CompanyService.instance.fetchMine();
      if (!mounted) return;
      if (company != null) {
        _fill(company);
      } else {
        _name.text = RecruiterProfileService.instance.company;
      }
      setState(() {
        _saved = company;
        _loading = false;
      });
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompanyProfileScreen: load failed');
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error('Could not load your company', description: 'Check your connection and try again.');
    }
  }

  void _fill(CompanyProfile c) {
    _name.text = c.name;
    _website.text = c.website;
    _industry.text = c.industry;
    _location.text = c.location;
    _about.text = c.about;
    _size = c.size;
    _logoUrl = c.logoUrl;
  }

  Future<void> _pickLogo() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final file = files.isEmpty ? null : files.first;
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService.instance.uploadPhoto(file);
      if (mounted) setState(() => _logoUrl = url);
    } on StateError catch (e) {
      if (mounted) AppToast.error('Could not upload the logo', description: e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompanyProfileScreen: logo upload failed');
      if (mounted) AppToast.error('Could not upload the logo', description: 'Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      AppToast.warning('Some details need fixing', description: 'Check the fields marked in red.');
      return;
    }
    setState(() => _saving = true);
    try {
      final wasVerified = _saved?.isVerified ?? false;
      final company = await CompanyService.instance.save(CompanyProfile(
        id: _saved?.id ?? '',
        name: _name.text.trim(),
        website: _website.text.trim(),
        about: _about.text.trim(),
        industry: _industry.text.trim(),
        size: _size,
        location: _location.text.trim(),
        logoUrl: _logoUrl,
      ));
      if (!mounted) return;
      setState(() => _saved = company);
      _fill(company);
      if (company.isVerified && !wasVerified) {
        AppToast.success('Company verified', description: 'Candidates now see the verified badge next to ${company.name}.');
      } else {
        AppToast.success('Company saved', description: 'Candidates see this on your job postings.');
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not save your company', description: e.message);
    } catch (e, stackTrace) {
      ErrorReporter.report(e, stackTrace, reason: 'CompanyProfileScreen: save failed');
      if (mounted) AppToast.error('Could not save your company', description: 'Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestReview() async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request a review'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'How can we confirm this is your company? (e.g. registration number, LinkedIn page)',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Send request')),
        ],
      ),
    );
    controller.dispose();
    if (note == null || !mounted) return;
    try {
      final company = await CompanyService.instance.requestVerification(note: note);
      if (!mounted) return;
      setState(() => _saved = company);
      AppToast.info('Request sent', description: 'We will review it and update the badge.');
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not send the request', description: e.message);
    }
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
                    const Text('Company page', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accentAlt))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FadeInUp(child: _verificationCard()),
                              const SizedBox(height: 16),
                              FadeInUp(delay: const Duration(milliseconds: 40), child: _logoRow()),
                              const SizedBox(height: 16),
                              _field(_name, 'Company name', Icons.apartment_rounded,
                                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the company name' : null),
                              const SizedBox(height: 14),
                              _field(_website, 'Website', Icons.language_rounded,
                                  keyboardType: TextInputType.url, helper: 'Use your company domain, e.g. acme.com'),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: _field(_industry, 'Industry', Icons.category_outlined)),
                                  const SizedBox(width: 12),
                                  Expanded(child: _field(_location, 'Location', Icons.location_on_outlined)),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text('Company size', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final s in _sizes)
                                    ChoiceChip(
                                      label: Text(s),
                                      selected: _size == s,
                                      onSelected: (on) => setState(() => _size = on ? s : ''),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _field(_about, 'About the company', Icons.notes_rounded, maxLines: 5),
                              const SizedBox(height: 24),
                              FilledButton(
                                onPressed: (_saving || _uploading) ? null : _save,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                                child: _saving
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                                    : const Text('Save company'),
                              ),
                            ],
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

  Widget _verificationCard() {
    final company = _saved;
    final (color, icon, title, text) = company == null
        ? (
            AppColors.textSecondary,
            Icons.shield_outlined,
            'Not verified yet',
            'Save your company with a website on your work email domain and it is verified automatically.',
          )
        : company.isVerified
            ? (AppColors.info, Icons.verified_rounded, 'Verified', 'Candidates see a verified badge next to ${company.name}.')
            : company.isPending
                ? (AppColors.warning, Icons.hourglass_top_rounded, 'Review requested', 'We are reviewing your request. The badge appears once it is approved.')
                : (
                    AppColors.textSecondary,
                    Icons.shield_outlined,
                    'Not verified yet',
                    'Your website does not match your work email domain. Fix the website, or ask for a manual review.',
                  );
    return SectionCard(
      title: 'Verification',
      icon: Icons.verified_user_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          if (company != null && !company.isVerified && !company.isPending) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _requestReview,
              icon: const Icon(Icons.rate_review_outlined, size: 16),
              label: const Text('Request a review'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _logoRow() {
    final name = _name.text.trim().isEmpty ? 'Company' : _name.text.trim();
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: _logoUrl.isEmpty
                ? InitialsAvatar(name: name)
                : CachedNetworkImage(
                    imageUrl: _logoUrl,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) => InitialsAvatar(name: name),
                  ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _uploading ? null : _pickLogo,
                icon: _uploading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.image_outlined, size: 18),
                label: Text(_uploading ? 'Uploading...' : (_logoUrl.isEmpty ? 'Add a logo' : 'Change logo')),
              ),
              if (_logoUrl.isNotEmpty)
                TextButton(onPressed: () => setState(() => _logoUrl = ''), child: const Text('Remove logo')),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
    TextInputType? keyboardType,
    String? helper,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: AppColors.textPrimary),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        alignLabelWithHint: maxLines > 1,
        prefixIcon: Icon(icon, color: AppColors.accentAlt, size: 20),
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      ),
    );
  }
}
