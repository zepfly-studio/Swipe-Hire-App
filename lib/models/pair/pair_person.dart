/// Small tolerant JSON readers shared by the pair models (the contract says
/// to tolerate missing fields).
String pairStr(Object? v, [String fallback = '']) {
  if (v == null) return fallback;
  final s = v.toString();
  return s.isEmpty ? fallback : s;
}

int pairInt(Object? v, [int fallback = 0]) {
  if (v is num) return v.toInt();
  return int.tryParse(pairStr(v)) ?? fallback;
}

DateTime? pairDate(Object? v) {
  final s = pairStr(v);
  if (s.isEmpty) return null;
  return DateTime.tryParse(s)?.toLocal();
}

Map<String, dynamic> pairMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// The other side of a pair: a candidate (for a company) or a company (for a
/// candidate). `{ id, name, subtitle, verified?, avatarUrl }`.
class PairPerson {
  final String id;
  final String name;
  final String subtitle;
  final bool verified;
  final String avatarUrl;

  const PairPerson({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.verified = false,
    this.avatarUrl = '',
  });

  factory PairPerson.fromMap(Object? raw) {
    final m = pairMap(raw);
    return PairPerson(
      id: pairStr(m['id']),
      name: pairStr(m['name'], 'Unknown'),
      subtitle: pairStr(m['subtitle']),
      verified: m['verified'] == true,
      avatarUrl: pairStr(m['avatarUrl']),
    );
  }

  String get firstName {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }
}
