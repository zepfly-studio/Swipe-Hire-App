/// Salary inputs are in LPA (lakh rupees per year). A value of 1000 or more
/// is taken to be a yearly rupee amount and converted (/ 100000).
class LpaValue {
  const LpaValue({this.value, this.converted = false, this.rawRupees = 0});

  /// The amount in LPA, or null when the text is not a usable number.
  final double? value;

  /// True when the typed number was a rupee amount that got converted.
  final bool converted;
  final double rawRupees;

  bool get valid => value != null;

  /// Shown under the input: the conversion when one happened, else the unit.
  String get hint => converted
      ? '= ₹${_trim(value!)} LPA (₹${formatInr(rawRupees)} per year)'
      : 'In lakh per year, e.g. 4.5';
}

String _trim(double v) {
  final fixed = v.toStringAsFixed(2);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
      : fixed;
}

/// Parses text like "6", "4.5", "450000" or "4,50,000".
LpaValue parseLpa(String text) {
  final cleaned = text
      .trim()
      .replaceAll(',', '')
      .replaceAll(RegExp(r'\s+'), '');
  if (cleaned.isEmpty || !RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) {
    return const LpaValue();
  }
  final n = double.tryParse(cleaned);
  if (n == null || n.isNaN || n.isInfinite) return const LpaValue();
  if (n >= 1000) {
    final lpa = n / 100000;
    if (lpa > 1000) return const LpaValue();
    return LpaValue(value: lpa, converted: true, rawRupees: n);
  }
  return LpaValue(value: n);
}

/// 450000 -> "4,50,000" (Indian digit grouping).
String formatInr(num amount) {
  final s = amount.round().toString();
  if (s.length <= 3) return s;
  final head = s.substring(0, s.length - 3);
  final tail = s.substring(s.length - 3);
  final buf = StringBuffer();
  for (var i = 0; i < head.length; i++) {
    if (i > 0 && (head.length - i).isEven) buf.write(',');
    buf.write(head[i]);
  }
  return '$buf,$tail';
}

/// Minimum expected salary (required).
String? validateMinSalary(String text) {
  if (text.trim().isEmpty) return 'Enter the minimum salary you expect';
  final v = parseLpa(text).value;
  if (v == null || v <= 0) return 'Enter a valid salary';
  return null;
}

/// Current salary (optional).
String? validateCurrentSalary(String text) {
  if (text.trim().isEmpty) return null;
  return parseLpa(text).valid ? null : 'Enter a valid salary';
}

/// Maximum expected salary (optional, must exceed the minimum when given).
String? validateMaxSalary(String text, String minText) {
  if (text.trim().isEmpty) return null;
  final v = parseLpa(text).value;
  if (v == null || v <= 0) return 'Enter a valid salary';
  final min = parseLpa(minText).value;
  if (min != null && v <= min) return 'Should be more than the minimum';
  return null;
}

/// Years of experience from the form text; null when not a number.
double? parseYears(String text) =>
    double.tryParse(text.trim().replaceAll(',', '.'));

/// "Experience (years)": required, 0 = fresher, 0..50.
String? validateExperienceYears(String text) {
  if (text.trim().isEmpty) return 'Enter your experience (0 if fresher)';
  final v = parseYears(text);
  if (v == null || v < 0 || v > 50) return 'Enter years between 0 and 50';
  return null;
}

/// What the server stores: "Fresher" for 0, else `<n> years`.
String experienceTextFor(double years) {
  if (years <= 0) return 'Fresher';
  final n = years == years.roundToDouble()
      ? years.round().toString()
      : years.toString();
  return '$n years';
}

/// "₹6–8 LPA · Negotiable" style summary, empty when there is no minimum.
String salaryRangeLabel(double min, double max, {bool negotiable = false}) {
  if (min <= 0) return '';
  String f(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
  final range = max > min ? '${f(min)}–${f(max)}' : f(min);
  return '₹$range LPA${negotiable ? ' · Negotiable' : ''}';
}
