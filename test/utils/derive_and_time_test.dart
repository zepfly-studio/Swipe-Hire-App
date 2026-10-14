import 'package:flutter_test/flutter_test.dart';
import 'package:hiring_app/utils/derive.dart';
import 'package:hiring_app/utils/time_format.dart';

void main() {
  group('parseExperienceYears', () {
    test('reads plain and decimal years', () {
      expect(parseExperienceYears('3 years'), 3);
      expect(parseExperienceYears('1.5 yrs'), 1.5);
      expect(parseExperienceYears('7'), 7);
    });

    test('a fresher or empty text is zero', () {
      expect(parseExperienceYears('Fresher'), 0);
      expect(parseExperienceYears(''), 0);
    });

    test('months turn into a fraction of a year', () {
      expect(parseExperienceYears('6 months'), 0.5);
      expect(parseExperienceYears('18 months'), 1.5);
    });
  });

  group('dueLabel', () {
    final now = DateTime(2026, 10, 14, 10);

    test('today, tomorrow and later', () {
      expect(dueLabel(DateTime(2026, 10, 14, 18), now: now), 'Due today');
      expect(dueLabel(DateTime(2026, 10, 15, 9), now: now), 'Due tomorrow');
      expect(dueLabel(DateTime(2026, 10, 19, 9), now: now), 'Due in 5 days');
    });

    test('past dates are overdue', () {
      expect(dueLabel(DateTime(2026, 10, 14, 8), now: now), 'Overdue');
      expect(dueLabel(DateTime(2026, 10, 12, 8), now: now), 'Overdue by 2 days');
      expect(dueLabel(DateTime(2026, 10, 13, 8), now: now), 'Overdue by 1 day');
    });
  });

  group('googleCalendarUri', () {
    test('builds an event link with the start and end in UTC', () {
      final start = DateTime.utc(2026, 10, 20, 9, 30);
      final uri = googleCalendarUri(
        title: 'Interview: Flutter Developer',
        start: start,
        durationMinutes: 45,
        details: 'Bring your laptop',
        location: 'Google Meet',
      );

      expect(uri.host, 'calendar.google.com');
      expect(uri.queryParameters['action'], 'TEMPLATE');
      expect(uri.queryParameters['text'], 'Interview: Flutter Developer');
      expect(uri.queryParameters['dates'], '20261020T093000Z/20261020T101500Z');
      expect(uri.queryParameters['details'], 'Bring your laptop');
      expect(uri.queryParameters['location'], 'Google Meet');
    });

    test('leaves out details and location when empty', () {
      final uri = googleCalendarUri(title: 'Call', start: DateTime.utc(2026, 1, 1));
      expect(uri.queryParameters.containsKey('details'), isFalse);
      expect(uri.queryParameters.containsKey('location'), isFalse);
    });
  });
}
