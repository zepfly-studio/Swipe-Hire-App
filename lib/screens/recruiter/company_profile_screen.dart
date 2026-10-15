import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/hiring_company.dart';
import '../../services/api_client.dart';
import '../../services/cloudinary_service.dart';
import '../../services/account_flags.dart';
import '../../services/error_reporter.dart';
import '../../services/hiring_service.dart';
import '../../services/recruiter_profile_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/candidate_card_face.dart' show InitialsAvatar;
import '../../widgets/inputs/form_blocks.dart';
import '../../widgets/inputs/location_field.dart';
import 'company_profile_form.dart';
import 'onboarding/company_onboarding_form.dart' show kCompanySizes, kIndustries, canonicalCompanySize;
import 'onboarding/company_onboarding_screen.dart';
import 'verify/verify_company_screen.dart';

/// The company profile (spec C7): logo, about, contact and links, with an
/// "unsaved changes" bar. Candidates you shortlist see these details.
class CompanyProfileScreen extends StatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  State<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends State<CompanyProfileScreen> {
  final _name = TextEditingController();
  final _founded = TextEditingController();
  final _about = TextEditingController();
  final _website = TextEditingController();
  final _linkedin = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();

  CompanyProfileForm _form = CompanyProfileForm();
  CompanyProfileForm _saved = CompanyProfileForm();
  HiringCompany? _company;
  Map<String, String> _errors = {};
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  /// Only the account owner may rename the company or change its website.
  /// Unknown (not loaded yet) counts as owner; the server enforces the rule.
  bool get _isOwner => AccountFlagsService.forCurrentUser()?.isOwner ?? true;

  static const String _ownerOnlyHint = 'Only the account owner can change this';

  void _onFlags() {
    if (mounted) setState(() {});
  }

  List<TextEditingController> get _all => [_name, _founded, _about, _website, _linkedin, _phone, _email, _city, _address];

  @override
  void initState() {
    super.initState();
    AccountFlagsService.current.addListener(_onFlags);
    if (AccountFlagsService.forCurrentUser() == null) AccountFlagsService.refresh();
    _load();
  }

  @override
  void dispose() {
    AccountFlagsService.current.removeListener(_onFlags);
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }

  CompanyProfileForm _fromCompany(HiringCompany c) => CompanyProfileForm(
        name: c.name,
        industry: kIndustries.contains(c.industry) ? c.industry : '',
        size: canonicalCompanySize(c.size),
        foundedYear: c.foundedYear?.toString() ?? '',
        about: c.about,
        website: c.website,
        linkedin: c.linkedin,
        phone: c.phone,
        contactEmail: c.contactEmail,
        location: c.location,
        address: c.address,
      );

  void _apply(CompanyProfileForm f) {
    _name.text = f.name;
    _founded.text = f.foundedYear;
    _about.text = f.about;
    _website.text = f.website;
    _linkedin.text = f.linkedin;
    _phone.text = f.phone;
    _email.text = f.contactEmail;
    _city.text = f.location;
    _address.text = f.address;
    _form = f.copy();
  }

  void _syncFromControllers() {
    _form
      ..name = _name.text
      ..foundedYear = _founded.text
      ..about = _about.text
      ..website = _website.text
      ..linkedin = _linkedin.text
      ..phone = _phone.text
      ..contactEmail = _email.text
      ..location = _city.text
      ..address = _address.text;
  }

  bool get _dirty {
    _syncFromControllers();
    return !_form.sameAs(_saved);
  }

