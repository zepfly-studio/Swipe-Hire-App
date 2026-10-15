import 'package:flutter/material.dart';

import '../../../models/hiring_company.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../services/hiring_service.dart';
import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/salary.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/autocomplete_field.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/location_field.dart';
import '../../../widgets/inputs/tag_input.dart';
import '../../auth/auth_gate.dart';
import '../jobs/job_form.dart' show kJobWorkModeLabels, kJobWorkModes;
import '../swipe/confetti_burst.dart';
import 'company_onboarding_form.dart';

/// Company onboarding (spec C1): step 1 "About your company", step 2 "Who are
/// you hiring?", then "You're all set!". One POST /company/onboarding at the
/// end. With [edit] it shows step 1 only and saves with PUT /company/me,
/// popping with the saved [HiringCompany].
class CompanyOnboardingScreen extends StatefulWidget {
  final String userName;
  final bool edit;
  final HiringCompany? existing;

  /// Called by "Start swiping" instead of routing through [AuthGate]
  /// (used when the screen is opened on top of an already-running shell).
  final VoidCallback? onFinished;
  final HiringService? service;

  const CompanyOnboardingScreen({
    super.key,
    this.userName = '',
    this.edit = false,
    this.existing,
    this.onFinished,
    this.service,
  });

  @override
  State<CompanyOnboardingScreen> createState() => _CompanyOnboardingScreenState();
}

class _CompanyOnboardingScreenState extends State<CompanyOnboardingScreen> {
  late final CompanyOnboardingForm _form;
  final _name = TextEditingController();
  final _location = TextEditingController();
  final _website = TextEditingController();
  final _about = TextEditingController();
  final _role = TextEditingController();
  final _minExp = TextEditingController();
  final _maxExp = TextEditingController();
  final _minSalary = TextEditingController();
  final _maxSalary = TextEditingController();
  final _jobLocation = TextEditingController();

