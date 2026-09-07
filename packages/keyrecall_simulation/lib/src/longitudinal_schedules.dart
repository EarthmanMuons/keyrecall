import 'trajectory.dart';

/// Named schedules to characterize a run against.
///
/// A handful of shapes rather than a sweep over gap lengths. What a run across
/// months is asked to answer is whether practice and forgetting interact
/// sensibly, and the answer differs by the pattern of the calendar rather than
/// by any one interval: the same twelve sittings dense, spread, interrupted or
/// sporadic are four different questions.
///
/// The days are attendance, not policy. Nothing in the app schedules a
/// sitting, so these describe learners who show up in recognisable ways.
class LongitudinalSchedules {
  /// A week of near-daily practice, where almost nothing decays.
  static const List<int> denseWeek = [0, 1, 2, 4, 6];

  /// A month of ordinary practice, thinning as it goes.
  static const List<int> normalMonth = [0, 2, 5, 9, 14, 21, 30];

  /// A good start, a month away, and a good restart.
  static const List<int> interrupted = [0, 1, 3, 30, 31, 38, 60];

  /// Somebody who practises when they remember to.
  static const List<int> sporadic = [0, 7, 21, 45, 90];

  /// Enough practice to build something, then a season away from it.
  static const List<int> returnAfterLongBreak = [0, 1, 2, 3, 4, 94, 95, 96];

  static const Map<String, List<int>> all = {
    'dense_week': denseWeek,
    'normal_month': normalMonth,
    'interrupted': interrupted,
    'sporadic': sporadic,
    'return_after_long_break': returnAfterLongBreak,
  };

  /// The schedule [name] describes, at [slots] attempts a sitting.
  ///
  /// Throws [ArgumentError] when no schedule matches.
  static List<Sitting> named(String name, {required int slots}) {
    final days = all[name];
    if (days == null) {
      throw ArgumentError.value(name, 'name', 'unknown schedule');
    }
    return sittingsOnDays(days, slots: slots);
  }
}
