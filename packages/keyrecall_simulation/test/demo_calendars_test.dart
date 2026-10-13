import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final reference = demoSessions(from: demoHistoryStart, until: demoHistoryEnd);

  int daysBetween(DemoSession a, DemoSession b) =>
      b.start.difference(a.start).inDays;

  test('every calendar offers the same sessions in the same order', () {
    for (final calendar in DemoCalendar.values) {
      final sessions = calendar.of(reference, seed: 3);
      expect(
        [for (final s in sessions) s.slots],
        [for (final s in reference) s.slots],
      );
      for (var i = 1; i < sessions.length; i++) {
        expect(sessions[i].start.isAfter(sessions[i - 1].start), isTrue);
      }
    }
  });

  test('the reference calendar is the one drawn', () {
    expect(DemoCalendar.reference.of(reference), reference);
  });

  test('interruptions add an absence after every eighth session', () {
    final sessions = DemoCalendar.interrupted.of(reference);
    for (var i = 1; i < sessions.length; i++) {
      final added =
          daysBetween(sessions[i - 1], sessions[i]) -
          daysBetween(reference[i - 1], reference[i]);
      expect(added, i % 8 == 0 ? inInclusiveRange(5, 10) : 0);
    }
  });

  test('one 21-day break falls at the middle of the offered slots', () {
    final sessions = DemoCalendar.extendedBreak.of(reference);
    final total = reference.fold(0, (sum, s) => sum + s.slots);
    final added = [
      for (var i = 1; i < sessions.length; i++)
        daysBetween(sessions[i - 1], sessions[i]) -
            daysBetween(reference[i - 1], reference[i]),
    ];
    expect(added.where((d) => d != 0), [21]);
    final at = added.indexOf(21) + 1;
    final before = reference.take(at).fold(0, (sum, s) => sum + s.slots);
    expect(before, lessThan(total / 2));
    expect(before + reference[at].slots, greaterThanOrEqualTo(total / 2));
  });
}
