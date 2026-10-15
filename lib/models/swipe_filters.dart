import 'package:flutter/foundation.dart';

/// Notice-period chips and the exact day buckets the backend filters on.
const Map<String, int> kNoticeBuckets = {
  'Immediate': 0,
  '15 days': 15,
  '30 days': 30,
  '60 days': 60,
  '90 days': 90,
};

/// The filters on the swipe screen (spec C2 "FeedFilters"). Remembered per
/// user, sent to GET /candidates and stored inside a saved search.
@immutable
class SwipeFilters {
  final String location;
  final double? minExp;
  final double? maxExp;

  /// The company's budget (max LPA): shows candidates whose expected salary
  /// is at or below it, plus anyone open to negotiate.
  final double? maxSalary;

  /// Notice-period buckets in days (0, 15, 30, 60, 90), sorted.
  final List<int> notice;
  final List<String> skills;

  const SwipeFilters({
    this.location = '',
    this.minExp,
    this.maxExp,
    this.maxSalary,
    this.notice = const [],
    this.skills = const [],
  });

  static const int maxSkills = 10;

  bool get isEmpty =>
      location.trim().isEmpty && minExp == null && maxExp == null && maxSalary == null && notice.isEmpty && skills.isEmpty;

  /// City, min experience, max experience and budget count one each; notice
  /// period and skills one each (spec C15).
  int get activeCount =>
      (location.trim().isNotEmpty ? 1 : 0) +
      (minExp != null ? 1 : 0) +
      (maxExp != null ? 1 : 0) +
      (maxSalary != null ? 1 : 0) +
      (notice.isNotEmpty ? 1 : 0) +
      (skills.isNotEmpty ? 1 : 0);

  static String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Query parameters for GET /candidates.
  Map<String, String> toQuery() => {
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (minExp != null) 'expMin': _num(minExp!),
        if (maxExp != null) 'expMax': _num(maxExp!),
        if (maxSalary != null) 'maxSalary': _num(maxSalary!),
        if (notice.isNotEmpty) 'notice': notice.join(','),
        if (skills.isNotEmpty) 'skills': skills.take(maxSkills).join(','),
      };

  /// The `filters` object of a saved search (POST /company/searches) and of
  /// the copy remembered on the device.
  Map<String, dynamic> toJson() => {
        'location': location.trim(),
        'minExp': minExp,
        'maxExp': maxExp,
        'maxSalary': maxSalary,
        'notice': notice,
        'skills': skills.take(maxSkills).toList(),
      };

  static double? _double(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static int? _noticeDays(Object? v) {
    if (v is num) return v.toInt();
    final s = v.toString().trim().toLowerCase();
    if (s.isEmpty) return null;
    if (s == 'immediate' || s == 'immediately') return 0;
    return int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');
  }

  /// Tolerant: missing fields, strings for numbers, `notice` as ints or
  /// labels ("15 days").
  factory SwipeFilters.fromJson(Object? raw) {
    if (raw is! Map) return const SwipeFilters();
    final days = <int>{};
    if (raw['notice'] is List) {
      for (final e in raw['notice'] as List) {
        final d = _noticeDays(e);
        if (d != null) days.add(d);
      }
    }
    return SwipeFilters(
      location: (raw['location'] ?? '').toString(),
      minExp: _double(raw['minExp']),
      maxExp: _double(raw['maxExp']),
      maxSalary: _double(raw['maxSalary']),
      notice: days.toList()..sort(),
      skills: raw['skills'] is List ? (raw['skills'] as List).map((e) => e.toString()).toList() : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwipeFilters &&
      other.location == location &&
      other.minExp == minExp &&
      other.maxExp == maxExp &&
      other.maxSalary == maxSalary &&
      listEquals(other.notice, notice) &&
      listEquals(other.skills, skills);

  @override
  int get hashCode => Object.hash(location, minExp, maxExp, maxSalary, Object.hashAll(notice), Object.hashAll(skills));
}

/// A saved search with alerts (GET /company/searches).
@immutable
class SavedSearch {
  final String id;
  final String name;
  final SwipeFilters filters;
  final bool alerts;

  const SavedSearch({required this.id, required this.name, required this.filters, this.alerts = true});

  SavedSearch copyWith({bool? alerts, String? name}) =>
      SavedSearch(id: id, name: name ?? this.name, filters: filters, alerts: alerts ?? this.alerts);

  factory SavedSearch.fromMap(Map<String, dynamic> m) => SavedSearch(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        filters: SwipeFilters.fromJson(m['filters']),
        alerts: m['alerts'] != false,
      );
}
