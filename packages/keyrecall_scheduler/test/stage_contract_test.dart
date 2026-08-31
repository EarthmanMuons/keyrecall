import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What a trace says about the stages a candidate did not reach.
///
/// Qualification is answered for every candidate, because "why not that one?"
/// has to be answerable from the trace. Ranking is not: a candidate that never
/// competed has no key, and inventing one would be a number presented as
/// though it meant something. It is also what keeps a slot from computing
/// ranking terms for candidates that cannot consume them, which is most of
/// them.
void main() {
  final candidates = generateCandidates(InstrumentProfile(), allScales);

  List<CandidateTrace> tracesFor(LearnerState state) => pipeline.evaluate(
    state: state,
    session: SessionState(),
    candidates: candidates,
    at: t0,
  );

  for (final tier in [PlacementTier.beginner, PlacementTier.advanced]) {
    group('for a ${tier.name} learner', () {
      final traces = tracesFor(stateAt(tier));

      test('every candidate carries the qualification stages', () {
        for (final trace in traces) {
          expect(trace.eligibility.code, isNotNull);
          expect(trace.prediction.overallP, isNotNaN);
          expect(trace.safety, isNotNull);
        }
      });

      test('a candidate that reached ranking has a key', () {
        final ranked = traces.where((trace) => trace.priorityStatus.isReached);

        expect(ranked, isNotEmpty);
        for (final trace in ranked) {
          expect(trace.rankKey, isNotNull);
          expect(trace.isRanked, isTrue);
        }
      });

      test('and one that did not has none', () {
        final unranked = traces.where(
          (trace) => !trace.priorityStatus.isReached,
        );

        expect(unranked, isNotEmpty);
        for (final trace in unranked) {
          expect(
            trace.rankKey,
            isNull,
            reason:
                'ranking was never reached for ${trace.exercise}, so a key '
                'would be a value it could not have competed on',
          );
          expect(trace.isRanked, isFalse);
        }
      });

      test('the coordination transition is recorded either way', () {
        // A fact about the candidate rather than a ranking term, so refusing a
        // candidate must not erase it: a diagnostic asking which candidates
        // were transitions needs the refused ones most.
        for (final trace in traces) {
          expect(
            trace.coordinationTransition,
            isCoordinationTransition(stateAt(tier), trace.exercise),
          );
        }
      });

      test('most candidates never reach ranking', () {
        final ranked = traces.where((trace) => trace.isRanked).length;

        expect(
          ranked,
          lessThan(traces.length),
          reason: 'otherwise deferring the ranking terms saves nothing',
        );
      });
    });
  }
}
