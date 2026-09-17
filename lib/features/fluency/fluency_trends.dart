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
