import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final scale = TechnicalMaterial('C', ScaleForm.major);
  final arpeggio = ArpeggioMaterial('C', ArpeggioQuality.major);
  final set = standardAssessment([scale, arpeggio], repetitions: 3);

  SyntheticPlayer knowing(double scaleFamiliarity) =>
      PlayerArchetypes.developing.copyWith(
        materialFamiliarity: {
          scale.materialId: scaleFamiliarity,
          arpeggio.materialId: 0.5,
        },
      );

  List<Outcome> arpeggioOutcomes(double scaleFamiliarity) {
    final playing = knowing(scaleFamiliarity).begin();
    return [
      for (var repetition = 0; repetition < set.repetitions; repetition++)
        for (final (index, exercise) in set.exercises.indexed)
          if (exercise.material.materialId == arpeggio.materialId)
            playing.play(
              exercise,
              PythonCompatibleRandom(set.streamSeedFor(index, repetition)),
              practising: false,
            ),
    ];
  }

  test('what one material knows cannot move another material of the set', () {
    final unknown = arpeggioOutcomes(0);
    final known = arpeggioOutcomes(1);

    expect(unknown, hasLength(known.length));
    for (final (i, outcome) in unknown.indexed) {
      final other = known[i];
      expect(outcome.started, other.started, reason: 'attempt $i started');
      expect(outcome.retrieval, other.retrieval, reason: 'attempt $i recalled');
      expect(outcome.completed, other.completed);
      expect(outcome.pitchIntegrity, other.pitchIntegrity);
      expect(outcome.continuity, other.continuity);
      expect(outcome.temporalStability, other.temporalStability);
      expect(outcome.materialRetrieval, other.materialRetrieval);
      expect(outcome.topologyAccuracy, other.topologyAccuracy);
      expect(outcome.coordination, other.coordination);
    }
  });

  test('a reading of the unchanged family reads identically', () {
    AssessmentReading readingOf(double scaleFamiliarity) =>
        assess(set, knowing(scaleFamiliarity).begin(), at: DateTime.utc(2026));

    final unknown = readingOf(0).families[TechnicalMaterial.arpeggioFamilyId]!;
    final known = readingOf(1).families[TechnicalMaterial.arpeggioFamilyId]!;

    expect(known.retrieval, unknown.retrieval);
    expect(known.managed, unknown.managed);
    expect(known.started, unknown.started);
    expect(known.pitchIntegrity, unknown.pitchIntegrity);
  });

  test('and the same exercise meets the same draws in either state', () {
    // The stronger property the isolation alone does not give: within one
    // attempt the branches consume a fixed budget, so a material the learner
    // now recalls does not shift its own later draws either.
    // Cued, so both states get past the start and the motor draw is visible
    // in the outcome either way.
    final exercise = Exercise.linear(
      material: scale,
      hands: HandConfiguration.right,
      guidance: GuidanceContext.continuouslyCued,
    );
    Outcome attemptOf(double familiarity) => PlayerArchetypes.developing
        .copyWith(
          materialFamiliarity: {exercise.material.materialId: familiarity},
          noise: 0,
        )
        .begin()
        .play(exercise, PythonCompatibleRandom(7), practising: false);

    final guessing = attemptOf(0);
    final knowing = attemptOf(1);

    expect(guessing.started, isTrue);
    expect(knowing.started, isTrue);
    expect(
      guessing.materialRetrieval,
      isNot(knowing.materialRetrieval),
      reason: 'the two states really do differ on what the notes were worth',
    );
    expect(
      guessing.continuity,
      knowing.continuity,
      reason: 'the motor draw is the same one, taken before retrieval branches',
    );
  });
}
