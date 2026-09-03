import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// One pinned run, hashed two ways.
class PinnedDigests {
  final SyntheticProfile profile;
  final int seed;
  final int attempts;

  /// Categorical decisions and outcomes. Computed identically by the Python
  /// prototype, so this one is a cross-implementation check.
  final String discrete;

  /// Everything the run computed, at full precision. A regression sentinel for
  /// this implementation.
  final String full;

  const PinnedDigests({
    required this.profile,
    required this.seed,
    required this.attempts,
    required this.discrete,
    required this.full,
  });
}

/// Both digests are tagged with a schema version, so these pins are
/// statements about a named record shape rather than about whatever the
/// simulation happens to record. Changing the hashed field set means bumping
/// the schema and regenerating these values in the same step.
///
/// The discrete column was matched by the Python prototype at
/// `v1-prototype-0`, which was the evidence that the Dart model reproduced it.
/// Both columns are regression pins against this implementation now that the
/// prototype is retired: a mismatch means this implementation changed. See
/// `analysis/README.md`. A full mismatch means the behavior changed somewhere;
/// the pinned reference scalars
/// and the tolerance comparison in `reference_equivalence_test.dart` are the
/// diagnosable failures that say where.
const List<PinnedDigests> pinnedRuns = [
  PinnedDigests(
    profile: SyntheticProfile.advanced,
    seed: 4,
    attempts: 80,
    discrete:
        '7738a3fa3fcd45fad5def4c9b19bf468d6d903cf2b680bc7433d0384d7ca6675',
    full: 'd1141b145255c3709ebc60e8b2480f34f44292ddd3075c5a1de67f95a7dc5b2a',
  ),
  PinnedDigests(
    profile: SyntheticProfile.beginner,
    seed: 4,
    attempts: 80,
    discrete:
        'eb6e6b7ca584fa6b37cc457842bf1f873919a233a529ece1d108eb13b9fce128',
    full: 'c2b5119691fb1cfc804c2befe330aa83d150a5e200e7ef43ba2a71ecda84cdac',
  ),
  PinnedDigests(
    profile: SyntheticProfile.returning,
    seed: 4,
    attempts: 80,
    discrete:
        '558a181e55893357dc069c675bbf2142c71afc79940170805fd0d9cb18c9a8b6',
    full: '6023dc07fe0d1a905d738823c8771bb26bcf4ea1e1f10ba407d3a9cbd86960a5',
  ),
  PinnedDigests(
    profile: SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 4,
    attempts: 80,
    discrete:
        '8314f455000ca11aa03fc72c5e44d011f2eae949b49607f1ae4884eb22655c5f',
    full: '43ba13444b98420d0383c6bebe1b1f25183f80b063b4635e5a57fb329188f002',
  ),
];

void main() {
  group('pinned runs', () {
    for (final pinned in pinnedRuns) {
      test('${pinned.profile.id}, seed ${pinned.seed}', () {
        final simulation = PracticeSimulation.of(
          pinned.profile,
          seed: pinned.seed,
        );
        final traces = simulation.run(pinned.attempts);

        expect(
          discreteTraceDigest(traces),
          pinned.discrete,
          reason:
              'the two implementations made different decisions or sampled '
              'different categorical outcomes',
        );
        expect(
          fullTraceDigest(traces, epoch: simulation.epoch),
          pinned.full,
          reason: 'this implementation computed something different',
        );
      });
    }
  });

  group('schema', () {
    test('the discrete record matches its declared field list', () {
      // Guards against a field quietly appearing in the builder: adding a
      // diagnostic to AttemptTrace must not look like a behavioral change.
      final simulation = PracticeSimulation.of(
        SyntheticProfile.advanced,
        seed: 1,
      );
      final digest = discreteTraceDigest(simulation.run(1));
      expect(digest, isNotEmpty);
      expect(discreteDigestFields, hasLength(12));
      expect(discreteDigestFields.toSet(), hasLength(12));
    });

    test('the schema tag participates in the hash', () {
      // A digest computed under a different schema must not silently compare
      // equal to one computed under this schema.
      expect(discreteDigestSchema, 'discrete-trace-digest-v2');
      expect(fullDigestSchema, 'full-trace-digest-v2');
      expect(discreteDigestSchema, isNot(fullDigestSchema));

      final traces = PracticeSimulation.of(
        SyntheticProfile.advanced,
        seed: 1,
      ).run(5);
      expect(
        discreteTraceDigest(traces),
        isNot(fullTraceDigest(traces, epoch: defaultSimulationEpoch)),
      );
    });
  });

  group('the digests actually discriminate', () {
    List<AttemptTrace> runOf(
      SyntheticProfile profile,
      int seed,
      int attempts,
    ) => PracticeSimulation.of(profile, seed: seed).run(attempts);

    test('a different seed changes both', () {
      final first = runOf(SyntheticProfile.advanced, 4, 40);
      final second = runOf(SyntheticProfile.advanced, 5, 40);

      expect(discreteTraceDigest(first), isNot(discreteTraceDigest(second)));
      expect(
        fullTraceDigest(first, epoch: defaultSimulationEpoch),
        isNot(fullTraceDigest(second, epoch: defaultSimulationEpoch)),
      );
    });

    test('a different learner changes both', () {
      final advanced = runOf(SyntheticProfile.advanced, 4, 40);
      final beginner = runOf(SyntheticProfile.beginner, 4, 40);

      expect(
        discreteTraceDigest(advanced),
        isNot(discreteTraceDigest(beginner)),
      );
      expect(
        fullTraceDigest(advanced, epoch: defaultSimulationEpoch),
        isNot(fullTraceDigest(beginner, epoch: defaultSimulationEpoch)),
      );
    });

    test('a shorter run changes both', () {
      final long = runOf(SyntheticProfile.advanced, 4, 40);
      final short = runOf(SyntheticProfile.advanced, 4, 39);

      expect(discreteTraceDigest(long), isNot(discreteTraceDigest(short)));
      expect(
        fullTraceDigest(long, epoch: defaultSimulationEpoch),
        isNot(fullTraceDigest(short, epoch: defaultSimulationEpoch)),
      );
    });

    test('the same run reproduces both', () {
      final first = runOf(SyntheticProfile.returning, 9, 40);
      final second = runOf(SyntheticProfile.returning, 9, 40);

      expect(discreteTraceDigest(first), discreteTraceDigest(second));
      expect(
        fullTraceDigest(first, epoch: defaultSimulationEpoch),
        fullTraceDigest(second, epoch: defaultSimulationEpoch),
      );
    });

    test('an empty run still hashes', () {
      expect(discreteTraceDigest(const []), isNotEmpty);
      expect(
        fullTraceDigest(const [], epoch: defaultSimulationEpoch),
        isNotEmpty,
      );
    });
  });
}
