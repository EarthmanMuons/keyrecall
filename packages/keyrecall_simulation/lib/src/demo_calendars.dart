import 'dart:math' as math;

import 'demo_history.dart';

/// Re-datings of one [demoSessions] calendar.
///
/// Every variant keeps the calendar's sessions, their order, and their slots,
/// so two calendars differ in when practice happens and not in how much of it
/// is offered.
enum DemoCalendar {
  /// The calendar as drawn.
  reference,

  /// An added absence of 5 to 10 days after every eighth session.
  interrupted,

  /// An added 21 days away once half the calendar's slots are offered.
  extendedBreak;

  /// [sessions] re-dated by this calendar, with [seed] drawing any absences.
  List<DemoSession> of(List<DemoSession> sessions, {int seed = 0}) {
    final random = math.Random(seed);
    final half = sessions.fold(0, (sum, s) => sum + s.slots) / 2;
    final redated = <DemoSession>[];
    var offered = 0;
    var away = Duration.zero;
    for (final (index, (:start, :slots)) in sessions.indexed) {
      away += switch (this) {
        DemoCalendar.interrupted when index > 0 && index % 8 == 0 => Duration(
          days: 5 + random.nextInt(6),
        ),
        DemoCalendar.extendedBreak
            when index > 0 && offered < half && offered + slots >= half =>
          const Duration(days: 21),
        _ => Duration.zero,
      };
      offered += slots;
      redated.add((start: start.add(away), slots: slots));
    }
    return redated;
  }
}
