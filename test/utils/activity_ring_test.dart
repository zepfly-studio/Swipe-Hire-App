import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/utils/activity_ring.dart';

void main() {
  final now = DateTime(2026, 10, 15, 12);

  test('just confirmed: 15 days left, empty ring', () {
    final r = activityRingFor(now, now: now);
    expect(r.isFull, isFalse);
    expect(r.daysLeft, 15);
    expect(r.progress, 0);
  });

  test('5 days ago: 10 days left', () {
    final r = activityRingFor(now.subtract(const Duration(days: 5)), now: now);
    expect(r.daysLeft, 10);
    expect(r.progress, closeTo(5 / 15, 1e-9));
    expect(r.isFull, isFalse);
  });

  test('part of a day still counts the day as left (min 1)', () {
    final r = activityRingFor(now.subtract(const Duration(days: 14, hours: 23)), now: now);
    expect(r.daysLeft, 1);
    expect(r.isFull, isFalse);
  });

  test('15 days or more: full ring and an active button', () {
    final r = activityRingFor(now.subtract(const Duration(days: 15)), now: now);
    expect(r.isFull, isTrue);
    expect(r.progress, 1);
    expect(activityRingFor(now.subtract(const Duration(days: 40)), now: now).isFull, isTrue);
  });

  test('unknown activeAt behaves like just now; future dates clamp', () {
    expect(activityRingFor(null, now: now).daysLeft, 15);
    expect(activityRingFor(now.add(const Duration(days: 2)), now: now).progress, 0);
  });
}
