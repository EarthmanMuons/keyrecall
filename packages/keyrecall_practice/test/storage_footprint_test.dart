import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// What a history actually costs to keep.
///
/// The journal is retained in full and forever, so how big an attempt is
/// decides whether that is a promise the app can keep. Measured rather than
/// estimated, because the answer settles an architectural question: at these
/// sizes nothing needs compaction, downsampling, or a second summarized store,
/// and the design that would introduce them is not worth its complexity. See
/// `docs/design/data-products.md`.
///
/// The bound is deliberately loose. This is not a budget to optimize against;
/// it is a tripwire for a record that quietly grew by an order of magnitude,
/// which is what would change the answer.
void main() {
  /// A record is comfortably under two kilobytes today. Ten times that would
  /// still be affordable; a hundred times would not.
  const int budgetPerAttempt = 8 * 1024;

  test('an attempt costs about what the storage design assumes', () async {
    final root = Directory.systemTemp.createTempSync('keyrecall_footprint');
    addTearDown(() => root.deleteSync(recursive: true));
    final store = FilePracticeStore(root);

    // Several independent histories rather than one long one, so the sample
    // spans placements, materials, and conditions without the run having to
    // stay plausible over simulated years.
    final sizes = <int>[];
    final everything = <int>[];
    var checkpointBytes = 0;
    for (var run = 0; run < 6; run++) {
      final profile = Profile(
        id: '3f2a6c18-0000-4000-8000-00000000000$run',
        displayName: 'Runner $run',
        createdAt: t0,
        placement: PlacementTier.values[run % PlacementTier.values.length],
      );
      final session = await PracticeSession.open(
        store: store,
        profile: profile,
        materials: v1ScaleCatalog,
        learner: learner,
        sessionId: 'session-$run',
      );
      // A sitting ends when the challenge band admits nothing, which is a fine
      // place to stop measuring.
      try {
        await practise(session, attempts: 12, succeed: run.isEven);
      } on StateError {
        continue;
      }
      await session.saveCheckpoint();

      final journal = File('${root.path}/${profile.id}/journal.jsonl');
      everything.addAll(journal.readAsBytesSync());
      for (final line in journal.readAsLinesSync().skip(1)) {
        sizes.add(line.length + 1);
      }
      checkpointBytes = File(
        '${root.path}/${profile.id}/checkpoint.json',
      ).lengthSync();
    }

    expect(sizes, hasLength(greaterThan(30)));
    final mean = sizes.reduce((a, b) => a + b) / sizes.length;
    final compressed = gzip.encode(everything).length / everything.length;

    // Printed so the projections in the design document can be refreshed from
    // a real number rather than re-derived by hand.
    printOnFailure(
      'attempt: ${mean.round()} bytes mean, '
      '${sizes.reduce((a, b) => a < b ? a : b)} to '
      '${sizes.reduce((a, b) => a > b ? a : b)}; '
      'checkpoint: $checkpointBytes bytes; '
      'gzip: ${(compressed * 100).toStringAsFixed(1)}% of raw',
    );

    expect(
      mean,
      lessThan(budgetPerAttempt),
      reason:
          'a history is kept whole and forever, so an attempt growing by '
          'an order of magnitude changes whether that is affordable',
    );
    expect(
      compressed,
      lessThan(0.5),
      reason:
          'the wire format repeats its keys on every line, so ordinary '
          'compression is the whole answer if size ever does become one',
    );
  });
}
