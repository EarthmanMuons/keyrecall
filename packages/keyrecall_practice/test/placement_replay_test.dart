import 'dart:io';

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
  /// A sitting over [profile], run [attempts] deep when asked.
  Future<PracticeSession> sessionOver(
    PracticeStore store,
    Profile profile, {
    int attempts = 0,
  }) async {
    final session = await PracticeSession.open(
      store: store,
      profile: profile,
      materials: fixtureMaterials,
      learner: learner,
      sessionId: 'session-1',
      nextId: countingIds(),
    );
    if (attempts > 0) await practise(session, attempts: attempts);
    return session;
  }

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

  test('a profile directory is enough to reopen the learner', () async {
    // The invariant the layout exists for. The genesis is a hundred bytes and
    // the history it governs is not, so losing the index must cost a selection
    // rather than every profile's evidence on the install.
    final root = Directory.systemTemp.createTempSync('keyrecall_genesis');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = FileProfileRepository(root);
    final profile = await repository.create(
      displayName: 'Alice',
      placement: PlacementTier.beginner,
      createdAt: t0,
    );
    final store = FilePracticeStore(root);
    final expected = learnerStateHash(
      (await sessionOver(store, profile, attempts: 6)).state,
    );

    repository.indexFile.deleteSync();

    final rebuilt = await repository.list();
    expect(rebuilt.single, profile, reason: 'including its placement');
    expect(
      await repository.selected(),
      isNull,
      reason: 'who was active is the part that really was only in that file',
    );
    expect(
      learnerStateHash((await sessionOver(store, rebuilt.single)).state),
      expected,
      reason: 'and the history replays from the genesis beside it',
    );
  });

  test('practice storage with no profile beside it is not a person', () async {
    // The other side of scanning: a directory is read because it holds a
    // profile's record of itself, never because it is named like one. This is
    // what a deleted profile's leftover history looks like.
    final root = Directory.systemTemp.createTempSync('keyrecall_orphan');
    addTearDown(() => root.deleteSync(recursive: true));
    final repository = FileProfileRepository(root);
    final profile = await repository.create(
      displayName: 'Alice',
      placement: PlacementTier.beginner,
      createdAt: t0,
    );
    await sessionOver(FilePracticeStore(root), profile, attempts: 2);

    await repository.delete(profile.id);

    expect(await repository.list(), isEmpty);
    expect(
      File('${root.path}/${profile.id}/journal.jsonl').existsSync(),
      isTrue,
      reason:
          'forgetting who somebody is and destroying what they played are '
          'still different decisions',
    );
  });

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
