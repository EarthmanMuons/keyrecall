import 'package:flutter/foundation.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

/// How many attempts a week needs before its value is drawn at full weight.
const int fullWeightAttempts = 3;

/// The [count] weeks ending with the week [today] falls in, each holding its
/// entry from [series] or an empty week where there is none.
List<WeeklyTempo> recentWeeks(
  List<WeeklyTempo> series, {
  required CalendarDay today,
  int count = 8,
}) {
  final byWeek = {for (final week in series) week.week: week};
  final first = today.weekStart.plusDays(-7 * (count - 1));
  return [
    for (var index = 0; index < count; index++)
      byWeek[first.plusDays(7 * index)] ?? _empty(first.plusDays(7 * index)),
  ];
}

WeeklyTempo _empty(CalendarDay week) => WeeklyTempo(
  week: week,
  guidanceIndependence: null,
  medianTempoBpm: null,
  observations: 0,
);

/// The runs of consecutive weeks with a value, as their positions in [weeks].
///
/// A chart draws each run as its own line, so nothing is drawn across a week
/// nobody played.
List<List<int>> contiguousRuns(List<WeeklyTempo> weeks) {
  final runs = <List<int>>[];
  List<int>? current;
  for (final (index, week) in weeks.indexed) {
    if (week.medianTempoBpm == null) {
      current = null;
      continue;
    }
    if (current == null) runs.add(current = []);
    current.add(index);
  }
  return runs;
}

/// Whether [week] rests on too few attempts to draw at full weight.
bool isSparse(WeeklyTempo week) =>
    week.observations > 0 && week.observations < fullWeightAttempts;

/// What a point on the playing pace chart says when it is tapped, one line at
/// a time, or null for a week with no value.
List<String>? playingPaceDetail(WeeklyTempo week) {
  final tempo = week.medianTempoBpm;
  if (tempo == null) return null;
  return [
    '${tempo.round()} BPM',
    week.observations == 1 ? '1 attempt' : '${week.observations} attempts',
    switch (week.guidanceIndependence) {
      2 => 'From memory',
      1 => 'Notes previewed',
      _ => 'With cues',
    },
  ];
}

/// How many materials stood at each demonstration level by the end of a week.
@immutable
class WeeklyMilestones {
  /// The Monday the week starts on.
  final CalendarDay week;

  /// Materials whose strongest demonstration by the end of [week] is each
  /// level. A level nobody has reached is absent.
  final Map<DemonstrationLevel, int> counts;

  WeeklyMilestones({
    required this.week,
    required Map<DemonstrationLevel, int> counts,
  }) : counts = Map.unmodifiable(counts);

  int countAt(DemonstrationLevel level) => counts[level] ?? 0;

  int get total => counts.values.fold(0, (sum, count) => sum + count);
}

/// The strongest demonstration of each material in [materialIds], week by week
/// for the [count] weeks ending with the week [today] falls in.
///
/// Cumulative over the whole history rather than the window, and best-ever, so
/// the counts at or above any level never fall from one week to the next.
List<WeeklyMilestones> recallMilestones(
  List<FluencyDay> days, {
  required Set<String> materialIds,
  required CalendarDay today,
  int count = 8,
}) {
  final first = today.weekStart.plusDays(-7 * (count - 1));
  final best = <String, DemonstrationLevel>{};
  final weeks = <WeeklyMilestones>[];
  var next = 0;
  for (var index = 0; index < count; index++) {
    final week = first.plusDays(7 * index);
    final end = week.plusDays(7);
    for (; next < days.length && days[next].day.compareTo(end) < 0; next++) {
      for (final demonstration in days[next].demonstrations.values) {
        if (!materialIds.contains(demonstration.materialId)) continue;
        final held = best[demonstration.materialId];
        if (held == null || demonstration.level.index > held.index) {
          best[demonstration.materialId] = demonstration.level;
        }
      }
    }
    final counts = <DemonstrationLevel, int>{};
    for (final level in best.values) {
      counts.update(level, (count) => count + 1, ifAbsent: () => 1);
    }
    weeks.add(WeeklyMilestones(week: week, counts: counts));
  }
  return weeks;
}
