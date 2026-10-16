import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/models/swipe_filters.dart';
import 'package:hiring_app/screens/recruiter/swipe/swipe_decision.dart';
import 'package:hiring_app/widgets/candidate_details.dart';

void main() {
  group('swipe decision thresholds', () {
    test('commits past 100px in either direction', () {
      expect(swipeDecision(dx: 101, velocityX: 0), SwipeDir.right);
      expect(swipeDecision(dx: -101, velocityX: 0), SwipeDir.left);
    });

    test('exactly 100px with no speed springs back', () {
      expect(swipeDecision(dx: 100, velocityX: 0), isNull);
      expect(swipeDecision(dx: -100, velocityX: 0), isNull);
    });

    test('a fast fling commits from 40px', () {
      expect(swipeDecision(dx: 41, velocityX: 600), SwipeDir.right);
      expect(swipeDecision(dx: -60, velocityX: -900), SwipeDir.left);
    });

    test('a fast fling under 40px or a slow drag under 100px springs back', () {
      expect(swipeDecision(dx: 39, velocityX: 2000), isNull);
      expect(swipeDecision(dx: 80, velocityX: 400), isNull);
      expect(swipeDecision(dx: 80, velocityX: 500), isNull);
    });

    test('rotation is capped at 9 degrees', () {
      expect(swipeRotation(320), closeTo(9 * math.pi / 180, 1e-9));
      expect(swipeRotation(-640), closeTo(-9 * math.pi / 180, 1e-9));
      expect(swipeRotation(0), 0);
    });

    test('stamp and tint opacity follow the drag', () {
      expect(swipeStampOpacity(50), closeTo(0.5, 1e-9));
      expect(swipeStampOpacity(-400), 1);
      expect(swipeTintOpacity(320), closeTo(0.22, 1e-9));
      expect(swipeTintOpacity(1000), closeTo(0.22, 1e-9));
    });
  });

  group('match badge colours', () {
    test('75+ green, 45+ amber, otherwise grey', () {
      expect(matchBadgeColors(75).fg, matchBadgeColors(100).fg);
      expect(matchBadgeColors(74).fg, matchBadgeColors(45).fg);
      expect(matchBadgeColors(44).fg, matchBadgeColors(0).fg);
      expect(matchBadgeColors(75).fg, isNot(matchBadgeColors(74).fg));
      expect(matchBadgeColors(45).fg, isNot(matchBadgeColors(44).fg));
    });
  });

  group('filters serialization', () {
    test('query uses the backend parameter names', () {
      const f = SwipeFilters(
        location: ' Jaipur ',
        minExp: 2,
        maxExp: 5.5,
        maxSalary: 8,
        notice: [0, 30],
        skills: ['React', 'Excel'],
      );
      expect(f.toQuery(), {
        'location': 'Jaipur',
        'expMin': '2',
        'expMax': '5.5',
        'maxSalary': '8',
        'notice': '0,30',
        'skills': 'React,Excel',
      });
    });

    test('work mode and job type are sent, counted, saved and labelled', () {
      const f = SwipeFilters(workModes: ['remote', 'hybrid'], jobTypes: ['contract']);
      expect(f.isEmpty, isFalse);
      expect(f.toQuery(), {'workMode': 'remote,hybrid', 'jobType': 'contract'});
      expect(f.activeCount, 2);
      expect(SwipeFilters.fromJson(f.toJson()), f);
      expect(f.summaryParts, ['Remote/Hybrid', 'Contract']);
      expect(f.label, 'Remote/Hybrid · Contract');
      expect(f, isNot(const SwipeFilters(workModes: ['remote'], jobTypes: ['contract'])));
    });

    test('empty filters send nothing', () {
      expect(const SwipeFilters().toQuery(), isEmpty);
      expect(const SwipeFilters().isEmpty, isTrue);
      expect(const SwipeFilters().activeCount, 0);
    });

    test('skills are capped at 10', () {
      final f = SwipeFilters(skills: [for (var i = 0; i < 14; i++) 's$i']);
      expect(f.toQuery()['skills']!.split(',').length, 10);
      expect((f.toJson()['skills'] as List).length, 10);
    });

    test('active count: city, min, max, budget one each; notice and skills one each', () {
      expect(const SwipeFilters(location: 'x', minExp: 1, maxExp: 4, maxSalary: 9).activeCount, 4);
      expect(const SwipeFilters(notice: [0, 15, 30], skills: ['a', 'b']).activeCount, 2);
      expect(const SwipeFilters(minExp: 1, notice: [15], skills: ['a']).activeCount, 3);
    });

    test('json round trip, tolerant of strings and notice labels', () {
      const f = SwipeFilters(location: 'Pune', minExp: 1, maxSalary: 6.5, notice: [15, 60], skills: ['Go']);
      expect(SwipeFilters.fromJson(f.toJson()), f);

      final loose = SwipeFilters.fromJson({
        'location': 'Delhi',
        'minExp': '3',
        'maxSalary': '10.5',
        'notice': ['Immediate', '30 days', 60],
        'skills': ['SQL'],
      });
      expect(loose.minExp, 3);
      expect(loose.maxSalary, 10.5);
      expect(loose.notice, [0, 30, 60]);
      expect(SwipeFilters.fromJson(null).isEmpty, isTrue);
    });
  });
}
