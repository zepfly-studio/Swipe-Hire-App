/// "3 years" -> 3, "1.5 years" -> 1.5, "Fresher" -> 0, "6 months" -> 0.5.
/// Mirrors backend/src/lib/derive.js so the app and the server agree on
/// what a candidate's free-text experience means.
double parseExperienceYears(String text) {
  final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
  if (match == null) return 0;
  final n = double.parse(match.group(0)!);
  final lower = text.toLowerCase();
  if (lower.contains('month') && !lower.contains('year') && !lower.contains('yr')) {
    return (n / 12 * 10).round() / 10;
  }
  return n;
}
