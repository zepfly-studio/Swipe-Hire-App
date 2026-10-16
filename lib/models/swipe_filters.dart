import 'package:flutter/foundation.dart';

import 'job_choices.dart';

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

  /// Work modes (`onsite`, `hybrid`, `remote`) and job types (`full-time`,
  /// `part-time`, `internship`, `contract`) the candidate is open to; a
  /// candidate matches when they accept any of the chosen ones.
  final List<String> workModes;
  final List<String> jobTypes;

  const SwipeFilters({
    this.location = '',
    this.minExp,
    this.maxExp,
    this.maxSalary,
    this.notice = const [],
    this.skills = const [],
    this.workModes = const [],
    this.jobTypes = const [],
  });

  static const int maxSkills = 10;

  bool get isEmpty =>
      location.trim().isEmpty &&
      minExp == null &&
      maxExp == null &&
      maxSalary == null &&
      notice.isEmpty &&
      skills.isEmpty &&
      workModes.isEmpty &&
      jobTypes.isEmpty;

  /// City, min experience, max experience and budget count one each; notice
  /// period and skills one each (spec C15).
  int get activeCount =>
      (location.trim().isNotEmpty ? 1 : 0) +
      (minExp != null ? 1 : 0) +
      (maxExp != null ? 1 : 0) +
      (maxSalary != null ? 1 : 0) +
      (notice.isNotEmpty ? 1 : 0) +
      (skills.isNotEmpty ? 1 : 0) +
      (workModes.isNotEmpty ? 1 : 0) +
      (jobTypes.isNotEmpty ? 1 : 0);

  /// "Jaipur", "2-5 yrs", "Budget ₹8 LPA", "Notice 15d/30d", "React, Excel":
  /// the active filters as short phrases (empty when no filter is set).
  List<String> get summaryParts {
    final exp = minExp != null && maxExp != null
        ? '${_num(minExp!)}-${_num(maxExp!)} yrs'
        : minExp != null
            ? '${_num(minExp!)}+ yrs'
            : maxExp != null
                ? 'up to ${_num(maxExp!)} yrs'
                : '';
    return [
      if (location.trim().isNotEmpty) location.trim(),
      if (exp.isNotEmpty) exp,
      if (maxSalary != null) 'Budget ₹${_num(maxSalary!)} LPA',
      if (notice.isNotEmpty) 'Notice ${notice.map((d) => d == 0 ? 'immediate' : '${d}d').join('/')}',
      if (workModes.isNotEmpty) workModes.map((m) => kJobWorkModeLabels[m] ?? m).join('/'),
      if (jobTypes.isNotEmpty) jobTypes.map((t) => kJobTypeLabelsMap[t] ?? t).join('/'),
      if (skills.isNotEmpty) skills.take(4).join(', ') + (skills.length > 4 ? '…' : ''),
    ];
  }

  /// A name for a saved filter (the backend allows 60 characters).
  String get label {
    final text = summaryParts.join(' · ');
    return text.length <= 60 ? text : '${text.substring(0, 59)}…';
  }

  static String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toString();

  /// Query parameters for GET /candidates.
  Map<String, String> toQuery() => {
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (minExp != null) 'expMin': _num(minExp!),
        if (maxExp != null) 'expMax': _num(maxExp!),
        if (maxSalary != null) 'maxSalary': _num(maxSalary!),
        if (notice.isNotEmpty) 'notice': notice.join(','),
        if (skills.isNotEmpty) 'skills': skills.take(maxSkills).join(','),
        if (workModes.isNotEmpty) 'workMode': workModes.join(','),
        if (jobTypes.isNotEmpty) 'jobType': jobTypes.join(','),
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
        'workModes': workModes,
        'jobTypes': jobTypes,
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
      workModes: raw['workModes'] is List ? (raw['workModes'] as List).map((e) => e.toString()).toList() : const [],
      jobTypes: raw['jobTypes'] is List ? (raw['jobTypes'] as List).map((e) => e.toString()).toList() : const [],
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
      listEquals(other.skills, skills) &&
      listEquals(other.workModes, workModes) &&
      listEquals(other.jobTypes, jobTypes);

  @override
  int get hashCode => Object.hash(
        location,
        minExp,
        maxExp,
        maxSalary,
        Object.hashAll(notice),
        Object.hashAll(skills),
        Object.hashAll(workModes),
        Object.hashAll(jobTypes),
      );
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
