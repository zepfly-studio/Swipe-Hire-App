import 'package:flutter/material.dart';

import '../../../models/hiring_company.dart';
import '../../../services/api_client.dart';
import '../../../services/auth_service.dart';
import '../../../services/hiring_service.dart';
import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/location_field.dart';
import '../../auth/auth_gate.dart';
import '../swipe/confetti_burst.dart';
import 'company_onboarding_form.dart';

/// Company onboarding: "About your company", then "You're all set!" (there
/// is no job step: recruiters filter candidates on the Swipe tab). One POST
/// /company/onboarding. With [edit] it saves with PUT /company/me instead,
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
    for (final c in [_name, _location, _website, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    _form
      ..name = _name.text
      ..location = _location.text
      ..website = _website.text
      ..about = _about.text;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field) || _generalError != null) {
      setState(() {
        _errors = {..._errors}..remove(field);
        _generalError = null;
      });
    }
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
    final errors = _form.validateCompany();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _generalError = null;
      _errors = {};
    });
    try {
      final res = await _service.onboard(company: _form.companyBody());
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
          _errors = {field.contains('.') ? field : 'company.$field': e.message};
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
                  'GlideRecruit',
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              const Text('About your company', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              const Text(
                'Candidates see this when you shortlist them',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: _stepCompany(),
          ),
        ),
        _footer(),
      ],
    );
  }

  Widget _footer() {
    final label = widget.edit ? 'Save changes' : 'Continue →';
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
              Expanded(
                child: FilledButton(
                  onPressed: _saving || _loadingCompany ? null : (widget.edit ? _saveEdit : _finish),
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
