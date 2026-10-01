import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/fluency/practice_activity.dart';

/// A Thursday.
final _today = CalendarDay(2026, 10, 1);

void main() {
  test('bands split at fixed attempt counts', () {
    expect(
      [
        for (final attempts in [0, 1, 2, 3, 5, 6, 10, 11, 40])
          ActivityBand.of(attempts),
      ],
      [
        ActivityBand.none,
        ActivityBand.upTo2,
        ActivityBand.upTo2,
        ActivityBand.upTo5,
        ActivityBand.upTo5,
        ActivityBand.upTo10,
        ActivityBand.upTo10,
        ActivityBand.moreThan10,
        ActivityBand.moreThan10,
      ],
    );
  });

  group('activity weeks', () {
    test('end with the week today falls in, each from its Monday', () {
      final weeks = activityWeeks(const [], today: _today, count: 26);

      expect(weeks, hasLength(26));
      expect(weeks.last.week, CalendarDay(2026, 9, 28));
      expect(weeks.first.week, CalendarDay(2026, 4, 6));
      expect(weeks.every((week) => week.week.weekStart == week.week), isTrue);
    });

    test('count each day, leave days still to come empty', () {
      final weeks = activityWeeks(
        [_practiced(CalendarDay(2026, 9, 29), 4), _practiced(_today, 12)],
        today: _today,
        count: 2,
      );

      expect(weeks.last.attempts, [0, 4, 0, 12, null, null, null]);
      expect(weeks.last.daysPracticed, 2);
      expect(weeks.last.totalAttempts, 16);
      expect(weeks.first.attempts, everyElement(0));
    });

    test('never change an earlier day as history grows', () {
      final earlier = [_practiced(CalendarDay(2026, 9, 2), 3)];
      final later = [
        ...earlier,
        for (var day = 3; day <= 30; day++)
          _practiced(CalendarDay(2026, 9, day), 30),
      ];

      int attemptsOnSep2(List<FluencyDay> days) =>
          activityWeeks(days, today: _today, count: 26)
              .firstWhere((week) => week.week == CalendarDay(2026, 8, 31))
              .attempts[2]!;

      expect(attemptsOnSep2(earlier), 3);
      expect(attemptsOnSep2(later), 3);
    });
  });

  test('days practiced counts the 30 days ending today', () {
    final days = [
      _practiced(_today.plusDays(-30), 5),
      _practiced(_today.plusDays(-29), 1),
      _practiced(_today.plusDays(-3), 2),
      _practiced(_today, 8),
    ];

    expect(daysPracticed(days, today: _today), 3);
  });

  group('descriptions', () {
    test('a week names its days and attempts', () {
      final weeks = activityWeeks(
        [_practiced(CalendarDay(2026, 9, 21), 1)],
        today: _today,
        count: 2,
      );

      expect(
        activityWeekDescription(weeks.first, today: _today),
        'Week of Sep 21. Practiced 1 day, 1 attempt.',
      );
      expect(
        activityWeekDescription(weeks.last, today: _today),
        'Week of Sep 28. No practice.',
      );
    });

    test('a day names its attempts', () {
      expect(
        activityDayDescription(CalendarDay(2026, 9, 28), 14, today: _today),
        'Sep 28 · 14 attempts',
      );
      expect(
        activityDayDescription(CalendarDay(2025, 12, 30), 0, today: _today),
        'Dec 30, 2025 · No practice',
      );
    });
  });
}

FluencyDay _practiced(CalendarDay day, int attempts) => FluencyDay(
  day: day,
  attempts: attempts,
  demonstrations: const {},
  tempos: const [],
);
