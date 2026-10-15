import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// A form field in the website's style: a small uppercase letter-spaced
/// label, the control, then an error in the danger colour. The [hint] shows
/// only while there is no error.
class FormFieldBlock extends StatelessWidget {
  final String label;
  final bool required;
  final Widget child;
  final String? error;
  final String? hint;

  const FormFieldBlock({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.error,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              text: label.toUpperCase(),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.reject),
                  ),
              ],
            ),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        child,
        if (error != null && error!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              error!,
              style: const TextStyle(
                color: AppColors.reject,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          )
        else if (hint != null && hint!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              hint!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          ),
      ],
    );
  }
}

/// The shared look of every text input.
InputDecoration fieldDecoration({
  String? hintText,
  bool hasError = false,
  Widget? suffix,
  Widget? prefix,
  bool showCounter = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: AppColors.surface,
    isDense: true,
    counterText: showCounter ? null : '',
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    prefixIcon: prefix,
    suffixIcon: suffix,
    border: border(hasError ? AppColors.reject : AppColors.border),
    enabledBorder: border(hasError ? AppColors.reject : AppColors.border),
    focusedBorder: border(hasError ? AppColors.reject : AppColors.primary, 1.5),
  );
}

/// Single choice shown as chips (Gender).
class ChipSelect extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final Map<String, String> labels;

  const ChipSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.labels = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          _SelectableChip(
            label: labels[o] ?? o,
            selected: o == value,
            onTap: () => onChanged(o),
          ),
      ],
    );
  }
}

/// Multiple choice shown as toggle chips (work mode, job type).
class MultiChipSelect extends StatelessWidget {
  final List<String> options;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final Map<String, String> labels;

  const MultiChipSelect({
    super.key,
    required this.options,
    required this.values,
    required this.onChanged,
    this.labels = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          _SelectableChip(
            label: labels[o] ?? o,
            selected: values.contains(o),
            onTap: () {
              final next = values.contains(o)
                  ? values.where((v) => v != o).toList()
                  : [...values, o];
              // Keep the option order stable so equality checks stay simple.
              next.sort(
                (a, b) => options.indexOf(a).compareTo(options.indexOf(b)),
              );
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SelectableChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Material(
        color: selected ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A select whose first entry "Select" acts as the placeholder.
class SelectField extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool hasError;

  const SelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final current = options.contains(value) ? value : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('select-$current'),
      initialValue: current,
      isExpanded: true,
      icon: const Icon(Icons.keyboard_arrow_down_rounded),
      decoration: fieldDecoration(hasError: hasError),
      items: [
        const DropdownMenuItem(
          value: '',
          child: Text(
            'Select',
            style: TextStyle(color: AppColors.textTertiary),
          ),
        ),
        for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}
