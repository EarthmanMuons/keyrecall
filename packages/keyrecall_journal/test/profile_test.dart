import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// A shared install has no single learner. The profile owns the history, and
/// these are the guarantees that keeps two people's evidence apart.
void main() {
  test('profile ids are safe filesystem path segments', () {
    for (final id in ['', '.', '..', '../another-profile', 'a/b', r'a\b']) {
      expect(
        () => Profile(
          id: id,
          displayName: 'Alice',
          createdAt: t0,
          placement: PlacementTier.someExperience,
        ),
        throwsArgumentError,
        reason: id,
      );
    }
  });

  group('profile identity', () {
    test('is opaque, so a rename keeps the history', () {
      final alice = Profile.create(
        displayName: 'Alice',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );
      final renamed = alice.renamed('Alice B.');

      expect(renamed.id, alice.id);
      expect(renamed.displayName, 'Alice B.');
      expect(renamed.createdAt, alice.createdAt);
    });

    test('does not collide between two people with the same name', () {
      final first = Profile.create(
        displayName: 'Sam',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );
      final second = Profile.create(
        displayName: 'Sam',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );

      expect(first.id, isNot(second.id));
      expect(first, isNot(second));
    });

    test('is a version 4 UUID', () {
      final ids = {for (var i = 0; i < 500; i++) newProfileId()};

      expect(ids, hasLength(500), reason: 'ids must not repeat');
      for (final id in ids) {
        expect(
          id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-'
              r'[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
    });

    test('round-trips', () {
      final profile = Profile.create(
        displayName: 'Bob',
        createdAt: t0,
        presentationHint: 'teal',
        placement: PlacementTier.someExperience,
      );
      final reread = Profile.fromJson(
        jsonDecode(jsonEncode(profile.toJson())) as Map<String, Object?>,
      );

      expect(reread, profile);
      expect(reread.presentationHint, 'teal');
    });

    test('rejects an empty id or name', () {
      expect(
        () => Profile(
          id: '',
          displayName: 'Bob',
          createdAt: t0,
          placement: PlacementTier.someExperience,
        ),
        throwsArgumentError,
      );
      expect(
        () => Profile(
          id: 'x',
          displayName: '',
          createdAt: t0,
          placement: PlacementTier.someExperience,
        ),
        throwsArgumentError,
      );
    });
  });

  group('placement is recorded, not assumed', () {
    test('every profile written now carries its tier explicitly', () {
      for (final tier in PlacementTier.values) {
        final written = Profile.create(
          displayName: 'Bob',
          createdAt: t0,
          placement: tier,
        ).toJson();

        expect(
          written['placement'],
          tier.id,
          reason:
              'a missing placement has to date a record rather than '
              'describe one, so nothing written now may omit it',
        );
      }
    });

    test('a profile with no placement is refused, not defaulted', () {
      final withoutPlacement = {
        'id': '3f2a6c18-0000-4000-8000-00000000a11c',
        'display_name': 'Alice',
        'created_at': encodeTime(t0),
        'presentation_hint': null,
      };

      expect(
        () => Profile.fromJson(withoutPlacement),
        throwsA(isA<JournalFormatException>()),
        reason:
            'the prior a history was computed against is not something to '
            'guess: a default would reinterpret that history under a starting '
            'state it never ran from',
      );
    });

    test('renaming carries the placement, since identity is untouched', () {
      final profile = Profile.create(
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.beginner,
      );

      expect(profile.renamed('Robert').placement, PlacementTier.beginner);
    });

    test('two profiles differing only in placement are not the same', () {
      Profile placedAt(PlacementTier tier) => Profile(
        id: '3f2a6c18-0000-4000-8000-00000000a11c',
        displayName: 'Alice',
        createdAt: t0,
        placement: tier,
      );

      expect(
        placedAt(PlacementTier.beginner),
        isNot(placedAt(PlacementTier.someExperience)),
      );
    });
  });

  group('history is scoped to its profile', () {
    test('a journal refuses an attempt from another profile', () {
      // The failure this scoping exists to prevent: one person's evidence
      // folded into another person's learner state.
      final recorded = recordSession(attempts: 2);
      final other = Profile.create(
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );
      final exercise = exerciseFor(v1ScaleCatalogFirst);
      final outcome = outcomeOf();

      expect(
        () => recorded.journal.append(
          AttemptRecord(
            journalSequence: recorded.journal.nextSequence,
            identity: AttemptIdentity(
              profileId: other.id,
              attemptId: 'intruder',
              sessionId: 'session-1',
              indexInSession: 99,
              occurredAt: t0.plusDays(100),
            ),
            provenance: provenance,
            exercise: exercise,
            closure: AttemptClosure.measured(
              termination: AttemptTermination.learnerStopped,
              outcome: outcome,
              weights: evidenceWeightsFor(exercise, outcome),
              memoryUpdate: const MemoryUpdateDiagnostics(),
            ),
          ),
        ),
        throwsA(isA<JournalFormatException>()),
      );
      expect(recorded.journal.length, 2);
    });

    test('a record still names its profile once it leaves the journal', () {
      // What makes export, merge, and eventual sync safe: the record does not
      // depend on the file it came from to say whose it is.
      final recorded = recordSession(attempts: 2);
      final record = recorded.journal.records.first;
      final reread = AttemptRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
      );

      expect(reread.profileId, testProfile.id);
      expect(reread.identity.profileId, testProfile.id);
    });

    test('a checkpoint carries its profile and refuses another', () {
      final recorded = recordSession(attempts: 4);
      final replayed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      final other = Profile.create(
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );

      final foreign = LearnerStateCheckpoint.capture(
        profileId: other.id,
        state: replayed.state,
        learnerModelVersion: params.modelVersion,
        throughJournalSequence: 3,
        throughAttemptId: 'attempt-3',
        coversThrough: t0.plusDays(2),
      );

      expect(
        () => replayJournal(
          recorded.journal,
          model: model,
          initial: recorded.initial,
          from: foreign,
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('two profiles on one install keep independent histories', () {
      // The shared-iPad case, end to end: same install, same model, two
      // people, two states that never touch.
      final alice = recordSession(attempts: 6);
      final bob = Profile.create(
        displayName: 'Bob',
        createdAt: t0,
        placement: PlacementTier.someExperience,
      );
      final bobJournal = AttemptJournal(
        JournalHeader(profileId: bob.id, createdAt: t0),
      );
      final bobInitial = model.placementState(PlacementTier.beginner, at: t0);

      // Bob practices one material, badly, while Alice's history stands.
      final state = bobInitial.copy();
      for (var i = 0; i < 4; i++) {
        final at = t0.plusDays(0.5 * (i + 1));
        model.propagate(state, at);
        final before = learnerStateHash(state);
        final exercise = exerciseFor(v1ScaleCatalogFirst);
        final prediction = model.predict(state, exercise, at: at);
        final outcome = outcomeOf(
          retrieval: FactualRetrieval.failed,
          started: false,
          completed: false,
          quality: 0.0,
        );
        final weights = evidenceWeightsFor(exercise, outcome);
        final diagnostics = model.applyOutcome(
          state: state,
          exercise: exercise,
          outcome: outcome,
          weights: weights,
          prediction: prediction,
          at: at,
        );
        bobJournal.append(
          AttemptRecord(
            journalSequence: bobJournal.nextSequence,
            identity: AttemptIdentity(
              profileId: bob.id,
              attemptId: 'bob-$i',
              sessionId: 'bob-session',
              indexInSession: i,
              occurredAt: at,
            ),
            provenance: provenance,
            exercise: exercise,
            closure: AttemptClosure.measured(
              termination: AttemptTermination.learnerStopped,
              outcome: outcome,
              weights: weights,
              memoryUpdate: diagnostics,
            ),
          ).withStateHashes(before: before, after: learnerStateHash(state)),
        );
      }

      final aliceState = replayJournal(
        alice.journal,
        model: model,
        initial: alice.initial,
      );
      final bobState = replayJournal(
        bobJournal,
        model: model,
        initial: bobInitial,
      );

      expect(aliceState.divergences, isEmpty);
      expect(bobState.divergences, isEmpty);
      expect(
        aliceState.stateHash,
        isNot(bobState.stateHash),
        reason: 'two people practicing differently must not share a state',
      );
      expect(
        bobState.state.competency(Competency.rhScaleExecution).mean,
        lessThan(aliceState.state.competency(Competency.rhScaleExecution).mean),
        reason: 'Bob only failed; his estimate should be the lower one',
      );
    });
  });
}
