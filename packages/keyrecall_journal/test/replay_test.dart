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
      final checkpoint = LearnerStateCheckpoint.capture(
        state: partial.state,
        learnerModelVersion: params.modelVersion,
        sessionId: 'session-1',
        throughIndexInSession: 3,
        coversThrough: recorded.journal.records[3].identity.occurredAt,
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

    test('when a checkpoint came from another model version', () {
      final recorded = recordSession(attempts: 3);
      final checkpoint = LearnerStateCheckpoint.capture(
        state: recorded.initial,
        learnerModelVersion: 'v1-prototype-99',
        sessionId: 'session-1',
        throughIndexInSession: 0,
        coversThrough: t0,
      );

      expect(checkpoint.isUsableUnder(params.modelVersion), isFalse);
      expect(
        () => replayJournal(
          recorded.journal,
          model: model,
          initial: recorded.initial,
          from: checkpoint,
        ),
        throwsA(isA<JournalFormatException>()),
      );
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
