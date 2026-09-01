import 'package:test/test.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';

/// The policies are calibrated constants, so their invariants are assertions;
/// see `docs/domain-model/validation-boundaries.md`.
void main() {
  group('alignment costs', () {
    test('may not undercut a match', () {
      for (final build in [
        () => AlignmentPolicy(substitutionCost: -1),
        () => AlignmentPolicy(insertionCost: -1),
        () => AlignmentPolicy(deletionCost: -1),
      ]) {
        expect(build, throwsA(isA<AssertionError>()));
      }
    });

    test('leave a wrong note priced either way', () {
      // Both readings stay affordable however the costs are set, which is what
      // keeps `prefersSubstitution` a policy question rather than a constraint.
      final generous = AlignmentPolicy(
        substitutionCost: 5,
        insertionCost: 1,
        deletionCost: 1,
      );

      expect(generous.prefersSubstitution, isFalse);
    });
  });

  group('grouping', () {
    test('may not outbid a correspondence decision', () {
      expect(
        () => AlignmentPolicy(substitutionCost: 2, maxGroupingPreference: 3),
        throwsA(isA<AssertionError>()),
      );
    });

    test('needs a region between its confident edges', () {
      expect(
        () => ObservationGroupingPolicy(
          confidentlySameMs: 300,
          confidentlySeparateMs: 250,
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => ObservationGroupingPolicy(confidentlySameMs: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
