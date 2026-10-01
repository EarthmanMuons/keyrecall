import 'package:flutter/foundation.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'fluency_summary.dart';

/// How a calendar day is shaded by the attempts committed on it.
///
/// Fixed bands rather than ones relative to the learner's own range, so a
/// day's shade never changes as later history accumulates.
enum ActivityBand {
  none,
  upTo2,
  upTo5,
  upTo10,
  moreThan10;

  static ActivityBand of(int attempts) => switch (attempts) {
    <= 0 => none,
    <= 2 => upTo2,
    <= 5 => upTo5,
    <= 10 => upTo10,
    _ => moreThan10,
  };
}

/// One week of the activity calendar.
@immutable
class ActivityWeek {
  /// The Monday the week starts on.
  final CalendarDay week;

  /// Committed attempts on each day from Monday, or null for a day still to
  /// come.
  final List<int?> attempts;

  ActivityWeek({required this.week, required Iterable<int?> attempts})
    : attempts = List.unmodifiable(attempts);

  CalendarDay dayAt(int weekday) => week.plusDays(weekday);

  int get daysPracticed =>
      attempts.where((count) => count != null && count > 0).length;

  int get totalAttempts =>
      attempts.fold(0, (total, count) => total + (count ?? 0));
}

/// The [count] weeks ending with the week [today] falls in.
List<ActivityWeek> activityWeeks(
  List<FluencyDay> days, {
  required CalendarDay today,
  required int count,
}) {
  final attemptsOn = {for (final day in days) day.day: day.attempts};
  final first = today.weekStart.plusDays(-7 * (count - 1));
  return [
    for (var index = 0; index < count; index++)
      ActivityWeek(
        week: first.plusDays(7 * index),
        attempts: [
          for (var weekday = 0; weekday < 7; weekday++)
            switch (first.plusDays(7 * index + weekday)) {
              final day when day.compareTo(today) > 0 => null,
              final day => attemptsOn[day] ?? 0,
            },
        ],
      ),
  ];
}

/// How many of the [window] days ending with [today] had any practice.
int daysPracticed(
  List<FluencyDay> days, {
  required CalendarDay today,
  int window = 30,
}) {
  final first = today.plusDays(1 - window);
  return days
      .where(
        (day) => day.day.compareTo(first) >= 0 && day.day.compareTo(today) <= 0,
      )
      .length;
}

/// What a week of the calendar reads as to assistive technology.
String activityWeekDescription(
  ActivityWeek week, {
  required CalendarDay today,
}) {
  final start = 'Week of ${dayName(week.week, today: today)}.';
  if (week.daysPracticed == 0) return '$start No practice.';
  return '$start Practiced ${_count(week.daysPracticed, 'day')}, '
      '${_count(week.totalAttempts, 'attempt')}.';
}

/// What one inspected day of the calendar says.
String activityDayDescription(
  CalendarDay day,
  int attempts, {
  required CalendarDay today,
}) =>
    '${dayName(day, today: today)} · '
    '${attempts == 0 ? 'No practice' : _count(attempts, 'attempt')}';

String _count(int count, String noun) =>
    count == 1 ? '1 $noun' : '$count ${noun}s';
