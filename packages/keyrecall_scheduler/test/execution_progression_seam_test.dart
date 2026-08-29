import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// Execution progression through the whole pipeline rather than in isolation.
///
/// The unit tests say what an adjacent step is; these say that one can
/// actually be chosen. The refinement stage is the reason both are needed: a
/// classification is worth nothing if the candidate it would classify never
/// reaches the loop that evaluates candidates.
void main() {
  const pipeline = SchedulerPipeline(learner: LearnerModel());
  final material = TechnicalMaterial('C', ScaleForm.major);
  final catalog = [material, TechnicalMaterial('G', ScaleForm.major)];

  /// A learner who owns C major in the hands given, at one octave and 60.
  LearnerState owning(
    List<HandConfiguration> hands, {
    bool retrieved = true,
    double tempoBpm = 60,
  }) {
    final state = stateAt(PlacementTier.someExperience);
    final memory = state.materialMemoryFor('C_MAJOR', v1PrototypeLearnerParams);
    if (retrieved) memory.factualLastRetrievalAt = t0;
    for (final configuration in hands) {
      state.materialExecutionFor(
          ('C_MAJOR', configuration),
          t0,
          v1PrototypeLearnerParams,
        )
        ..demonstrate(octaves: 1, tempoBpm: tempoBpm)
        ..lastEvidenceAt = t0;
    }
    return state;
  }

  List<CandidateTrace> evaluate(LearnerState state) => pipeline.evaluate(
    state: state,
    session: SessionState(),
    candidates: generateCandidates(InstrumentProfile(), catalog),
    at: t0.plusDays(1),
  );

  Iterable<CandidateTrace> progressing(List<CandidateTrace> traces) =>
      traces.where(
        (trace) =>
            trace.challengeBypass == ChallengeBypass.executionProgression,
      );

  test('the next tempo rung can be chosen, not merely generated', () {
    final state = owning([HandConfiguration.right]);

    final stepped = progressing(evaluate(state)).where(
      (trace) =>
          trace.exercise.conditions.tempoBpm == 63 &&
          trace.exercise.conditions.octaves == 1,
    );

    expect(stepped, isNotEmpty);
    expect(stepped.every((trace) => trace.challengeSurvived), isTrue);
  });

  test('a span step on owned material reaches admission', () {
    final state = owning([HandConfiguration.right]);

    expect(
      progressing(evaluate(state)).where(
        (trace) =>
            trace.exercise.conditions.octaves == 2 &&
            trace.exercise.conditions.hands == HandConfiguration.right,
      ),
      isNotEmpty,
    );
  });

  test('both hands make going together reachable', () {
    final together =
        progressing(
          evaluate(owning([HandConfiguration.right, HandConfiguration.left])),
        ).where(
          (trace) =>
              trace.exercise.conditions.hands == HandConfiguration.together,
        );

    expect(together, isNotEmpty);
    expect(
      progressing(evaluate(owning([HandConfiguration.right]))).where(
        (trace) =>
            trace.exercise.conditions.hands == HandConfiguration.together,
      ),
      isEmpty,
      reason: 'one hand is not two',
    );
  });

  test('two steps at once never survive, however they predict', () {
    // The payoff of naming multiple. Information gain prefers exactly this
    // candidate, so the guarantee has to be structural rather than a matter
    // of it ranking badly.
    final state = owning([HandConfiguration.right]);
    final admitted = evaluate(state).where(
      (trace) =>
          trace.challengeSurvived &&
          executionAdvanceFor(state, trace.exercise) ==
              ExecutionAdvance.multiple,
    );

    expect(admitted, isEmpty);
  });

  test('material shown but never produced goes to consolidation', () {
    // The two paths partition material state, and this is the boundary:
    // playing a scale well while looking at it demonstrates the conditions
    // and not the scale.
    // Both hands, so nothing is left to introduce: a hand that has never
    // played this scale is an introduction of its own and would rightly come
    // first.
    final state = owning([
      HandConfiguration.right,
      HandConfiguration.left,
    ], retrieved: false);
    final traces = pipeline.evaluate(
      state: state,
      session: SessionState(),
      candidates: generateCandidates(InstrumentProfile(), [material]),
      at: t0.plusDays(1),
    );

    expect(progressing(traces), isEmpty);
    expect(
      traces.where(
        (trace) => trace.challengeBypass == ChallengeBypass.consolidation,
      ),
      isNotEmpty,
    );
  });

  test('material never met goes to introduction', () {
    final state = owning([HandConfiguration.right]);
    final other = evaluate(
      state,
    ).where((trace) => trace.exercise.material.materialId == 'G_MAJOR');

    expect(
      other.where(
        (trace) =>
            trace.challengeBypass == ChallengeBypass.executionProgression,
      ),
      isEmpty,
    );
    expect(
      other.where(
        (trace) => trace.challengeBypass == ChallengeBypass.newMaterial,
      ),
      isNotEmpty,
    );
  });

  test('both the set-level fact and the loop read the refined set', () {
    // The stage boundary itself. Computing one from the raw candidates while
    // the other saw the refined ones would make two universes of one slot,
    // and the winner might be from either.
    final state = owning([HandConfiguration.right]);
    final raw = generateCandidates(InstrumentProfile(), catalog);
    final refined = withExecutionNeighbours(state, raw);

    expect(refined.length, greaterThan(raw.length));
    expect(
      evaluate(state),
      hasLength(refined.length),
      reason: 'every refined candidate was evaluated',
    );
    expect(
      pipeline.introducibleTier(state, refined),
      pipeline.introducibleTier(state, raw),
      reason:
          'and the stratum is the same fact either way here, which is '
          'what makes reading it from the refined set safe rather than '
          'merely consistent',
    );
  });
}
