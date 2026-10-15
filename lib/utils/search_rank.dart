/// Suggestion ranking shared by every autocomplete (website spec B0).
///
/// Score: exact 4 > starts-with 3 > every typed word starts a word 2 >
/// contains, or a loose typo match, 1. The loose match needs at least three
/// letters, the same first letter, and the typed letters appearing in order.
/// 0 means "not a match". Ties keep the list order (most popular first).
int searchScore(String query, String option) {
  final q = query.trim().toLowerCase();
  final o = option.toLowerCase();
  if (q.isEmpty) return 1;
  if (o == q) return 4;
  if (o.startsWith(q)) return 3;
  final words = o
      .split(RegExp(r'[^a-z0-9+#.]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  final typed = q.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (typed.isNotEmpty && typed.every((t) => words.any((w) => w.startsWith(t)))) {
    return 2;
  }
  if (o.contains(q)) return 1;
  if (_looseMatch(q, o)) return 1;
  return 0;
}

bool _looseMatch(String q, String o) {
  final letters = q.replaceAll(RegExp(r'\s+'), '');
  if (letters.length < 3 || o.isEmpty || letters[0] != o[0]) return false;
  var at = 0;
  for (final ch in letters.split('')) {
    final i = o.indexOf(ch, at);
    if (i < 0) return false;
    at = i + 1;
  }
  return true;
}

/// Up to [max] [options] that match [query], best first, skipping anything in
/// [exclude] (compared case-insensitively). An empty query returns the first
/// options in list order.
List<String> rankSuggestions(
  String query,
  List<String> options, {
  int max = 10,
  Iterable<String> exclude = const [],
}) {
  final skip = exclude.map((e) => e.toLowerCase()).toSet();
  final scored = <(int, int, String)>[];
  for (var i = 0; i < options.length; i++) {
    final opt = options[i];
    if (skip.contains(opt.toLowerCase())) continue;
    final s = searchScore(query, opt);
    if (s > 0) scored.add((s, i, opt));
  }
  scored.sort(
    (a, b) => b.$1 != a.$1 ? b.$1.compareTo(a.$1) : a.$2.compareTo(b.$2),
  );
  return [for (final e in scored.take(max)) e.$3];
}

/// Location suggestions: up to [maxCities] cities and [maxStates] states.
/// Strict prefix matches win; looser matches are used only when nothing
/// starts with the typed text ("j" -> Jaipur, Jodhpur, ... Jharkhand).
List<String> rankLocations(
  String query,
  List<String> cities,
  List<String> states, {
  int maxCities = 7,
  int maxStates = 3,
  Iterable<String> exclude = const [],
}) {
  final q = query.trim().toLowerCase();
  final skip = exclude.map((e) => e.toLowerCase()).toSet();
  bool keep(String s) => !skip.contains(s.toLowerCase());
  final c = cities.where(keep).toList();
  final s = states.where(keep).toList();
  if (q.isEmpty) return [...c.take(maxCities), ...s.take(maxStates)];

  bool prefix(String v) => v.toLowerCase().startsWith(q);
  final prefixCities = c.where(prefix).toList();
  final prefixStates = s.where(prefix).toList();
  if (prefixCities.isNotEmpty || prefixStates.isNotEmpty) {
    return [...prefixCities.take(maxCities), ...prefixStates.take(maxStates)];
  }
  return [
    ...rankSuggestions(query, c, max: maxCities),
    ...rankSuggestions(query, s, max: maxStates),
  ];
}
