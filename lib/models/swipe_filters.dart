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

/// The filters on the swipe screen: role, city, experience, salary range,
/// work mode, job type, notice period, education and skills. Remembered per user, sent to
/// GET /candidates and stored inside a saved search.
@immutable
class SwipeFilters {
  /// Role / job title; matches a candidate's desired role or current post.
  final String role;
  final String location;
  final double? minExp;
  final double? maxExp;

  /// Salary range in LPA, checked against the candidate's expected salary;
  /// anyone open to negotiate is always included.
  final double? minSalary;
  final double? maxSalary;

  /// Notice-period buckets in days (0, 15, 30, 60, 90), sorted.
  final List<int> notice;
  final List<String> skills;

  /// Work modes (`onsite`, `hybrid`, `remote`) the candidate is open to; a
  /// candidate matches when they accept any of the chosen ones.
  final List<String> workModes;

  /// `full-time`, `part-time`, `internship`, `contract`: any of the chosen ones.
  final List<String> jobTypes;

  /// Education levels (10th ... PhD) and a degree / college text such as
  /// "B.Tech" or "Jaipur University".
  final List<String> qualifications;
  final String education;

  const SwipeFilters({
    this.role = '',
    this.location = '',
    this.minExp,
    this.maxExp,
    this.minSalary,
    this.maxSalary,
    this.notice = const [],
    this.skills = const [],
    this.workModes = const [],
    this.jobTypes = const [],
    this.qualifications = const [],
    this.education = '',
  });

  static const int maxSkills = 10;

  bool get isEmpty =>
      role.trim().isEmpty &&
      location.trim().isEmpty &&
      minExp == null &&
      maxExp == null &&
      minSalary == null &&
      maxSalary == null &&
      notice.isEmpty &&
      skills.isEmpty &&
      workModes.isEmpty &&
      jobTypes.isEmpty &&
      qualifications.isEmpty &&
      education.trim().isEmpty;

  /// Role, city, each experience and salary bound count one each; notice
  /// period, skills and work mode one each.
  int get activeCount =>
      (role.trim().isNotEmpty ? 1 : 0) +
      (location.trim().isNotEmpty ? 1 : 0) +
      (minExp != null ? 1 : 0) +
      (maxExp != null ? 1 : 0) +
      (minSalary != null ? 1 : 0) +
      (maxSalary != null ? 1 : 0) +
      (notice.isNotEmpty ? 1 : 0) +
      (skills.isNotEmpty ? 1 : 0) +
      (workModes.isNotEmpty ? 1 : 0) +
      (jobTypes.isNotEmpty ? 1 : 0) +
      (qualifications.isNotEmpty ? 1 : 0) +
      (education.trim().isNotEmpty ? 1 : 0);

  /// "Web Developer", "Jaipur", "2-5 yrs", "₹3-7 LPA", "Remote", "Notice 15d",
  /// "React, Excel": the active filters as short phrases (empty when none).
  List<String> get summaryParts {
    final exp = minExp != null && maxExp != null
        ? '${_num(minExp!)}-${_num(maxExp!)} yrs'
        : minExp != null
            ? '${_num(minExp!)}+ yrs'
            : maxExp != null
                ? 'up to ${_num(maxExp!)} yrs'
                : '';
    final pay = minSalary != null && maxSalary != null
        ? '₹${_num(minSalary!)}-${_num(maxSalary!)} LPA'
        : minSalary != null
            ? '₹${_num(minSalary!)}+ LPA'
            : maxSalary != null
                ? 'up to ₹${_num(maxSalary!)} LPA'
                : '';
    return [
      if (role.trim().isNotEmpty) role.trim(),
      if (location.trim().isNotEmpty) location.trim(),
      if (exp.isNotEmpty) exp,
      if (pay.isNotEmpty) pay,
      if (workModes.isNotEmpty) workModes.map((m) => kJobWorkModeLabels[m] ?? m).join('/'),
      if (jobTypes.isNotEmpty) jobTypes.map((t) => kJobTypeLabelsMap[t] ?? t).join('/'),
      if (notice.isNotEmpty) 'Notice ${notice.map((d) => d == 0 ? 'immediate' : '${d}d').join('/')}',
      if (qualifications.isNotEmpty) qualifications.join('/'),
      if (education.trim().isNotEmpty) education.trim(),
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
        if (role.trim().isNotEmpty) 'role': role.trim(),
        if (location.trim().isNotEmpty) 'location': location.trim(),
        if (minExp != null) 'expMin': _num(minExp!),
        if (maxExp != null) 'expMax': _num(maxExp!),
        if (minSalary != null) 'minSalary': _num(minSalary!),
        if (maxSalary != null) 'maxSalary': _num(maxSalary!),
        if (notice.isNotEmpty) 'notice': notice.join(','),
        if (skills.isNotEmpty) 'skills': skills.take(maxSkills).join(','),
        if (workModes.isNotEmpty) 'workMode': workModes.join(','),
        if (jobTypes.isNotEmpty) 'jobType': jobTypes.join(','),
        if (qualifications.isNotEmpty) 'qualification': qualifications.join(','),
        if (education.trim().isNotEmpty) 'education': education.trim(),
      };

  /// The `filters` object of a saved search (POST /company/searches) and of
  /// the copy remembered on the device.
  Map<String, dynamic> toJson() => {
        'role': role.trim(),
        'location': location.trim(),
        'minExp': minExp,
        'maxExp': maxExp,
        'minSalary': minSalary,
        'maxSalary': maxSalary,
        'notice': notice,
        'skills': skills.take(maxSkills).toList(),
        'workModes': workModes,
        'jobTypes': jobTypes,
        'qualifications': qualifications,
        'education': education.trim(),
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

  static List<String> _strings(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

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
      role: (raw['role'] ?? '').toString(),
      location: (raw['location'] ?? '').toString(),
      minExp: _double(raw['minExp']),
      maxExp: _double(raw['maxExp']),
      minSalary: _double(raw['minSalary']),
      maxSalary: _double(raw['maxSalary']),
      notice: days.toList()..sort(),
      skills: _strings(raw['skills']),
      workModes: _strings(raw['workModes']),
      jobTypes: _strings(raw['jobTypes']),
      qualifications: _strings(raw['qualifications']),
      education: (raw['education'] ?? '').toString(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SwipeFilters &&
      other.role == role &&
      other.location == location &&
      other.minExp == minExp &&
      other.maxExp == maxExp &&
      other.minSalary == minSalary &&
      other.maxSalary == maxSalary &&
      listEquals(other.notice, notice) &&
      listEquals(other.skills, skills) &&
      listEquals(other.workModes, workModes) &&
      listEquals(other.jobTypes, jobTypes) &&
      listEquals(other.qualifications, qualifications) &&
      other.education == education;

  @override
  int get hashCode => Object.hash(
        role,
        location,
        minExp,
        maxExp,
        minSalary,
        maxSalary,
        Object.hashAll(notice),
        Object.hashAll(skills),
        Object.hashAll(workModes),
        Object.hashAll(jobTypes),
        Object.hashAll(qualifications),
        education,
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
