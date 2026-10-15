import 'package:flutter/material.dart';

import '../../../models/hiring_job.dart';
import '../../../services/api_client.dart';
import '../../../services/hiring_service.dart';
import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/salary.dart';
import '../../../widgets/app_toast.dart';
import '../../../widgets/inputs/autocomplete_field.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/location_field.dart';
import '../../../widgets/inputs/tag_input.dart';
import 'job_form.dart';

/// "Post a new job" / "Edit job". Resolves with the saved job, or null.
Future<HiringJob?> showJobFormSheet(
  BuildContext context, {
  HiringJob? job,
  String defaultLocation = '',
  HiringService? service,
}) {
  return showModalBottomSheet<HiringJob>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.bgTop,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => JobFormSheet(job: job, defaultLocation: defaultLocation, service: service),
  );
}

class JobFormSheet extends StatefulWidget {
  final HiringJob? job;
  final String defaultLocation;
  final HiringService? service;

  const JobFormSheet({super.key, this.job, this.defaultLocation = '', this.service});

  @override
  State<JobFormSheet> createState() => _JobFormSheetState();
}

class _JobFormSheetState extends State<JobFormSheet> {
  late final JobForm _form;
  late final TextEditingController _title;
  late final TextEditingController _minExp;
  late final TextEditingController _maxExp;
  late final TextEditingController _minSalary;
  late final TextEditingController _maxSalary;
  late final TextEditingController _location;
  late final TextEditingController _openings;
  late final TextEditingController _description;
  Map<String, String> _errors = {};
  bool _saving = false;

  bool get _edit => widget.job != null;
  HiringService get _service => widget.service ?? HiringService.instance;

  @override
  void initState() {
    super.initState();
    _form = _edit ? JobForm.fromJob(widget.job!) : JobForm(location: widget.defaultLocation);
    _title = TextEditingController(text: _form.title);
    _minExp = TextEditingController(text: _form.minExp);
    _maxExp = TextEditingController(text: _form.maxExp);
    _minSalary = TextEditingController(text: _form.minSalary);
    _maxSalary = TextEditingController(text: _form.maxSalary);
    _location = TextEditingController(text: _form.location);
    _openings = TextEditingController(text: _form.openings);
    _description = TextEditingController(text: _form.description);
    TaxonomyService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    for (final c in [_title, _minExp, _maxExp, _minSalary, _maxSalary, _location, _openings, _description]) {
      c.dispose();
    }
    super.dispose();
  }

  void _sync() {
    _form
      ..title = _title.text
      ..minExp = _minExp.text
      ..maxExp = _maxExp.text
      ..minSalary = _minSalary.text
      ..maxSalary = _maxSalary.text
      ..location = _location.text
      ..openings = _openings.text
      ..description = _description.text;
  }

  void _clearError(String field) {
    if (_errors.containsKey(field)) setState(() => _errors = {..._errors}..remove(field));
  }

  Future<void> _save() async {
    if (_saving) return;
    _sync();
    final errors = _form.validate();
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final body = _form.toBody();
      final saved = _edit ? await _service.updateJob(widget.job!.id, body) : await _service.createJob(body);
      if (!mounted) return;
      AppToast.success(_edit ? 'Job updated' : 'Job posted! Start swiping for it.');
      Navigator.of(context).pop(saved);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final field = e.body['field'];
      if (field is String && field.isNotEmpty) {
        setState(() => _errors = {field: e.message});
      } else {
        AppToast.error(e.message);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.error('Could not save the job. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final minHint = parseLpa(_minSalary.text);
    final maxHint = parseLpa(_maxSalary.text);
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 8, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _edit ? 'Edit job' : 'Post a new job',
                        style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Candidates are ranked against these requirements',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              children: [
                FormFieldBlock(
                  label: 'Job title',
                  required: true,
                  error: _errors['title'],
                  child: ValueListenableBuilder<Taxonomy>(
                    valueListenable: TaxonomyService.instance.notifier,
                    builder: (context, tax, _) => AutocompleteField(
                      controller: _title,
                      options: tax.roles,
                      hintText: 'e.g. Frontend Developer',
                      hasError: _errors.containsKey('title'),
                      maxLength: 80,
                      onChanged: (_) => _clearError('title'),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Skills you need',
                  required: true,
                  error: _errors['skills'],
                  hint: 'Candidates with these skills are shown first',
                  child: ValueListenableBuilder<Taxonomy>(
                    valueListenable: TaxonomyService.instance.notifier,
                    builder: (context, tax, _) => TagInput(
                      tags: _form.skills,
                      options: tax.skills,
                      hintText: 'React, JavaScript…',
                      hasError: _errors.containsKey('skills'),
                      onChanged: (v) => setState(() {
                        _form.skills = v;
                        _errors = {..._errors}..remove('skills');
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _numField('Min experience (yrs)', _minExp, '0', 'minExperienceYears')),
                    const SizedBox(width: 12),
                    Expanded(child: _numField('Max experience (yrs)', _maxExp, '5', 'maxExperienceYears')),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _numField('Min salary (LPA)', _minSalary, '3', 'salaryMinLpa',
                          hint: _minSalary.text.trim().isEmpty ? null : minHint.hint),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _numField('Max salary (LPA)', _maxSalary, '8', 'salaryMaxLpa',
                          required: true, hint: maxHint.hint),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Job location',
                  error: _errors['location'],
                  child: LocationField(
                    controller: _location,
                    hintText: 'Jaipur',
                    hasError: _errors.containsKey('location'),
                    onChanged: (_) => _clearError('location'),
                  ),
                ),
                const SizedBox(height: 14),
                _numField('Openings', _openings, '1', 'openings', integer: true),
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
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Job type',
                  child: ChipSelect(
                    options: kJobTypeValues,
                    labels: kJobTypeLabelsMap,
                    value: _form.employmentType,
                    onChanged: (v) => setState(() => _form.employmentType = v),
                  ),
                ),
                const SizedBox(height: 14),
                FormFieldBlock(
                  label: 'Description',
                  error: _errors['description'],
                  hint: 'Optional · shown to candidates you shortlist',
                  child: TextField(
                    controller: _description,
                    maxLines: 4,
                    maxLength: 3000,
                    decoration: fieldDecoration(
                      hintText: "What will this person do? What's great about the team?",
                      hasError: _errors.containsKey('description'),
                    ),
                    onChanged: (_) => _clearError('description'),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: SafeArea(
              top: false,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                      )
                    : Text(_edit ? 'Save changes' : 'Post job'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(
    String label,
    TextEditingController controller,
    String placeholder,
    String field, {
    bool required = false,
    bool integer = false,
    String? hint,
  }) {
    return FormFieldBlock(
      label: label,
      required: required,
      error: _errors[field],
      hint: hint,
      child: TextField(
        controller: controller,
        keyboardType: integer ? TextInputType.number : const TextInputType.numberWithOptions(decimal: true),
        decoration: fieldDecoration(hintText: placeholder, hasError: _errors.containsKey(field)),
        onChanged: (_) {
          _clearError(field);
          setState(() {});
        },
      ),
    );
  }
}
