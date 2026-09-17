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

  group('recall milestones', () {
    const cued = DemonstrationLevel.cued;
    const previewed = DemonstrationLevel.notesPreviewed;
    const memory = DemonstrationLevel.fromMemory;

    test('count each material once, at its best by the end of each week', () {
      final weeks = recallMilestones(
        [
          _day(-30, {'C_MAJOR': cued}),
          _day(-6, {'C_MAJOR': memory, 'G_MAJOR': cued}),
          _day(1, {'C_MAJOR': cued, 'G_MAJOR': previewed}),
          _day(3, {'F_MAJOR': cued, 'ARPEGGIO': memory}),
        ],
        materialIds: {'C_MAJOR', 'G_MAJOR', 'F_MAJOR'},
        today: CalendarDay(2026, 9, 17),
        count: 3,
      );

      expect(
        [for (final week in weeks) week.week],
        [_monday.plusDays(-14), _monday.plusDays(-7), _monday],
      );
      expect(weeks[0].counts, {cued: 1});
      expect(weeks[1].counts, {memory: 1, cued: 1});
      expect(weeks[2].counts, {memory: 1, previewed: 1, cued: 1});
      expect(weeks[2].total, 3);
    });

    test('never fall at or above any level from week to week', () {
      final weeks = recallMilestones(
        [
          _day(-40, {'A': memory, 'B': cued}),
          _day(-20, {'A': cued, 'B': previewed, 'C': cued}),
          _day(-10, {'B': cued, 'C': memory}),
          _day(0, {'A': cued, 'D': previewed}),
        ],
        materialIds: {'A', 'B', 'C', 'D'},
        today: _monday,
      );

      for (final (index, week) in weeks.indexed.skip(1)) {
        for (final level in DemonstrationLevel.values) {
          int atOrAbove(WeeklyMilestones of) => [
            for (final above in DemonstrationLevel.values)
              if (above.index >= level.index) of.countAt(above),
          ].fold(0, (sum, count) => sum + count);
          expect(
            atOrAbove(week),
            greaterThanOrEqualTo(atOrAbove(weeks[index - 1])),
          );
        }
      }
    });
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

FluencyDay _day(int days, Map<String, DemonstrationLevel> levels) => FluencyDay(
  day: _monday.plusDays(days),
  attempts: levels.length,
  demonstrations: {
    for (final MapEntry(key: id, value: level) in levels.entries)
      id: Demonstration(
        materialId: id,
        level: level,
        lastAt: DateTime.utc(2026, 9, 1),
      ),
  },
  tempos: const [],
);

WeeklyTempo _week(int days, {double? tempo, int attempts = 3, int rung = 2}) =>
    WeeklyTempo(
      week: _monday.plusDays(days),
      guidanceIndependence: tempo == null ? null : rung,
      medianTempoBpm: tempo,
      observations: tempo == null ? 0 : attempts,
    );
