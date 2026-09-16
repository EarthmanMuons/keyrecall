import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/timing_shortfall.dart';

void main() {
  test('an attempt whose notes were all timed was too short', () {
    expect(
      timingShortfallFor(null, source: InputSourceKind.midi),
      TimingShortfall.insufficientObservations,
    );
  });

  test('a lost timeline is told apart from a clock still being named', () {
    expect(
      timingShortfallFor(
        TimingUnavailableReason.continuityLost,
        source: InputSourceKind.midi,
      ),
      TimingShortfall.timelineFailed,
    );
    expect(
      timingShortfallFor(
        TimingUnavailableReason.detecting,
        source: InputSourceKind.midi,
      ),
      TimingShortfall.identifyingClock,
    );
    expect(
      timingShortfallFor(
        TimingUnavailableReason.nonPerformanceDomain,
        source: InputSourceKind.midi,
      ),
      TimingShortfall.unsupportedClock,
    );
  });

  test('a source that stamps nothing is not a clock being identified', () {
    expect(
      timingShortfallFor(
        TimingUnavailableReason.detecting,
        source: InputSourceKind.demo,
      ),
      TimingShortfall.unsupportedSource,
    );
  });

  test('only a connection fault sends the learner to the connection', () {
    expect(
      timingShortfallSentence(TimingShortfall.insufficientObservations),
      isNot(contains('connection')),
    );
    expect(
      timingShortfallSentence(TimingShortfall.unsupportedClock),
      contains('connection'),
    );
  });

  test('a replaced clock is said as that, not as a short attempt', () {
    expect(
      timingShortfallFor(
        null,
        source: InputSourceKind.midi,
        clockReplaced: true,
      ),
      TimingShortfall.clockReplaced,
    );
  });
}