  int _step = 0;
  bool _saving = false;
  bool _done = false;
  bool _loadingCompany = false;
  Map<String, String> _errors = {};
  String? _generalError;
  int _freeSwipes = 5;

  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing ?? HiringService.company.value;
    _form = existing != null ? CompanyOnboardingForm.fromCompany(existing) : CompanyOnboardingForm();
    _name.text = _form.name;
    _location.text = _form.location;
    _website.text = _form.website;
    _about.text = _form.about;
    TaxonomyService.instance.ensureLoaded();
    if (existing == null) _prefillName();
  }

  Future<void> _prefillName() async {
    setState(() => _loadingCompany = true);
    try {
      final res = await _service.fetchCompany();
      if (!mounted) return;
      final c = res.company;
      if (c != null) {
        final f = CompanyOnboardingForm.fromCompany(c, suggestedName: res.suggestedName);
        _form
          ..industry = f.industry
          ..size = f.size;
        if (_name.text.isEmpty) _name.text = f.name;
        if (_location.text.isEmpty) _location.text = f.location;
        if (_website.text.isEmpty) _website.text = f.website;
        if (_about.text.isEmpty) _about.text = f.about;
      } else if (_name.text.isEmpty) {
        _name.text = res.suggestedName;
      }
    } catch (_) {
      // Offline or not created yet: the form simply starts empty.
    } finally {
      if (mounted) setState(() => _loadingCompany = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _location, _website, _about, _role, _minExp, _maxExp, _minSalary, _maxSalary, _jobLocation]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    _form
      ..name = _name.text
      ..location = _location.text
      ..website = _website.text
      ..about = _about.text
      ..role = _role.text
      ..minExp = _minExp.text
      ..maxExp = _maxExp.text
      ..minSalary = _minSalary.text
      ..maxSalary = _maxSalary.text
      ..jobLocation = _jobLocation.text;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field) || _generalError != null) {
      setState(() {
        _errors = {..._errors}..remove(field);
        _generalError = null;
      });
    }
  }

  void _next() {
    _sync();
    final errors = _form.validateCompany();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    if (_jobLocation.text.trim().isEmpty) _jobLocation.text = _location.text.trim();
    setState(() {
      _errors = {};
      _step = 1;
    });
  }

  Future<void> _saveEdit() async {
    _sync();
    final errors = _form.validateCompany();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _generalError = null;
    });
    try {
      final saved = await _service.saveCompany(_form.companyBody());
      if (!mounted) return;
      AppToast.success('Company profile saved');
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.body['field'];
      setState(() {
        _saving = false;
        if (field is String && field.isNotEmpty) {
          _errors = {field.startsWith('company.') ? field : 'company.$field': e.message};
        } else {
          _generalError = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _generalError = 'Could not save. Please try again.';
      });
    }
  }

  Future<void> _finish() async {
    _sync();
    final errors = _form.validateAll();
    if (errors.isNotEmpty) {
      final first = errors.keys.map(onboardingStepForField).reduce((a, b) => a < b ? a : b);
      setState(() {
        _errors = errors;
        _step = first;
      });
      return;
    }
    setState(() {
      _saving = true;
      _generalError = null;
      _errors = {};
    });
    try {
      final body = _form.toRequestBody();
      final res = await _service.onboard(
        company: Map<String, dynamic>.from(body['company'] as Map),
        job: Map<String, dynamic>.from(body['job'] as Map),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _done = true;
        _freeSwipes = res.company.swipesLeft > 0 ? res.company.swipesLeft : (HiringService.swipesLeft.value > 0 ? HiringService.swipesLeft.value : 5);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      final field = e.body['field'];
      setState(() {
        _saving = false;
        if (field is String && field.isNotEmpty) {
          final key = field.contains('.') ? field : (onboardingStepForField(field) == 0 ? 'company.$field' : 'job.$field');
          _errors = {key: e.message};
          _step = onboardingStepForField(key);
        } else {
          _generalError = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _generalError = 'Something went wrong. Please try again.';
      });
    }
  }

  void _start() {
    final cb = widget.onFinished;
    if (cb != null) {
      cb();
      return;
    }
    // A fresh AuthGate re-reads the (now complete) account and routes home.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthGate()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = widget.userName.trim().split(RegExp(r'\s+')).first;
    return PopScope(
      canPop: widget.edit && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0 && !_saving && !_done) setState(() => _step = 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.bgTop,
        body: SafeArea(
          child: _done
              ? _DoneView(freeSwipes: _freeSwipes, onStart: _start)
              : Column(
                  children: [
                    _header(first),
                    Expanded(child: _card()),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _header(String first) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Swipe Hire',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.primary),
                ),
                if (first.isNotEmpty)
                  Text('Welcome, $first', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          ),
          if (widget.edit)
            TextButton.icon(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Cancel'),
            )
          else
            TextButton(
              onPressed: _saving ? null : () => AuthService.instance.signOut(),
              child: const Text('Log out'),
            ),
        ],
      ),
    );
  }

  Widget _card() {
    final total = widget.edit ? 1 : 2;
    final percent = ((_step + 1) * 100 ~/ total);
    final title = _step == 0 ? 'About your company' : 'Who are you hiring?';
    final subtitle = _step == 0 ? 'Candidates see this when you shortlist them' : 'We rank candidates by how well they match this';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    widget.edit ? 'Company details' : 'Step ${_step + 1} of $total',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                  const Spacer(),
                  if (!widget.edit)
                    Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ],
              ),
              if (!widget.edit) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent / 100,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceAlt,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: _step == 0 ? _stepCompany() : _stepJob(),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _footer() {
    final isLast = widget.edit || _step == 1;
    final label = widget.edit ? 'Save changes' : (_step == 0 ? 'Continue →' : 'Start swiping →');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_generalError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_generalError!, style: const TextStyle(color: AppColors.reject, fontSize: 13)),
            ),
          Row(
            children: [
              if (_step == 1 && !widget.edit) ...[
                OutlinedButton(
                  onPressed: _saving ? null : () => setState(() => _step = 0),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(56, 50)),
                  child: const Text('←'),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: FilledButton(
                  onPressed: _saving || _loadingCompany ? null : (widget.edit ? _saveEdit : (isLast ? _finish : _next)),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onPrimary),
                        )
                      : Text(label),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepCompany() {
    return Column(
      children: [
        FormFieldBlock(
          label: 'Company name',
          required: true,
          error: _errors['company.name'],
          child: TextField(
            controller: _name,
            maxLength: 100,
            textCapitalization: TextCapitalization.words,
            decoration: fieldDecoration(
              hintText: 'Acme Technologies',
              hasError: _errors.containsKey('company.name'),
              prefix: const Icon(Icons.apartment_rounded, size: 20),
            ),
            onChanged: (_) => _clearError('company.name'),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Industry',
          error: _errors['company.industry'],
          child: SelectField(
            value: _form.industry,
            options: kIndustries,
            onChanged: (v) => setState(() => _form.industry = v),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Company size',
          error: _errors['company.size'],
          child: SelectField(
            value: _form.size,
            options: kCompanySizes,
            onChanged: (v) => setState(() => _form.size = v),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Location',
          required: true,
          error: _errors['company.location'],
          child: LocationField(
            controller: _location,
            hintText: 'Jaipur',
            hasError: _errors.containsKey('company.location'),
            onChanged: (_) => _clearError('company.location'),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Website',
          error: _errors['company.website'],
          child: TextField(
            controller: _website,
            keyboardType: TextInputType.url,
            decoration: fieldDecoration(
              hintText: 'Optional',
              hasError: _errors.containsKey('company.website'),
              prefix: const Icon(Icons.language_rounded, size: 20),
            ),
            onChanged: (_) => _clearError('company.website'),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'About the company',
          hint: 'Optional',
          error: _errors['company.about'],
          child: TextField(
            controller: _about,
            maxLines: 4,
            maxLength: 600,
            decoration: fieldDecoration(
              hintText: 'What do you do? Why is it great to work with you?',
              hasError: _errors.containsKey('company.about'),
            ),
            onChanged: (_) => _clearError('company.about'),
          ),
        ),
      ],
    );
  }

  Widget _stepJob() {
    final minHint = parseLpa(_minSalary.text);
    final maxHint = parseLpa(_maxSalary.text);
    return Column(
      children: [
        FormFieldBlock(
          label: 'Role you are hiring for',
          required: true,
          error: _errors['job.title'],
          child: ValueListenableBuilder<Taxonomy>(
            valueListenable: TaxonomyService.instance.notifier,
            builder: (context, tax, _) => AutocompleteField(
              controller: _role,
              options: tax.roles,
              hintText: 'e.g. Frontend Developer',
              hasError: _errors.containsKey('job.title'),
              onChanged: (_) => _clearError('job.title'),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Skills you need',
          required: true,
          error: _errors['job.skills'],
          hint: 'Candidates with these skills are shown first · comma adds exactly what you typed',
          child: ValueListenableBuilder<Taxonomy>(
            valueListenable: TaxonomyService.instance.notifier,
            builder: (context, tax, _) => TagInput(
              tags: _form.skills,
              options: tax.skills,
              hintText: 'React, JavaScript…',
              hasError: _errors.containsKey('job.skills'),
              onChanged: (v) => setState(() {
                _form.skills = v;
                _errors = {..._errors}..remove('job.skills');
              }),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _num('Min experience (yrs)', _minExp, '0', 'job.minExperienceYears')),
            const SizedBox(width: 12),
            Expanded(child: _num('Max experience (yrs)', _maxExp, '5', 'job.maxExperienceYears')),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _num('Min salary (LPA)', _minSalary, '3', 'job.salaryMinLpa',
                  hint: _minSalary.text.trim().isEmpty ? null : minHint.hint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _num('Max salary (LPA)', _maxSalary, '8', 'job.salaryMaxLpa',
                  required: true, hint: maxHint.hint),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Job location',
          child: LocationField(controller: _jobLocation, hintText: 'Jaipur'),
        ),
        const SizedBox(height: 14),
        FormFieldBlock(
          label: 'Work mode',
          child: ChipSelect(
            options: kJobWorkModes,
            labels: kJobWorkModeLabels,
            value: _form.workMode,
            onChanged: (v) => setState(() => _form.workMode = v),
          ),
        ),
      ],
    );
  }

  Widget _num(String label, TextEditingController c, String placeholder, String field,
      {bool required = false, String? hint}) {
    return FormFieldBlock(
      label: label,
      required: required,
      error: _errors[field],
      hint: hint,
      child: TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: fieldDecoration(hintText: placeholder, hasError: _errors.containsKey(field)),
        onChanged: (_) {
          _clearError(field);
          setState(() {});
        },
      ),
    );
  }
}

class _DoneView extends StatelessWidget {
  final int freeSwipes;
  final VoidCallback onStart;
  const _DoneView({required this.freeSwipes, required this.onStart});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ConfettiBurst(count: 60)),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, size: 46, color: AppColors.primary),
                ),
                const SizedBox(height: 22),
                const Text("You're all set!", style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                Text(
                  'You have $freeSwipes free swipes. Swipe right to shortlist a candidate, left to pass.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, height: 1.45, fontSize: 14.5),
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: onStart,
                  style: FilledButton.styleFrom(minimumSize: const Size(220, 50)),
                  child: const Text('Start swiping', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
