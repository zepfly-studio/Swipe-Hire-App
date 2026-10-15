import 'package:flutter/material.dart';

import '../models/candidate_profile.dart';
import '../theme/app_theme.dart';

/// Where tapping a missing item should take the candidate.
enum StrengthTarget { editProfile, preferences }

class StrengthItem {
  final String key;
  final String label;
  final int points;
  final bool done;
  final StrengthTarget target;
  const StrengthItem({
    required this.key,
    required this.label,
    required this.points,
    required this.done,
    this.target = StrengthTarget.editProfile,
  });
}

class ProfileStrength {
  final int score;
  final List<StrengthItem> items;
  const ProfileStrength({required this.score, required this.items});

  /// All-star >= 90, Strong >= 70, Good start >= 45, otherwise Needs work.
  String get level => strengthLevel(score);

  Color get color => switch (level) {
    'All-star' => AppColors.like,
    'Strong' => AppColors.info,
    'Good start' => AppColors.warning,
    _ => AppColors.reject,
  };

  /// Everything not done yet, most valuable first (ties keep list order).
  List<StrengthItem> get missing {
    final list = [
      for (final i in items)
        if (!i.done) i,
    ];
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort(
      (a, b) => b.$2.points != a.$2.points
          ? b.$2.points.compareTo(a.$2.points)
          : a.$1.compareTo(b.$1),
    );
    return [for (final e in indexed) e.$2];
  }

  /// The few suggestions the home screen shows.
  List<StrengthItem> get topMissing => missing.take(4).toList();
}

String strengthLevel(int score) {
  if (score >= 90) return 'All-star';
  if (score >= 70) return 'Strong';
  if (score >= 45) return 'Good start';
  return 'Needs work';
}

bool _has(String s) => s.trim().isNotEmpty;

/// The website's profile-strength checklist (weights add up to 100).
ProfileStrength computeProfileStrength(CandidateProfile p) {
  final items = <StrengthItem>[
    StrengthItem(
      key: 'video',
      label: 'Intro video',
      points: 20,
      done: _has(p.introVideoUrl),
    ),
    StrengthItem(
      key: 'resume',
      label: 'Resume',
      points: 15,
      done: _has(p.resumeUrl),
    ),
    StrengthItem(
      key: 'skills',
      label: 'At least 5 skills',
      points: 15,
      done: p.skills.length >= 5,
    ),
    StrengthItem(
      key: 'about',
      label: 'A few lines about you',
      points: 10,
      done: p.about.trim().length >= 30,
    ),
    StrengthItem(
      key: 'company',
      label: 'Current or last company & role',
      points: 10,
      done:
          p.experienceYears == 0 ||
          (_has(p.currentCompany) && _has(p.currentPost)),
    ),
    StrengthItem(
      key: 'role',
      label: 'Job title you want',
      points: 5,
      done: _has(p.desiredRole),
    ),
    StrengthItem(
      key: 'college',
      label: 'College & passing year',
      points: 5,
      done: _has(p.college) && p.graduationYear > 0,
    ),
    StrengthItem(
      key: 'notice',
      label: 'Notice period',
      points: 5,
      done: _has(p.noticePeriod),
    ),
    StrengthItem(
      key: 'salary',
      label: 'Expected salary',
      points: 5,
      done: p.expectedSalaryLpa > 0,
    ),
    StrengthItem(
      key: 'prefs',
      label: 'Work mode & job type',
      points: 5,
      done: p.workModes.isNotEmpty && p.jobTypes.isNotEmpty,
      target: StrengthTarget.preferences,
    ),
    StrengthItem(
      key: 'cities',
      label: 'Cities you would work in',
      points: 5,
      done: p.preferredLocations.isNotEmpty,
      target: StrengthTarget.preferences,
    ),
  ];
  final score = items
      .where((i) => i.done)
      .fold<int>(0, (sum, i) => sum + i.points);
  return ProfileStrength(score: score, items: items);
}
