import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'support/fixtures.dart';

/// Attempt ordering is part of the model contract, not a calling convention.
///
/// Folding evidence into a state that has already moved past the attempt
/// corrupts replay without ever failing, so it fails here instead.
void main() {
  group('ordering', () {
    test('an attempt may not predate the state it updates', () {
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));

      expect(
        () => applyAttempt(
          state,
          exerciseFor(cMajor),
          perfectOutcome(),
          at: t0.plusDays(5),
        ),
        throwsArgumentError,
      );
    });

    test('an attempt may not predate the memory it updates', () {
      final state = model.newState(at: t0);
      final memory = state.materialMemoryFor(cMajor.materialId, params);
      anchorMemory(memory, t0.plusDays(20));
      // Propagation is current, so only the memory history is out of order.
      model.propagate(state, t0.plusDays(20));

      expect(
        () => applyAttempt(
          state,
          exerciseFor(cMajor),
          perfectOutcome(),
          at: t0.plusDays(15),
        ),
        throwsArgumentError,
      );
    });

    test('an out-of-order attempt writes nothing', () {
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));
      final meanBefore = state.competency(Competency.rhScaleExecution).mean;

      expect(
        () => applyAttempt(
          state,
          exerciseFor(cMajor),
          perfectOutcome(),
          at: t0.plusDays(5),
        ),
        throwsArgumentError,
      );

      expect(state.competency(Competency.rhScaleExecution).mean, meanBefore);
      expect(
        state.materialMemory,
        isEmpty,
        reason: 'a rejected attempt must not even create a memory entry',
      );
      expect(state.materialExecution, isEmpty);
    });

    test('an attempt at exactly the current instant is in order', () {
      final state = model.newState(at: t0);
      model.propagate(state, t0.plusDays(10));

      expect(
        () => applyAttempt(
          state,
          exerciseFor(cMajor),
          perfectOutcome(),
          at: t0.plusDays(10),
        ),
        returnsNormally,
      );
    });
  });
}