  Future<void> _load() async {
    try {
      final res = await HiringService.instance.fetchCompany();
      if (!mounted) return;
      final c = res.company;
      final f = c != null
          ? _fromCompany(c)
          : CompanyProfileForm(name: res.suggestedName.isNotEmpty ? res.suggestedName : RecruiterProfileService.instance.company);
      setState(() {
        _company = c;
        _saved = f.copy();
        _apply(f);
        _loading = false;
      });
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'CompanyProfileScreen: load failed');
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.error('Could not load your company', description: 'Check your connection and try again.');
    }
  }

  void _discard() => setState(() {
        _errors = {};
        _apply(_saved);
      });

  Future<void> _save() async {
    _syncFromControllers();
    final errors = _form.validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      AppToast.warning('Some details need fixing', description: errors.values.first);
      return;
    }
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final company = await HiringService.instance.saveCompany(_form.toBody());
      if (!mounted) return;
      final f = _fromCompany(company);
      setState(() {
        _company = company;
        _saved = f.copy();
        _apply(f);
        _saving = false;
      });
      AppToast.success('Company profile saved');
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.body['field'];
      setState(() {
        _saving = false;
        if (field is String && field.isNotEmpty) _errors = {field: e.message};
      });
      if (field is! String || field.isEmpty) AppToast.error('Could not save your company', description: e.message);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'CompanyProfileScreen: save failed');
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error('Could not save your company', description: 'Check your connection and try again.');
    }
  }

  Future<void> _pickLogo() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final file = files.isEmpty ? null : files.first;
    if (file == null || !mounted) return;
    final lower = file.name.toLowerCase();
    if (!(lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png') || lower.endsWith('.webp'))) {
      AppToast.error('Please choose a JPG, PNG or WebP image');
      return;
    }
    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (size > 3 * 1024 * 1024) {
      AppToast.error('Image must be under 3 MB');
      return;
    }
    setState(() => _uploading = true);
    try {
      final url = await CloudinaryService.instance.uploadPhoto(file);
      final company = await HiringService.instance.saveCompany({'logoUrl': url});
      if (mounted) {
        setState(() => _company = company);
        AppToast.success('Logo updated');
      }
    } on StateError catch (e) {
      if (mounted) AppToast.error('Could not upload the logo', description: e.message);
    } on ApiException catch (e) {
      if (mounted) AppToast.error('Could not save the logo', description: e.message);
    } catch (e, st) {
      ErrorReporter.report(e, st, reason: 'CompanyProfileScreen: logo upload failed');
      if (mounted) AppToast.error('Could not upload the logo', description: 'Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removeLogo() async {
    setState(() => _uploading = true);
    try {
      final company = await HiringService.instance.saveCompany({'logoUrl': ''});
      if (mounted) {
        setState(() => _company = company);
        AppToast.success('Logo removed');
      }
    } on ApiException catch (e) {
      if (mounted) AppToast.error(e.message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _quickEdit() async {
    final saved = await Navigator.of(context).push<HiringCompany>(
      MaterialPageRoute(
        builder: (_) => CompanyOnboardingScreen(
          edit: true,
          existing: _company,
          userName: RecruiterProfileService.instance.name,
        ),
      ),
    );
    if (saved != null && mounted) {
      final f = _fromCompany(saved);
      setState(() {
        _company = saved;
        _saved = f.copy();
        _apply(f);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dirty = !_loading && _dirty;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved changes.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep editing')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Discard')),
            ],
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: AppColors.bgTop,
        appBar: AppBar(
          title: const Text('Company profile'),
          actions: [
            if (!_loading && _company != null)
              TextButton(onPressed: _quickEdit, child: const Text('Edit basics')),
          ],
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    ListView(
                      padding: EdgeInsets.fromLTRB(20, 8, 20, dirty ? 100 : 32),
                      children: [
                        const Text(
                          'Candidates you shortlist see these details. A complete profile gets more replies.',
                          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                        ),
                        const SizedBox(height: 16),
                        _verificationCard(),
                        const SizedBox(height: 16),
                        _logoRow(),
                        const SizedBox(height: 20),
                        const _SectionTitle('About the company'),
                        FormFieldBlock(
                          label: 'Company name',
                          required: true,
                          error: _errors['name'],
                          hint: _isOwner ? null : _ownerOnlyHint,
                          child: TextField(
                            controller: _name,
                            readOnly: !_isOwner,
                            maxLength: 100,
                            textCapitalization: TextCapitalization.words,
                            style: _isOwner ? null : const TextStyle(color: AppColors.textSecondary),
                            decoration: fieldDecoration(
                              hasError: _errors.containsKey('name'),
                              prefix: const Icon(Icons.apartment_rounded, size: 20),
                              suffix: _isOwner ? null : const Icon(Icons.lock_outline_rounded, size: 18),
                            ),
                            onChanged: (_) => setState(() => _errors.remove('name')),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FormFieldBlock(
                          label: 'Industry',
                          child: SelectField(
                            value: _form.industry,
                            options: kIndustries,
                            onChanged: (v) => setState(() => _form.industry = v),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FormFieldBlock(
                          label: 'Company size',
                          child: SelectField(
                            value: _form.size,
                            options: kCompanySizes,
                            onChanged: (v) => setState(() => _form.size = v),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _text('Founded in', _founded, 'foundedYear',
                            hint: '2018', keyboard: TextInputType.number, icon: Icons.calendar_today_outlined),
                        const SizedBox(height: 14),
                        FormFieldBlock(
                          label: 'Description',
                          hint: 'What you do, your culture, why people love working with you',
                          child: TextField(
                            controller: _about,
                            maxLines: 5,
                            maxLength: 1500,
                            decoration: fieldDecoration(hintText: 'We build…'),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _SectionTitle('Contact & links'),
                        _text('Website', _website, 'website',
                            hint: 'yourcompany.com',
                            keyboard: TextInputType.url,
                            icon: Icons.language_rounded,
                            readOnly: !_isOwner),
                        const SizedBox(height: 14),
                        _text('LinkedIn page', _linkedin, 'linkedin',
                            hint: 'linkedin.com/company/…', keyboard: TextInputType.url, icon: Icons.link_rounded),
                        const SizedBox(height: 14),
                        _text('Contact number', _phone, 'phone',
                            hint: '+91 98765 43210', keyboard: TextInputType.phone, icon: Icons.phone_outlined),
                        const SizedBox(height: 14),
                        _text('Contact email', _email, 'contactEmail',
                            hint: 'careers@yourcompany.com',
                            helper: 'For candidates, e.g. careers@…',
                            keyboard: TextInputType.emailAddress,
                            icon: Icons.mail_outline_rounded),
                        const SizedBox(height: 14),
                        FormFieldBlock(
                          label: 'City',
                          required: true,
                          error: _errors['location'],
                          child: LocationField(
                            controller: _city,
                            hintText: 'Jaipur',
                            hasError: _errors.containsKey('location'),
                            onChanged: (_) => setState(() => _errors.remove('location')),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _text('Office address', _address, 'address',
                            hint: 'Floor, building, area', helper: 'Used for in-person interviews'),
                        const SizedBox(height: 12),
                        const Text(
                          'Changing the company name or website resets verification if the company was pending, verified or rejected.',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                    if (dirty)
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: AppColors.cardShadow(),
                          ),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'You have unsaved changes',
                                  style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w600),
                                ),
                              ),
                              TextButton(
                                onPressed: _saving ? null : _discard,
                                child: const Text('Discard', style: TextStyle(color: AppColors.onPrimaryMuted)),
                              ),
                              FilledButton(
                                onPressed: _saving ? null : _save,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.onPrimary,
                                  foregroundColor: AppColors.textPrimary,
                                  minimumSize: const Size(0, 40),
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Text('Save changes'),
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

  Widget _text(
    String label,
    TextEditingController controller,
    String field, {
    String? hint,
    String? helper,
    TextInputType? keyboard,
    IconData? icon,
    bool readOnly = false,
  }) {
    return FormFieldBlock(
      label: label,
      error: _errors[field],
      hint: readOnly ? _ownerOnlyHint : helper,
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        readOnly: readOnly,
        style: readOnly ? const TextStyle(color: AppColors.textSecondary) : null,
        decoration: fieldDecoration(
          hintText: hint,
          hasError: _errors.containsKey(field),
          prefix: icon == null ? null : Icon(icon, size: 20),
          suffix: readOnly ? const Icon(Icons.lock_outline_rounded, size: 18) : null,
        ),
        onChanged: (_) => setState(() => _errors.remove(field)),
      ),
    );
  }

  Future<void> _openVerify() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const VerifyCompanyScreen()));
    // The verify screen refreshed the shared company; keep unsaved edits.
    final latest = HiringService.company.value;
    if (mounted && latest != null) setState(() => _company = latest);
  }

  Widget _verificationCard() {
    final c = _company;
    if (c == null) return const SizedBox.shrink();
    final status = c.verified ? 'verified' : c.verificationStatus;
    final (color, icon, title, text, action) = switch (status) {
      'verified' => (
          AppColors.info,
          Icons.verified_rounded,
          'Verified company',
          'Candidates see a verified badge next to ${c.name}.',
          'View details',
        ),
      'pending' => (
          AppColors.warning,
          Icons.hourglass_top_rounded,
          'Verification under review',
          'We are reviewing your GSTIN. The badge appears once it is approved.',
          'View status',
        ),
      'rejected' => (
          AppColors.reject,
          Icons.error_outline_rounded,
          'Verification was not approved',
          'We could not verify your GSTIN. Check it, or verify with your work email instead.',
          'Try again',
        ),
      _ => (
          AppColors.textSecondary,
          Icons.shield_outlined,
          'Not verified yet',
          'Verify with your work email in a minute, or send your GSTIN for review.',
          'Get verified',
        ),
    };
    return Container(
      key: const Key('verification-card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w800))),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _openVerify,
            icon: const Icon(Icons.chevron_right_rounded, size: 18),
            label: Text(action),
          ),
        ],
      ),
    );
  }

  Widget _logoRow() {
    final name = _name.text.trim().isEmpty ? 'Company' : _name.text.trim();
    final logo = _company?.logoUrl ?? '';
    return Row(
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: logo.isEmpty
                ? InitialsAvatar(name: name)
                : CachedNetworkImage(
                    imageUrl: logo,
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
              const Text('Company logo', style: TextStyle(fontWeight: FontWeight.w700)),
              const Text(
                'JPG, PNG or WebP · up to 3 MB · square works best',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _uploading ? null : _pickLogo,
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                    child: _uploading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(logo.isEmpty ? 'Upload' : 'Change'),
                  ),
                  if (logo.isNotEmpty)
                    TextButton(onPressed: _uploading ? null : _removeLogo, child: const Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      );
}
