/// Adds [raw] to [tags] the way the website's TagInput does:
/// trimmed, at most [maxLen] characters, de-duplicated case-insensitively,
/// and spelled like the matching entry of [options] when there is one
/// ("react" becomes "React"). Returns [tags] itself (same instance) when
/// nothing was added, otherwise a new list; stops at [max] tags.
List<String> addTag(
  List<String> tags,
  String raw, {
  List<String> options = const [],
  int max = 30,
  int maxLen = 40,
}) {
  var text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty || tags.length >= max) return tags;
  if (text.length > maxLen) text = text.substring(0, maxLen).trim();
  final lower = text.toLowerCase();
  final canonical = options.firstWhere(
    (o) => o.toLowerCase() == lower,
    orElse: () => text,
  );
  final canonicalLower = canonical.toLowerCase();
  if (tags.any((t) => t.toLowerCase() == canonicalLower)) return tags;
  return [...tags, canonical];
}

/// Splits pasted/typed text on commas and adds every piece with [addTag].
List<String> addTags(
  List<String> tags,
  String raw, {
  List<String> options = const [],
  int max = 30,
  int maxLen = 40,
}) {
  var out = tags;
  for (final piece in raw.split(',')) {
    out = addTag(out, piece, options: options, max: max, maxLen: maxLen);
  }
  return out;
}
