import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/fluency/fluency_trends.dart';

/// 2026-09-14 is a Monday.
final _monday = CalendarDay(2026, 9, 14);

void main() {
  group('recent weeks', () {
    test('end with the week today falls in and fill gaps', () {
      final weeks = recentWeeks(
        [_week(-14, tempo: 60), _week(0, tempo: 72)],
        today: CalendarDay(2026, 9, 17),
        count: 4,
      );

      expect(
        [for (final week in weeks) week.week],
        [
          _monday.plusDays(-21),
          _monday.plusDays(-14),
          _monday.plusDays(-7),
          _monday,
        ],
      );
      expect(
        [for (final week in weeks) week.medianTempoBpm],
        [null, 60, null, 72],
      );
      expect(weeks[2].observations, 0);
    });

    test('leave out weeks older than the window', () {
      final weeks = recentWeeks(
        [_week(-70, tempo: 50)],
        today: _monday,
        count: 8,
      );

      expect(weeks, hasLength(8));
      expect(weeks.every((week) => week.medianTempoBpm == null), isTrue);
    });
  });

  test('a line is never drawn across a week without a value', () {
    final weeks = [
      _week(0, tempo: 60),
      _week(7, tempo: 62),
      _week(14),
      _week(21, tempo: 64),
      _week(28),
      _week(35),
      _week(42, tempo: 70),
      _week(49, tempo: 72),
    ];

    expect(contiguousRuns(weeks), [
      [0, 1],
      [3],
      [6, 7],
    ]);
  });

  test('a week of one or two attempts is sparse, and an empty one is not', () {
    expect(isSparse(_week(0, tempo: 60, attempts: 1)), isTrue);
    expect(isSparse(_week(0, tempo: 60, attempts: 2)), isTrue);
    expect(isSparse(_week(0, tempo: 60, attempts: 3)), isFalse);
    expect(isSparse(_week(0)), isFalse);
  });

  test('a point names its pace, its attempts, and its support', () {
    expect(playingPaceDetail(_week(0, tempo: 71.6, attempts: 1, rung: 1)), [
      '72 BPM',
      '1 attempt',
      'Notes previewed',
    ]);
    expect(playingPaceDetail(_week(0, tempo: 90, attempts: 4)), [
      '90 BPM',
      '4 attempts',
      'From memory',
    ]);
    expect(playingPaceDetail(_week(0)), isNull);
  });
}

WeeklyTempo _week(int days, {double? tempo, int attempts = 3, int rung = 2}) =>
    WeeklyTempo(
      week: _monday.plusDays(days),
      guidanceIndependence: tempo == null ? null : rung,
      medianTempoBpm: tempo,
      observations: tempo == null ? 0 : attempts,
    );
