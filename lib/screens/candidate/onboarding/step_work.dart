import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/salary.dart';
import '../../../widgets/inputs/autocomplete_field.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/tag_input.dart';
import 'onboarding_form.dart';

/// Step 1 -- "Your work & skills".
class StepWork extends StatefulWidget {
  final OnboardingForm form;
  final Map<String, String> errors;
  final void Function(String field) onEdited;

  const StepWork({
    super.key,
    required this.form,
    required this.errors,
    required this.onEdited,
  });

  @override
  State<StepWork> createState() => _StepWorkState();
}

class _StepWorkState extends State<StepWork> {
  late final TextEditingController _role = TextEditingController(
    text: widget.form.desiredRole,
  );
  late final TextEditingController _experience = TextEditingController(
    text: widget.form.experience,
  );
  late final TextEditingController _company = TextEditingController(
    text: widget.form.currentCompany,
  );
  late final TextEditingController _post = TextEditingController(
    text: widget.form.currentPost,
  );
  late final TextEditingController _currentSalary = TextEditingController(
    text: widget.form.currentSalary,
  );
  late final TextEditingController _min = TextEditingController(
    text: widget.form.expectedMin,
  );
  late final TextEditingController _max = TextEditingController(
    text: widget.form.expectedMax,
  );
  late final TextEditingController _about = TextEditingController(
    text: widget.form.about,
  );

  @override
  void initState() {
    super.initState();
    TaxonomyService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    for (final c in [
      _role,
      _experience,
      _company,
      _post,
      _currentSalary,
      _min,
      _max,
      _about,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  OnboardingForm get f => widget.form;
  String? _err(String key) => widget.errors[key];

  static final _decimal = FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'));

  /// The unit hint, or the rupee -> LPA conversion once 1000+ is typed.
  String _lpaHint(
    String text, {
    String fallback = 'In lakh per year, e.g. 4.5',
  }) {
    final p = parseLpa(text);
    return p.converted ? p.hint : fallback;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Taxonomy>(
      valueListenable: TaxonomyService.instance.notifier,
      builder: (context, t, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FormFieldBlock(
            label: 'Role you are looking for',
            required: true,
            error: _err('desiredRole'),
            child: AutocompleteField(
              controller: _role,
              options: t.roles,
              hintText: 'e.g. Web Developer, Sales Executive',
              maxLength: 80,
              hasError: _err('desiredRole') != null,
              onChanged: (v) {
                f.desiredRole = v;
                widget.onEdited('desiredRole');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Your skills',
            required: true,
            error: _err('skills'),
            hint:
                'Enter adds the highlighted skill · type a comma to add exactly what you typed',
            child: TagInput(
              tags: f.skills,
              options: t.skills,
              max: 30,
              hintText: 'React, Excel, Communication…',
              hasError: _err('skills') != null,
              onChanged: (v) {
                setState(() => f.skills = v);
                widget.onEdited('skills');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Experience (years)',
            required: true,
            error: _err('experience'),
            child: TextField(
              controller: _experience,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [_decimal],
              decoration: fieldDecoration(
                hintText: '0 if fresher',
                hasError: _err('experience') != null,
              ),
              onChanged: (v) {
                f.experience = v;
                widget.onEdited('experience');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Notice period',
            child: SelectField(
              value: f.noticePeriod,
              options: kNoticePeriods,
              onChanged: (v) {
                setState(() => f.noticePeriod = v);
                widget.onEdited('noticePeriod');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Current / last company',
            error: _err('currentCompany'),
            child: TextField(
              controller: _company,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              decoration: fieldDecoration(
                hintText: 'Optional',
                hasError: _err('currentCompany') != null,
              ),
              onChanged: (v) {
                f.currentCompany = v;
                widget.onEdited('currentCompany');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Current / last post',
            error: _err('currentPost'),
            child: AutocompleteField(
              controller: _post,
              options: t.roles,
              hintText: 'Optional',
              maxLength: 80,
              hasError: _err('currentPost') != null,
              onChanged: (v) {
                f.currentPost = v;
                widget.onEdited('currentPost');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Current salary (LPA)',
            error: _err('currentSalaryLpa'),
            hint: _lpaHint(f.currentSalary),
            child: TextField(
              controller: _currentSalary,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [_decimal],
              decoration: fieldDecoration(
                hintText: 'e.g. 4.5',
                hasError: _err('currentSalaryLpa') != null,
              ),
              onChanged: (v) {
                setState(() => f.currentSalary = v);
                widget.onEdited('currentSalaryLpa');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Expected salary (LPA) · minimum',
            required: true,
            error: _err('expectedSalaryLpa'),
            hint: _lpaHint(f.expectedMin),
            child: TextField(
              controller: _min,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [_decimal],
              decoration: fieldDecoration(
                hintText: 'e.g. 6',
                hasError: _err('expectedSalaryLpa') != null,
              ),
              onChanged: (v) {
                setState(() => f.expectedMin = v);
                widget.onEdited('expectedSalaryLpa');
                widget.onEdited('expectedSalaryMaxLpa');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Expected salary (LPA) · maximum',
            error: _err('expectedSalaryMaxLpa'),
            hint: _lpaHint(f.expectedMax, fallback: 'Optional'),
            child: TextField(
              controller: _max,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              inputFormatters: [_decimal],
              decoration: fieldDecoration(
                hintText: 'e.g. 8',
                hasError: _err('expectedSalaryMaxLpa') != null,
              ),
              onChanged: (v) {
                setState(() => f.expectedMax = v);
                widget.onEdited('expectedSalaryMaxLpa');
              },
            ),
          ),
          const SizedBox(height: 14),
          _NegotiableTile(
            value: f.negotiable,
            onChanged: (v) {
              setState(() => f.negotiable = v);
              widget.onEdited('salaryNegotiable');
            },
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Preferred work mode (optional)',
            child: MultiChipSelect(
              options: kWorkModes,
              labels: kWorkModeLabels,
              values: f.workModes,
              onChanged: (v) {
                setState(() => f.workModes = v);
                widget.onEdited('workModes');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'Job type (optional)',
            child: MultiChipSelect(
              options: kJobTypes,
              labels: kJobTypeLabels,
              values: f.jobTypes,
              onChanged: (v) {
                setState(() => f.jobTypes = v);
                widget.onEdited('jobTypes');
              },
            ),
          ),
          const SizedBox(height: 16),
          FormFieldBlock(
            label: 'About you',
            error: _err('about'),
            hint: '2–3 lines that make you stand out (optional)',
            child: TextField(
              controller: _about,
              maxLines: 4,
              minLines: 3,
              maxLength: 600,
              textCapitalization: TextCapitalization.sentences,
              decoration: fieldDecoration(
                hintText: 'I build fast, accessible web apps…',
                hasError: _err('about') != null,
                showCounter: true,
              ),
              onChanged: (v) {
                f.about = v;
                widget.onEdited('about');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NegotiableTile extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const _NegotiableTile({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'My salary is negotiable',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  value
                      ? 'Companies can shortlist you even if their budget is below your minimum.'
                      : 'Only companies whose budget reaches your minimum can shortlist you.',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
