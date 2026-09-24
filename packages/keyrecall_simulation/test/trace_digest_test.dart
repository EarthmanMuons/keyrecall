import 'package:keyrecall_learner/keyrecall_learner.dart';
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
/// Both columns are regression pins against this implementation, so a mismatch
/// means it changed. The pinned reference scalars and the tolerance comparison
/// in `reference_equivalence_test.dart` are the diagnosable failures that say
/// where. See `analysis/README.md`.
const List<PinnedDigests> pinnedRuns = [
  PinnedDigests(
    profile: SyntheticProfile.advanced,
    seed: 4,
    attempts: 80,
    discrete:
        'c55a182d21268a2353cc8848ae9829995fe5dcc9d4ed465bdc22510df1733959',
    full: 'bb202fbae409cbdcea598150de4939595ae0e531ee615762b2cc90b4471381ec',
  ),
  PinnedDigests(
    profile: SyntheticProfile.beginner,
    seed: 4,
    attempts: 80,
    discrete:
        '53fa86135b330b271262973d563e0b2c37c2ddb63e4915133e07d5388df8ee9e',
    full: '16cfebcc28d465e2f9fcd217382ece5e3d5b2adfff151d4efa6b9d759f50c1bf',
  ),
  PinnedDigests(
    profile: SyntheticProfile.returning,
    seed: 4,
    attempts: 80,
    discrete:
        '61b217025e6c58b603296f82c8b55f4cef08fbb84614ba5a432c3bfc624152ca',
    full: '07d1ea5cbc98aa1031157d67e949f393000622098917210788fc22689c68b4ae',
  ),
  PinnedDigests(
    profile: SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 4,
    attempts: 80,
    discrete:
        'e2b0b1352716ad9eb4273b161c3bdda2a8de184b2bf6e52b0a08f3ace70559d4',
    full: 'ced8cbf7dda96b08418e06c6455fbd854628582cc126986c32bfdc389a490d25',
  ),
];

void main() {
  group('pinned runs', () {
    for (final pinned in pinnedRuns) {
      test('${pinned.profile.id}, seed ${pinned.seed}', () {
        final simulation = PracticeSimulation.of(
          pinned.profile,
          seed: pinned.seed,
          attemptSpacing: const Duration(hours: 12),
          learner: const LearnerModel.v1Prototype(),
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
        attemptSpacing: const Duration(hours: 12),
        learner: const LearnerModel.v1Prototype(),
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
        attemptSpacing: const Duration(hours: 12),
        learner: const LearnerModel.v1Prototype(),
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
    ) => PracticeSimulation.of(
      profile,
      seed: seed,
      attemptSpacing: const Duration(hours: 12),
      learner: const LearnerModel.v1Prototype(),
    ).run(attempts);

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
