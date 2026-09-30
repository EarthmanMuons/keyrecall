import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:keyrecall_scheduler/src/selection_diagnostics.dart';

import 'selection_test.dart' show admittedTrace;
import 'support/fixtures.dart';

void main() {
  final scale = admittedTrace(
    exerciseFor(materials.first),
    retention: 0.1,
    information: 1,
  );
  final arpeggio = admittedTrace(
    exerciseFor(ArpeggioMaterial('C', ArpeggioQuality.major)),
    retention: 0.2,
    information: 0,
  );

  String report({bool removeScale = false}) => selectionDiagnostics(
    traces: [scale, arpeggio],
    stages: {
      'repetition': [scale, arpeggio],
      'pacing': [if (!removeScale) scale, arpeggio],
    },
    winner: arpeggio,
    state: stateAt(PlacementTier.beginner),
    pacing: removeScale ? 'relieved' : 'inactive',
    introductions: 'inactive',
    freshProbe: false,
    tempoProbe: null,
    guidanceService: false,
  );

  test('explains the first decisive field even when a later field loses', () {
    expect(
      report(),
      contains('winner_vs_best_selectable_scale=retention:0.2>0.1'),
    );
    expect(report(), contains('scale_candidate=0'));
    expect(report(), contains('family=SCALE'));
    expect(report(), contains('family=ARPEGGIO'));
  });

  test('keeps the best admitted scale visible after a filter removes it', () {
    expect(report(removeScale: true), contains('no_selectable_scale'));
    expect(report(removeScale: true), contains('removed:pacing'));
    expect(report(removeScale: true), contains('candidate=0'));
  });

  test('distinguishes a rank tie from a scoring advantage', () {
    expect(
      rankDifference(scale.rankKey!, scale.rankKey!),
      'exact_rank_tie_candidate_order',
    );
  });

  test('a slot decided without diagnostics decides the same', () {
    const pipeline = SchedulerPipeline(learner: LearnerModel());
    SelectionResult decide({required bool diagnose}) => pipeline
        .evaluateSlot(
          state: stateAt(PlacementTier.advanced),
          session: SessionState(),
          candidates: allCandidates(),
          at: t0,
          diagnose: diagnose,
        )
        .result;

    final described = decide(diagnose: true) as CandidateSelected;
    final undescribed = decide(diagnose: false) as CandidateSelected;

    expect(undescribed.diagnostics, isEmpty);
    expect(described.diagnostics, isNotEmpty);
    expect(undescribed.candidate.exercise, described.candidate.exercise);
    expect(
      [for (final trace in undescribed.selectable) trace.exercise],
      [for (final trace in described.selectable) trace.exercise],
    );
  });
}
