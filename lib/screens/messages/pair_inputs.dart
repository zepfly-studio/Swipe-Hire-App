import 'package:flutter/material.dart';
import '../../models/pair/pair_format.dart';
import '../../theme/app_theme.dart';

/// Date picker followed by a time picker. Returns null when cancelled.
Future<DateTime?> pickPairDateTime(
  BuildContext context, {
  required DateTime initial,
  DateTime? first,
  DateTime? last,
}) async {
  final now = DateTime.now();
  final firstDate = first ?? DateTime(now.year, now.month, now.day);
  final lastDate = last ?? now.add(const Duration(days: 365));
  var init = initial;
  if (init.isBefore(firstDate)) init = firstDate;
  if (init.isAfter(lastDate)) init = lastDate;
  final date = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: firstDate,
    lastDate: lastDate,
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

/// A tappable date-time "field" (the mobile stand-in for `datetime-local`).
class DateTimeField extends StatelessWidget {
  final DateTime? value;
  final String placeholder;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool hasError;

  const DateTimeField({
    super.key,
    required this.value,
    required this.onTap,
    this.placeholder = 'Pick date and time',
    this.onRemove,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hasError ? AppColors.reject : AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_rounded, size: 18, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      value == null ? placeholder : formatPairDateTime(value!),
                      style: TextStyle(
                        fontSize: 14.5,
                        color: value == null ? AppColors.textTertiary : AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            tooltip: 'Remove',
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.reject),
          ),
      ],
    );
  }
}
