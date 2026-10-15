import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/taxonomy_service.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/inputs/autocomplete_field.dart';
import '../../../widgets/inputs/form_blocks.dart';
import '../../../widgets/inputs/location_field.dart';
import 'onboarding_form.dart';
import 'onboarding_media.dart';

/// Where the resume auto-fill box is in its little life cycle.
enum AutofillPhase { idle, uploading, reading, done }

/// Step 0 -- "Tell us about yourself".
class StepDetails extends StatefulWidget {
  final OnboardingForm form;
  final Map<String, String> errors;

  /// Called after any edit with the field name that changed.
  final void Function(String field) onEdited;

  // Resume auto-fill box (only shown when there is no resume yet).
  final bool showAutofill;
  final AutofillPhase autofillPhase;
  final double autofillProgress;
  final int autofillFilled;
  final String? autofillError;
  final VoidCallback onPickResume;

  const StepDetails({
    super.key,
    required this.form,
    required this.errors,
    required this.onEdited,
    required this.showAutofill,
    required this.autofillPhase,
    required this.autofillProgress,
    required this.autofillFilled,
    required this.autofillError,
    required this.onPickResume,
  });

  @override
  State<StepDetails> createState() => _StepDetailsState();
}

class _StepDetailsState extends State<StepDetails> {
  late final TextEditingController _phone = TextEditingController(
    text: widget.form.phone,
  );
  late final TextEditingController _age = TextEditingController(
    text: widget.form.age,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.form.location,
  );
  late final TextEditingController _degree = TextEditingController(
    text: widget.form.degree,
  );
  late final TextEditingController _college = TextEditingController(
    text: widget.form.college,
  );
  late final TextEditingController _year = TextEditingController(
    text: widget.form.graduationYear,
  );

  @override
  void initState() {
    super.initState();
    TaxonomyService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    for (final c in [_phone, _age, _location, _degree, _college, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  OnboardingForm get f => widget.form;
  String? _err(String key) => widget.errors[key];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showAutofill) ...[
          _AutofillBox(
            phase: widget.autofillPhase,
            progress: widget.autofillProgress,
            filled: widget.autofillFilled,
            error: widget.autofillError,
            onPick: widget.onPickResume,
          ),
          const SizedBox(height: 18),
        ],
        FormFieldBlock(
          label: 'Phone number',
          required: true,
          error: _err('phone'),
          child: TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            maxLength: 20,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
            ],
            decoration: fieldDecoration(
              hintText: '98765 43210',
              hasError: _err('phone') != null,
            ),
            onChanged: (v) {
              f.phone = v;
              widget.onEdited('phone');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Age',
          required: true,
          error: _err('age'),
          hint: 'Never shown to companies.',
          child: TextField(
            controller: _age,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            maxLength: 3,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDecoration(
              hintText: '24',
              hasError: _err('age') != null,
            ),
            onChanged: (v) {
              f.age = v;
              widget.onEdited('age');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Gender',
          required: true,
          error: _err('gender'),
          hint: 'Never shown to companies.',
          child: ChipSelect(
            options: kGenders,
            value: f.gender,
            onChanged: (v) {
              setState(() => f.gender = v);
              widget.onEdited('gender');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Current city',
          required: true,
          error: _err('location'),
          child: LocationField(
            controller: _location,
            hintText: 'Jaipur',
            hasError: _err('location') != null,
            onChanged: (v) {
              f.location = v;
              widget.onEdited('location');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Highest qualification',
          required: true,
          error: _err('qualification'),
          child: SelectField(
            value: f.qualification,
            options: kQualifications,
            hasError: _err('qualification') != null,
            onChanged: (v) {
              setState(() => f.qualification = v);
              widget.onEdited('qualification');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Degree / course',
          required: true,
          error: _err('degree'),
          child: ValueListenableBuilder<Taxonomy>(
            valueListenable: TaxonomyService.instance.notifier,
            builder: (context, t, _) => AutocompleteField(
              controller: _degree,
              options: t.degrees,
              hintText: 'B.Tech (CSE)',
              maxLength: 80,
              hasError: _err('degree') != null,
              onChanged: (v) {
                f.degree = v;
                widget.onEdited('degree');
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'College / university',
          error: _err('college'),
          child: TextField(
            controller: _college,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            decoration: fieldDecoration(
              hintText: 'Optional',
              hasError: _err('college') != null,
            ),
            onChanged: (v) {
              f.college = v;
              widget.onEdited('college');
            },
          ),
        ),
        const SizedBox(height: 16),
        FormFieldBlock(
          label: 'Passing year',
          error: _err('graduationYear'),
          child: TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: fieldDecoration(
              hintText: '2023',
              hasError: _err('graduationYear') != null,
            ),
            onChanged: (v) {
              f.graduationYear = v;
              widget.onEdited('graduationYear');
            },
          ),
        ),
      ],
    );
  }
}

class _AutofillBox extends StatelessWidget {
  final AutofillPhase phase;
  final double progress;
  final int filled;
  final String? error;
  final VoidCallback onPick;

  const _AutofillBox({
    required this.phase,
    required this.progress,
    required this.filled,
    required this.error,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (phase == AutofillPhase.done) {
      return NoteBox(
        icon: Icons.check_circle_outline_rounded,
        text: filled > 0
            ? 'Resume uploaded · $filled field${filled == 1 ? '' : 's'} filled for you. '
                  "You won't need to upload it again."
            : "Resume uploaded. You won't need to upload it again.",
      );
    }
    final busy =
        phase == AutofillPhase.uploading || phase == AutofillPhase.reading;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.auto_awesome_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Save time: fill this from your resume',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            "Upload your PDF resume and we'll fill in your skills, college, experience, last company and more.",
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          if (busy) ...[
            LinearProgressIndicator(
              value: phase == AutofillPhase.uploading
                  ? progress.clamp(0.02, 1.0)
                  : null,
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
              backgroundColor: AppColors.surfaceAlt,
            ),
            const SizedBox(height: 8),
            Text(
              phase == AutofillPhase.uploading
                  ? 'Uploading… ${(progress * 100).round()}%'
                  : 'Reading your resume…',
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else
            OutlinedButton.icon(
              onPressed: onPick,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.upload_file_rounded, size: 18),
              label: const Text('Upload resume & auto-fill'),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(color: AppColors.reject, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}
