import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// What moves `HANDS_TOGETHER_COORDINATION`, and what must not.
///
/// The competency exists because two hands are a distinct skill. Learning it
/// from how unbroken and how steady the playing was would say it had been
/// measured when nothing measured it.
void main() {
  final handsTogether = exerciseFor(cMajor, hands: HandConfiguration.together);
  final rightHand = exerciseFor(cMajor);

  double coordinationMeanAfter({
    required Exercise exercise,
    required Outcome outcome,
  }) {
    final state = model.newState(at: t0);
    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: evidenceWeightsFor(exercise, outcome),
      prediction: model.predict(state, exercise, at: t0),
      at: t0,
    );
    return state.competency(Competency.handsTogetherCoordination).mean;
  }

  final untouched = model
      .newState(at: t0)
      .competency(Competency.handsTogetherCoordination)
      .mean;

  test('a flawless single-hand attempt says nothing about it', () {
    expect(
      coordinationMeanAfter(exercise: rightHand, outcome: perfectOutcome()),
      untouched,
    );
  });

  test('nor does a two-hand attempt that measured no coordination', () {
    expect(
      coordinationMeanAfter(exercise: handsTogether, outcome: perfectOutcome()),
      untouched,
      reason:
          'otherwise a perfect motor score would stand in for evidence '
          'about coordination',
    );
  });

  test('a measured attempt moves it', () {
    expect(
      coordinationMeanAfter(
        exercise: handsTogether,
        outcome: perfectOutcome(coordination: 1.0),
      ),
      greaterThan(untouched),
    );
    expect(
      coordinationMeanAfter(
        exercise: handsTogether,
        outcome: perfectOutcome(coordination: 0.0),
      ),
      lessThan(untouched),
    );
  });

  test('how together the hands were is what it moves with', () {
    final loose = coordinationMeanAfter(
      exercise: handsTogether,
      outcome: perfectOutcome(coordination: 0.2),
    );
    final tight = coordinationMeanAfter(
      exercise: handsTogether,
      outcome: perfectOutcome(coordination: 0.9),
    );

    expect(tight, greaterThan(loose));
  });

  test('an unmeasured attempt carries no weight for it', () {
    final measured = evidenceWeightsFor(
      handsTogether,
      perfectOutcome(coordination: 0.5),
    );
    final unmeasured = evidenceWeightsFor(handsTogether, perfectOutcome());

    expect(measured[Competency.handsTogetherCoordination], greaterThan(0));
    expect(unmeasured[Competency.handsTogetherCoordination], 0);
    expect(
      unmeasured.competencies.containsKey(Competency.handsTogetherCoordination),
      isFalse,
      reason:
          'omitted rather than zero, so the record says it was not '
          'observed rather than observed as uninformative',
    );
  });

  test('the hands the exercise uses still learn from how it was played', () {
    final state = model.newState(at: t0);
    final outcome = perfectOutcome();
    model.applyOutcome(
      state: state,
      exercise: handsTogether,
      outcome: outcome,
      weights: evidenceWeightsFor(handsTogether, outcome),
      prediction: model.predict(state, handsTogether, at: t0),
      at: t0,
    );

    expect(
      state.competency(Competency.rhScaleExecution).mean,
      greaterThan(untouched),
    );
    expect(
      state.competency(Competency.lhScaleExecution).mean,
      greaterThan(untouched),
    );
  });

  test('coordination is not a motor competency', () {
    expect(Competency.handsTogetherCoordination.isMotor, isFalse);
    expect(Competency.handsTogetherCoordination.isCoordination, isTrue);
    expect(
      motorLoadings(handsTogether.structuralQ).keys,
      isNot(contains(Competency.handsTogetherCoordination)),
    );
  });

  test('repeated adverse readings lower the coordination prediction', () {
    final outcome = Outcome(
      started: true,
      retrieval: FactualRetrieval.notTested,
      completed: false,
      materialRetrieval: 1.0,
      pitchIntegrity: 1.0,
      continuity: 0.385,
      temporalStability: 0.385,
      achievedTempoRatio: 1.0,
      topologyAccuracy: 1.0,
      coordination: 0.385,
    );

    double afterRepeatedEvidence(Duration spacing) {
      final state = model.newState(at: t0);
      var at = t0;
      for (var i = 0; i < 25; i++) {
        model.applyOutcome(
          state: state,
          exercise: handsTogether,
          outcome: outcome,
          weights: evidenceWeightsFor(handsTogether, outcome),
          prediction: model.predict(state, handsTogether, at: at),
          at: at,
        );
        at = at.add(spacing);
        model.propagate(state, at);
      }
      return model.coordinationProbability(state, handsTogether);
    }

    final immediate = afterRepeatedEvidence(Duration.zero);
    final oneMinute = afterRepeatedEvidence(const Duration(minutes: 1));
    final initial = model.coordinationProbability(
      model.newState(at: t0),
      handsTogether,
    );

    expect(immediate, lessThan(initial));
    expect(oneMinute, immediate);
  });
}
