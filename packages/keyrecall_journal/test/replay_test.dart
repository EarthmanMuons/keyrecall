import 'dart:convert';

import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// The acceptance conditions that make the journal authoritative.
///
/// If replay does not reproduce recorded history, then learner state is not a
/// function of the journal, and the journal is decoration rather than a source
/// of truth.
void main() {
  group('exact replay', () {
    test('reproduces the recorded state', () {
      final recorded = recordSession(attempts: 8);
      final live = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );

      expect(live.attemptsApplied, 8);
      expect(live.divergences, isEmpty, reason: live.divergences.join('\n'));
      expect(live.stateHash, recorded.journal.records.last.stateAfterHash);
    });

    test('reproduces it again after a serialization round trip', () {
      // Standing in for a process restart: the journal is written out, read
      // back, and replayed by a reader that shares nothing with the writer.
      final recorded = recordSession(attempts: 8);
      final reread = AttemptJournal.fromJsonLines(
        recorded.journal.toJsonLines(),
      );

      final live = replayJournal(
        reread,
        model: model,
        initial: recorded.initial,
      );

      expect(live.divergences, isEmpty, reason: live.divergences.join('\n'));
      expect(live.stateHash, recorded.journal.records.last.stateAfterHash);
    });

    test('reproduces every intermediate state, not only the last', () {
      // Each record carries the hash of the state its decision was made from
      // and the state its update produced. Replay checks both at every step,
      // so a divergence that later cancels out cannot pass.
      final recorded = recordSession(attempts: 8);
      for (final record in recorded.journal.records) {
        expect(record.stateBeforeHash, isNotNull);
        expect(record.stateAfterHash, isNotNull);
      }

      final live = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      expect(live.divergences, isEmpty);
    });

    test('the execution frontier survives a checkpoint and a rebuild', () {
      // It is durable learner state now, so both routes to it have to agree:
      // reading a checkpoint back, and throwing the checkpoint away and
      // replaying the journal that produced it. A field that only one route
      // carries is a divergence that hides until somebody deletes a file.
      final recorded = recordSession(attempts: 8);
      final replayed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );

      final frontiers = replayed.state.materialExecution;
      expect(
        frontiers.values.any((residual) => residual.demonstratedOctaves > 0),
        isTrue,
        reason:
            'a sitting this long demonstrates something, or the rest of '
            'this test is checking that zero equals zero',
      );

      final captured = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: replayed.state,
        learnerModelVersion: params.modelVersion,
        throughJournalSequence: recorded.journal.records.last.journalSequence,
        throughAttemptId: recorded.journal.records.last.identity.attemptId,
        coversThrough: recorded.journal.records.last.identity.occurredAt,
      );
      final reread = LearnerStateCheckpoint.fromJson(
        jsonDecode(jsonEncode(captured.toJson())) as Map<String, Object?>,
        params: params,
      );

      for (final entry in frontiers.entries) {
        final restored = reread.state.materialExecution[entry.key]!;
        expect(
          restored.demonstratedOctaves,
          entry.value.demonstratedOctaves,
          reason: '${entry.key}',
        );
        expect(
          restored.demonstratedTempoByOctaves,
          entry.value.demonstratedTempoByOctaves,
          reason: '${entry.key}',
        );
      }
      expect(
        learnerStateHash(reread.state),
        learnerStateHash(replayed.state),
        reason:
            'and the frontier is part of what the state hashes to, so a '
            'route that lost it would already have been caught',
      );
    });

    test('resuming from a checkpoint reaches the same state', () {
      final recorded = recordSession(attempts: 8);
      final full = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );

      // A checkpoint after attempt 3, then replay only what follows it.
      final partial = replayJournal(
        AttemptJournal(recorded.journal.header)
          ..appendAll(recorded.journal.records.take(4)),
        model: model,
        initial: recorded.initial,
      );
      final checkpoint = LearnerStateCheckpoint.after(
        recorded.journal.records[3],
        state: partial.state,
        learnerModelVersion: params.modelVersion,
      );

      final resumed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
        from: checkpoint,
      );

      expect(resumed.attemptsApplied, 4);
      expect(resumed.divergences, isEmpty);
      expect(
        resumed.stateHash,
        full.stateHash,
        reason: 'a checkpoint must be an accelerator, never a different answer',
      );
    });

    test('a checkpoint resumes correctly across several sessions', () {
      // The failure a within-session index cannot catch: a checkpoint taken in
      // a later session would leave every earlier session unmatched, and
      // replay would reapply all of it on top of a state that already
      // contained it.
      final first = recordSession(attempts: 5, sessionId: 'session-a');
      final second = recordSession(
        attempts: 4,
        sessionId: 'session-b',
        continuing: first.journal,
        fromState: replayJournal(
          first.journal,
          model: model,
          initial: first.initial,
        ).state,
        startDay: 20,
      );
      final journal = second.journal;
      expect(journal.length, 9);
      expect(journal.records.map((r) => r.identity.sessionId).toSet(), {
        'session-a',
        'session-b',
      });

      final full = replayJournal(journal, model: model, initial: first.initial);
      expect(full.divergences, isEmpty);

      // Checkpoint inside the second session, at within-session index 2 but
      // journal sequence 7.
      final at = journal.records[7];
      expect(at.identity.sessionId, 'session-b');
      expect(at.identity.indexInSession, 2);
      expect(at.journalSequence, 7);

      final upTo = AttemptJournal(journal.header)
        ..appendAll(journal.records.take(8));
      final partial = replayJournal(upTo, model: model, initial: first.initial);
      final checkpoint = LearnerStateCheckpoint.after(
        at,
        state: partial.state,
        learnerModelVersion: params.modelVersion,
      );

      final resumed = replayJournal(
        journal,
        model: model,
        initial: first.initial,
        from: checkpoint,
      );

      expect(
        resumed.attemptsApplied,
        1,
        reason: 'only the one attempt after the checkpoint remains',
      );
      expect(resumed.divergences, isEmpty);
      expect(resumed.stateHash, full.stateHash);
    });

    test('a checkpoint whose position names another attempt is refused', () {
      final recorded = recordSession(attempts: 5);
      final replayed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      final wrong = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: replayed.state,
        learnerModelVersion: params.modelVersion,
        throughJournalSequence: 2,
        throughAttemptId: 'some-other-attempt',
        coversThrough: t0,
      );

      expect(
        () => replayJournal(
          recorded.journal,
          model: model,
          initial: recorded.initial,
          from: wrong,
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a checkpoint does not follow the state it was taken from', () {
      // Learner state is mutable, so a checkpoint that aliased it would drift
      // as practice continued and stop matching its own hash.
      final recorded = recordSession(attempts: 3);
      final state = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      ).state;
      final checkpoint = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: state,
        learnerModelVersion: params.modelVersion,
        throughJournalSequence: 2,
        throughAttemptId: recorded.journal.records[2].identity.attemptId,
        coversThrough: t0,
      );

      final exercise = recorded.journal.records.first.exercise;
      final at = recorded.journal.records.last.identity.occurredAt.plusDays(30);
      model.propagate(state, at);
      model.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcomeOf(),
        weights: evidenceWeightsFor(exercise, outcomeOf()),
        prediction: model.predict(state, exercise, at: at),
        at: at,
      );

      expect(
        learnerStateHash(checkpoint.state),
        checkpoint.contentHash,
        reason: 'the captured state must still hash to what it claims',
      );
      expect(learnerStateHash(state), isNot(checkpoint.contentHash));
    });

    test('discarding every checkpoint costs only time', () {
      final recorded = recordSession(attempts: 6);
      final fromScratch = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );

      expect(fromScratch.attemptsApplied, 6);
      expect(fromScratch.stateHash, isNotEmpty);
      expect(fromScratch.divergences, isEmpty);
    });
  });

  group('replay fails loudly', () {
    test('when the recorded model version is not the one replaying', () {
      final recorded = recordSession(attempts: 3);
      final other = LearnerModel(
        params: params.copyWith(modelVersion: 'v1-prototype-99'),
      );

      expect(
        () => replayJournal(
          recorded.journal,
          model: other,
          initial: recorded.initial,
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('when a checkpoint came from another model version, in any mode', () {
      final recorded = recordSession(attempts: 3);
      final checkpoint = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: recorded.initial,
        learnerModelVersion: 'v1-prototype-99',
        throughJournalSequence: 0,
        throughAttemptId: 'attempt-0',
        coversThrough: t0,
      );

      expect(checkpoint.isUsableUnder(params.modelVersion), isFalse);
      for (final mode in ReplayMode.values) {
        expect(
          () => replayJournal(
            recorded.journal,
            model: model,
            initial: recorded.initial,
            from: checkpoint,
            options: ReplayOptions(mode: mode),
          ),
          throwsA(isA<JournalFormatException>()),
          reason:
              'a checkpoint holds one model reading of everything before it, '
              'so seeding another model from it yields a hybrid',
        );
      }
    });

    test('when a recorded state hash does not match the rebuilt state', () {
      final recorded = recordSession(attempts: 4);
      final tampered = AttemptJournal(recorded.journal.header);
      for (var i = 0; i < recorded.journal.records.length; i++) {
        final record = recorded.journal.records[i];
        tampered.append(
          i == 2
              ? record.withStateHashes(
                  before: record.stateBeforeHash!,
                  after: 'not-the-real-hash',
                )
              : record,
        );
      }

      final live = replayJournal(
        tampered,
        model: model,
        initial: recorded.initial,
      );

      expect(live.divergences, isNotEmpty);
      expect(
        live.divergences.map((divergence) => divergence.field),
        contains('state_after_hash'),
      );
    });

    test('and can stop at the first divergence when asked', () {
      final recorded = recordSession(attempts: 4);
      final tampered = AttemptJournal(recorded.journal.header)
        ..appendAll([
          recorded.journal.records.first.withStateHashes(
            before: 'wrong',
            after: 'wrong',
          ),
          ...recorded.journal.records.skip(1),
        ]);

      expect(
        () => replayJournal(
          tampered,
          model: model,
          initial: recorded.initial,
          options: const ReplayOptions(stopOnDivergence: true),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('counterfactual replay', () {
    test('re-estimates the same attempts under a different model', () {
      final recorded = recordSession(attempts: 8);
      final alternative = LearnerModel(
        params: params.copyWith(
          modelVersion: 'v1-experiment-1',
          // The one change under test: a much faster learner.
          competency: const CompetencyParams(
            priorMean: 0.0,
            priorVariance: 1.0,
            minVariance: 0.05,
            learningRate: 0.6,
            uncertaintyDiffusion: 0.01,
            evidenceShrinkage: 0.3,
          ),
        ),
      );

      final counterfactual = replayJournal(
        recorded.journal,
        model: alternative,
        initial: recorded.initial,
        options: const ReplayOptions(mode: ReplayMode.counterfactual),
      );

      expect(counterfactual.attemptsApplied, 8);
      expect(
        counterfactual.divergences,
        isEmpty,
        reason:
            'a counterfactual is not expected to match, so it reports '
            'nothing to reconcile',
      );

      final faithful = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      expect(
        counterfactual.stateHash,
        isNot(faithful.stateHash),
        reason: 'a different estimator should reach a different state',
      );
    });

    test('never mutates the canonical history it reads', () {
      final recorded = recordSession(attempts: 5);
      final before = recorded.journal.toJsonLines();
      final initialHash = learnerStateHash(recorded.initial);

      replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
        options: const ReplayOptions(mode: ReplayMode.counterfactual),
      );

      expect(recorded.journal.toJsonLines(), before);
      expect(
        learnerStateHash(recorded.initial),
        initialHash,
        reason: 'replay must work on a copy, never on the caller"s state',
      );
    });
  });
}
