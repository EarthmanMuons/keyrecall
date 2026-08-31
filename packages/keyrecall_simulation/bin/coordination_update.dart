import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

const _reading = 0.385;
const _checkpoints = {1, 2, 5, 10, 25};
final _start = DateTime.utc(2026);

/// Accounts for repeated direct coordination evidence without a scheduler.
void main() {
  const model = LearnerModel();
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
    guidance: GuidanceContext.continuouslyCued,
  );
  final outcome = Outcome(
    started: true,
    retrieval: FactualRetrieval.notTested,
    completed: false,
    materialRetrieval: 1.0,
    pitchIntegrity: 1.0,
    continuity: _reading,
    temporalStability: _reading,
    achievedTempoRatio: 1.0,
    topologyAccuracy: 1.0,
    coordination: _reading,
  );

  final immediate = _audit(
    model: model,
    exercise: exercise,
    outcome: outcome,
    spacing: Duration.zero,
  );
  final propagated = _audit(
    model: model,
    exercise: exercise,
    outcome: outcome,
    spacing: const Duration(minutes: 1),
  );

  final first = propagated.first;
  stdout
    ..writeln('coordination update accounting')
    ..writeln('  prediction       ${_number(first.prediction)}')
    ..writeln('  reading          ${_number(_reading)}')
    ..writeln('  surprise         ${_signed(first.surprise)}')
    ..writeln('  evidence weight  ${_number(first.weight)}')
    ..writeln('  loading          ${_number(first.loading)}')
    ..writeln('  raw delta        ${_signed(first.rawDelta)}')
    ..writeln(
      '  learning rate    ${_number(model.params.competency.learningRate)}',
    )
    ..writeln('  applied delta    ${_signed(first.appliedDelta)}')
    ..writeln('  posterior mean   ${_signed(first.meanAfterUpdate)}')
    ..writeln(
      '  variance         ${_number(first.varianceBefore)} -> '
      '${_number(first.varianceAfterUpdate)}',
    )
    ..writeln('  mean propagated  ${_signed(first.meanAfterPropagation)}')
    ..writeln('  next probability ${_number(first.nextProbability)}')
    ..writeln()
    ..writeln('repeated reading ${_number(_reading)}')
    ..writeln(
      '${'elapsed'.padRight(12)}${'n'.padLeft(4)}'
      '${'mean'.padLeft(13)}${'probability'.padLeft(14)}'
      '${'sum surprise'.padLeft(16)}',
    );

  for (final run in [('none', immediate), ('one minute', propagated)]) {
    for (final step in run.$2.where((step) => _checkpoints.contains(step.n))) {
      stdout.writeln(
        '${run.$1.padRight(12)}${step.n.toString().padLeft(4)}'
        '${_signed(step.meanAfterPropagation).padLeft(13)}'
        '${_number(step.nextProbability).padLeft(14)}'
        '${_signed(step.cumulativeSurprise).padLeft(16)}',
      );
    }
  }
}

List<_Step> _audit({
  required LearnerModel model,
  required Exercise exercise,
  required Outcome outcome,
  required Duration spacing,
}) {
  final competency = Competency.handsTogetherCoordination;
  final state = model.newState(at: _start);
  final loading = coordinationLoadings(exercise.structuralQ)[competency]!;
  final steps = <_Step>[];
  var at = _start;
  var cumulativeSurprise = 0.0;

  for (var n = 1; n <= 25; n++) {
    final prediction = model.coordinationProbability(state, exercise);
    final surprise = _reading - prediction;
    final weights = evidenceWeightsFor(exercise, outcome);
    final weight = weights[competency];
    final rawDelta = surprise * weight * loading;
    final belief = state.competency(competency);
    final meanBefore = belief.mean;
    final varianceBefore = belief.variance;

    model.applyOutcome(
      state: state,
      exercise: exercise,
      outcome: outcome,
      weights: weights,
      prediction: model.predict(state, exercise, at: at),
      at: at,
    );

    final meanAfterUpdate = state.competency(competency).mean;
    final varianceAfterUpdate = state.competency(competency).variance;
    at = at.add(spacing);
    model.propagate(state, at);
    final meanAfterPropagation = state.competency(competency).mean;
    cumulativeSurprise += surprise;
    steps.add(
      _Step(
        n: n,
        prediction: prediction,
        surprise: surprise,
        weight: weight,
        loading: loading,
        rawDelta: rawDelta,
        appliedDelta: meanAfterUpdate - meanBefore,
        meanAfterUpdate: meanAfterUpdate,
        varianceBefore: varianceBefore,
        varianceAfterUpdate: varianceAfterUpdate,
        meanAfterPropagation: meanAfterPropagation,
        nextProbability: model.coordinationProbability(state, exercise),
        cumulativeSurprise: cumulativeSurprise,
      ),
    );
  }
  return steps;
}

class _Step {
  final int n;
  final double prediction;
  final double surprise;
  final double weight;
  final double loading;
  final double rawDelta;
  final double appliedDelta;
  final double meanAfterUpdate;
  final double varianceBefore;
  final double varianceAfterUpdate;
  final double meanAfterPropagation;
  final double nextProbability;
  final double cumulativeSurprise;

  const _Step({
    required this.n,
    required this.prediction,
    required this.surprise,
    required this.weight,
    required this.loading,
    required this.rawDelta,
    required this.appliedDelta,
    required this.meanAfterUpdate,
    required this.varianceBefore,
    required this.varianceAfterUpdate,
    required this.meanAfterPropagation,
    required this.nextProbability,
    required this.cumulativeSurprise,
  });
}

String _number(double value) => value.toStringAsFixed(6);

String _signed(double value) => '${value < 0 ? '' : '+'}${_number(value)}';
