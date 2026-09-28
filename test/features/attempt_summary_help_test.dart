import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/attempt_summary_help.dart';

void main() {
  test('explains the attempt dimensions without describing model scores', () {
    final entries = attemptSummaryHelpEntries(includesCoordination: true);

    expect(entries.map((entry) => entry.$1), [
      'Notes',
      'Flow',
      'Pulse',
      'Coordination',
      'Tempo',
    ]);
    expect(attemptSummaryIntroduction, contains('this exercise attempt'));
    expect(attemptSummaryIntroduction, contains('not your overall skill'));
  });

  test('only explains coordination when the attempt measured it', () {
    final entries = attemptSummaryHelpEntries(includesCoordination: false);

    expect(entries.map((entry) => entry.$1), isNot(contains('Coordination')));
  });

  test('names the pulse as played along with the metronome when it was', () {
    final entries = attemptSummaryHelpEntries(
      includesCoordination: false,
      pulseSupplied: true,
    );

    expect(entries.map((entry) => entry.$1), contains('Pulse, with metronome'));
    expect(entries.map((entry) => entry.$1), isNot(contains('Pulse')));
  });
}
