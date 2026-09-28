import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// Whether an attempt tested the learner keeping the pulse is decided by what
/// reached them once it began, not by what was asked for.
void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    tempoBpm: 100,
  );

  PulseMaintenance pulseUnder(TempoDelivery? tempo) => outcomeFor(
    measurement: measure(
      realization: realize(exercise),
      transcript: PerformanceTranscript.empty,
    ),
    exercise: exercise,
    delivery: tempo == null ? null : PresentationDelivery(tempo: tempo),
  ).pulseMaintenance;

  test('an attempt that presented nothing tested the pulse', () {
    expect(pulseUnder(null), PulseMaintenance.tested);
  });

  test('a count-in alone tested the pulse', () {
    expect(pulseUnder(TempoDelivery.complete(4)), PulseMaintenance.tested);
  });

  test('a metronome that sounded did not', () {
    expect(
      pulseUnder(TempoDelivery.complete(4, continuingBeats: 12)),
      PulseMaintenance.notTested,
    );
  });

  test('a metronome that started late did not, from its first beat', () {
    expect(
      pulseUnder(
        TempoDelivery(
          countInBeats: 4,
          continuingBeats: 12,
          deliveredCountInBeats: 0,
          deliveredContinuingBeats: 1,
        ),
      ),
      PulseMaintenance.notTested,
    );
  });

  test('a metronome that failed before the downbeat tested the pulse', () {
    expect(
      pulseUnder(
        TempoDelivery(
          countInBeats: 4,
          continuingBeats: 12,
          deliveredCountInBeats: 4,
          deliveredContinuingBeats: 0,
        ),
      ),
      PulseMaintenance.tested,
    );
  });

  test('a metronome that never sounded tested the pulse', () {
    expect(
      pulseUnder(TempoDelivery.silent(4, continuingBeats: 12)),
      PulseMaintenance.tested,
    );
  });
}
