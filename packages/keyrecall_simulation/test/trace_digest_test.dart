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
/// the schema on both sides.
///
/// Regenerate the discrete column from the reference implementation:
///
/// ```console
/// python3 tool/reference_digest.py --all
/// ```
///
/// The discrete column was matched by the Python prototype at
/// `v1-prototype-0`, which is the evidence that the Dart model reproduces it.
/// Both columns are regression pins now: a mismatch means this implementation
/// changed, and the prototype is frozen provenance rather than something to
/// reconcile against. See `analysis/README.md`. A full mismatch means this
/// implementation's behavior changed somewhere; the pinned reference scalars
/// and the tolerance comparison in `reference_equivalence_test.dart` are the
/// diagnosable failures that say where.
const List<PinnedDigests> pinnedRuns = [
  PinnedDigests(
    profile: SyntheticProfile.advanced,
    seed: 4,
    attempts: 80,
    discrete:
        '9f40161a316a3d9276f30e985475113eb2b81e1182f733cf7f76a0436500c5c3',
    full: 'f1d62ff98f677532308b8e4e179fd3d92f0828ecda33d666c2734a88d8ecef56',
  ),
  PinnedDigests(
    profile: SyntheticProfile.beginner,
    seed: 4,
    attempts: 80,
    discrete:
        'fbc235ede210611b454596f2e6c69986f749b551424022c91fcbce1cba6cbda0',
    full: '22528397b471a5d02710a647755cac8e71ffcadc4088b9100e67ff769e667257',
  ),
  PinnedDigests(
    profile: SyntheticProfile.returning,
    seed: 4,
    attempts: 80,
    discrete:
        'a6ae0d8472c65a3419226181ad97f7a2335d96c44bb0956bbbfdad90799688b2',
    full: '4561512eb4528d4d746fc18461f433f684b8247a6360f2f7e9b147097685cbb3',
  ),
  PinnedDigests(
    profile: SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 4,
    attempts: 80,
    discrete:
        '02f465ce275e69079bdce6d36ba502195c2052f85d1685506289260d345e12d2',
    full: '4351b3caab418a6fc9a66de5f6cfd490af95995e037ff4b13517ce2035773bfc',
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
      expect(discreteDigestFields, hasLength(11));
      expect(discreteDigestFields.toSet(), hasLength(11));
    });

    test('the schema tag participates in the hash', () {
      // A digest computed under a different schema must not silently compare
      // equal to one computed under this schema.
      expect(discreteDigestSchema, 'reference-digest-v1');
      expect(fullDigestSchema, 'full-trace-digest-v1');
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
