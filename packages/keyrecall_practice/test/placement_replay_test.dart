import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

/// Placement is the initial condition replay propagates from.
///
/// Every posterior in a journal is a function of it, so a profile that does
/// not record its own placement cannot reproduce its own state. These tests
/// exist to pin that it really is load-bearing, rather than that the field
/// happens to survive serialization.
void main() {
  /// Runs a real sitting for [profile] and returns what its state hashes to.
  Future<String> hashAfterPractising(
    PracticeStore store,
    Profile profile,
  ) async {
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: fixtureMaterials,
      learner: learner,
      sessionId: 'session-1',
      nextId: countingIds(),
    );
    await practise(session, attempts: 6);
    return learnerStateHash(session.state);
  }

  test(
    'the same history under a different placement is a different state',
    () async {
      // The reason the tier is stored rather than defaulted. Same identity, same
      // materials, same seeded ids, so the sittings are as alike as two sittings
      // can be; only the prior differs.
      final asBeginner = await hashAfterPractising(
        InMemoryPracticeStore(createdAt: t0),
        alicePlacedAt(PlacementTier.beginner),
      );
      final asExperienced = await hashAfterPractising(
        InMemoryPracticeStore(createdAt: t0),
        alicePlacedAt(PlacementTier.someExperience),
      );

      expect(
        asBeginner,
        isNot(asExperienced),
        reason:
            'if these agreed, placement would be decoration and losing it '
            'would cost nothing',
      );
    },
  );

  test(
    'a reopened profile replays faithfully from its own placement',
    () async {
      for (final tier in PlacementTier.values) {
        final store = InMemoryPracticeStore(createdAt: t0);
        final profile = alicePlacedAt(tier);
        final expected = await hashAfterPractising(store, profile);

        // Reopening replays the journal from placement, and open() throws when
        // that does not reproduce what was recorded.
        final reopened = await PracticeSession.open(
          store: store,
          profile: profile,
          materials: fixtureMaterials,
          learner: learner,
          sessionId: 'session-2',
        );

        expect(learnerStateHash(reopened.state), expected, reason: tier.id);
      }
    },
  );

  test(
    'reopening under a different placement is caught, not absorbed',
    () async {
      // What losing the stored tier would look like: the journal is intact and
      // the prior underneath it is not the one it was recorded against.
      final store = InMemoryPracticeStore(createdAt: t0);
      await hashAfterPractising(store, alicePlacedAt(PlacementTier.beginner));

      expect(
        () => PracticeSession.open(
          store: store,
          profile: alicePlacedAt(PlacementTier.advanced),
          materials: fixtureMaterials,
          learner: learner,
          sessionId: 'session-2',
        ),
        throwsA(isA<JournalFormatException>()),
        reason:
            'replaying a history under a prior it was not recorded against '
            'must fail rather than quietly produce a different learner',
      );
    },
  );
}
