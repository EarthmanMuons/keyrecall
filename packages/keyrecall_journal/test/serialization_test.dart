import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

void main() {
  group('attempt records round-trip', () {
    test('every field survives, for every recorded attempt', () {
      final recorded = recordSession(attempts: 8);
      for (final record in recorded.journal.records) {
        final reread = AttemptRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
        );

        expect(reread.identity, record.identity);
        expect(reread.provenance, record.provenance);
        expect(reread.exercise, record.exercise);
        expect(reread.outcome, record.outcome);
        expect(reread.weights, record.weights);
        expect(reread.stateBeforeHash, record.stateBeforeHash);
        expect(reread.stateAfterHash, record.stateAfterHash);
        expect(
          reread.memoryUpdate.consolidationDeltaFromRetrievalInference,
          record.memoryUpdate.consolidationDeltaFromRetrievalInference,
        );
        expect(reread.decision?.rankKey, record.decision?.rankKey);
        expect(reread.decision?.prediction, record.decision?.prediction);
        expect(
          reread.decision?.challengeBypass,
          record.decision?.challengeBypass,
        );
      }
    });

    test('an untested retrieval stays null, never false', () {
      // The distinction the whole evidence model rests on. Serialized as null
      // and read back as notTested, never collapsed into a failure.
      final exercise = exerciseFor(
        v1ScaleCatalog.first,
        guidance: GuidanceContext.continuouslyCued,
      );
      final outcome = outcomeOf(retrieval: FactualRetrieval.notTested);
      final record = AttemptRecord(
        identity: AttemptIdentity(
          profileId: testProfile.id,
          attemptId: 'a',
          sessionId: 's',
          indexInSession: 0,
          occurredAt: t0,
        ),
        provenance: provenance,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      );

      final json = record.toJson();
      final outcomeJson = json['outcome']! as Map<String, Object?>;
      expect(outcomeJson.containsKey('retrieval_succeeded'), isTrue);
      expect(outcomeJson['retrieval_succeeded'], isNull);
      expect(jsonEncode(json), contains('"retrieval_succeeded":null'));

      final reread = AttemptRecord.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, Object?>,
      );
      expect(reread.outcome.retrieval, FactualRetrieval.notTested);
      expect(reread.outcome.retrieval.isTested, isFalse);
    });

    test('all three retrieval values survive distinctly', () {
      for (final retrieval in FactualRetrieval.values) {
        final exercise = exerciseFor(v1ScaleCatalog.first);
        final outcome = outcomeOf(retrieval: retrieval);
        final record = AttemptRecord(
          identity: AttemptIdentity(
            profileId: testProfile.id,
            attemptId: 'a',
            sessionId: 's',
            indexInSession: 0,
            occurredAt: t0,
          ),
          provenance: provenance,
          exercise: exercise,
          outcome: outcome,
          weights: evidenceWeightsFor(exercise, outcome),
          memoryUpdate: const MemoryUpdateDiagnostics(),
        );
        final reread = AttemptRecord.fromJson(
          jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
        );
        expect(reread.outcome.retrieval, retrieval);
      }
    });

    test('timestamps keep sub-millisecond precision', () {
      final precise = DateTime.utc(2026, 3, 4, 5, 6, 7, 8, 9);
      final identity = AttemptIdentity(
        profileId: testProfile.id,
        attemptId: 'a',
        sessionId: 's',
        indexInSession: 0,
        occurredAt: precise,
      );
      final exercise = exerciseFor(v1ScaleCatalog.first);
      final outcome = outcomeOf();
      final record = AttemptRecord(
        identity: identity,
        provenance: provenance,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      );

      final reread = AttemptRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())) as Map<String, Object?>,
      );
      expect(reread.identity.occurredAt, precise);
      expect(reread.identity.occurredAt.microsecond, 9);
      expect(reread.identity.occurredAt.isUtc, isTrue);
    });
  });

  group('reading fails loudly', () {
    Map<String, Object?> validRecord() {
      final exercise = exerciseFor(v1ScaleCatalog.first);
      final outcome = outcomeOf();
      return AttemptRecord(
        identity: AttemptIdentity(
          profileId: testProfile.id,
          attemptId: 'a',
          sessionId: 's',
          indexInSession: 0,
          occurredAt: t0,
        ),
        provenance: provenance,
        exercise: exercise,
        outcome: outcome,
        weights: evidenceWeightsFor(exercise, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      ).toJson();
    }

    test('on an unknown schema version', () {
      final json = validRecord()..['schema_version'] = attemptSchemaVersion + 1;
      expect(
        () => AttemptRecord.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('on a material id that disagrees with its tonic and form', () {
      final json = validRecord();
      (json['exercise']! as Map<String, Object?>)['material_id'] = 'Z_MAJOR';
      expect(
        () => AttemptRecord.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('on a guidance level that is not one of the three rungs', () {
      final json = validRecord();
      (json['exercise']! as Map<String, Object?>)['guidance'] = 'half_cued';
      expect(
        () => AttemptRecord.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('on a retrieval value that is neither bool nor null', () {
      final json = validRecord();
      (json['outcome']! as Map<String, Object?>)['retrieval_succeeded'] =
          'maybe';
      expect(
        () => AttemptRecord.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('on a missing model version', () {
      final json = validRecord();
      (json['provenance']! as Map<String, Object?>).remove(
        'learner_model_version',
      );
      expect(
        () => AttemptRecord.fromJson(json),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('on an out-of-range observation', () {
      final json = validRecord();
      (json['outcome']! as Map<String, Object?>)['continuity'] = 1.5;
      expect(() => AttemptRecord.fromJson(json), throwsArgumentError);
    });
  });

  group('canonical encoding', () {
    test('does not depend on the order fields were built in', () {
      expect(canonicalJson({'b': 1, 'a': 2}), canonicalJson({'a': 2, 'b': 1}));
      expect(
        contentHash({
          'outer': {'z': 1, 'a': 2},
        }),
        contentHash({
          'outer': {'a': 2, 'z': 1},
        }),
      );
    });

    test('refuses a value JSON cannot represent', () {
      expect(
        () => canonicalJson({'x': double.nan}),
        throwsA(isA<JournalFormatException>()),
      );
      expect(
        () => canonicalJson({'x': double.infinity}),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('checkpoints', () {
    test('round-trip and verify against their own hash', () {
      final recorded = recordSession(attempts: 5);
      final replayed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      final checkpoint = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: replayed.state,
        learnerModelVersion: params.modelVersion,
        sessionId: 'session-1',
        throughIndexInSession: 4,
        coversThrough: recorded.journal.records.last.identity.occurredAt,
      );

      final reread = LearnerStateCheckpoint.fromJson(
        jsonDecode(jsonEncode(checkpoint.toJson())) as Map<String, Object?>,
        params: params,
      );

      expect(reread.contentHash, checkpoint.contentHash);
      expect(learnerStateHash(reread.state), checkpoint.contentHash);
      expect(reread.throughIndexInSession, 4);
      expect(reread.isUsableUnder(params.modelVersion), isTrue);
    });

    test('reject content that does not match the claimed hash', () {
      final recorded = recordSession(attempts: 3);
      final checkpoint = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: recorded.initial,
        learnerModelVersion: params.modelVersion,
        sessionId: 'session-1',
        throughIndexInSession: 0,
        coversThrough: t0,
      );
      final json = checkpoint.toJson();
      final competencies =
          (json['state']! as Map<String, Object?>)['competencies']!
              as Map<String, Object?>;
      (competencies['RH_SCALE_EXECUTION']! as Map<String, Object?>)['mean'] =
          99.0;

      expect(
        () => LearnerStateCheckpoint.fromJson(json, params: params),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('reject a state that breaks the durability envelope', () {
      final recorded = recordSession(attempts: 3);
      final replayed = replayJournal(
        recorded.journal,
        model: model,
        initial: recorded.initial,
      );
      final state = replayed.state;
      final materialId = state.materialMemory.keys.first;
      // Current durability above consolidation is impossible by construction,
      // so meeting it in persisted data means the data is wrong.
      state.materialMemory[materialId]!.logCurrentHalfLife =
          state.materialMemory[materialId]!.logConsolidatedHalfLife + 1.0;

      final checkpoint = LearnerStateCheckpoint.capture(
        profileId: testProfile.id,
        state: state,
        learnerModelVersion: params.modelVersion,
        sessionId: 'session-1',
        throughIndexInSession: 2,
        coversThrough: t0,
      );

      expect(
        () => LearnerStateCheckpoint.fromJson(
          checkpoint.toJson(),
          params: params,
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('reject a factual success with no activation anchor', () {
      final state = model.placementState(PlacementTier.beginner, at: t0);
      final memory = state.materialMemoryFor('C_MAJOR', params)
        ..factualLastRetrievalAt = t0;

      expect(memory.memoryAnchorAt, isNull);
      expect(
        () => validateMaterialMemory(memory, params: params),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });
}
