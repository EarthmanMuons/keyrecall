import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/journal_arbitraries.dart';

/// Everything about an attempt but its place in a journal.
typedef Content = ({
  DateTime? observedWallTime,
  ModelProvenance provenance,
  Exercise exercise,
  PresentationRecord? presentation,
  SchedulerDecision? decision,
  DecisionScope? scope,
  AttemptTiming? timing,
  InputProvenance? input,
  AttemptClosure closure,
  String? stateBeforeHash,
  String? stateAfterHash,
});

final Arbitrary<Content> anyContent =
    combine2(
      combine8(
        optional(anyTime),
        combine3(anyText, anyText, optional(anyText)),
        anyExercise,
        optional(anyPresentation),
        optional(anyDecision),
        optional(anyScope),
        optional(anyTiming),
        optional(anyInput),
      ),
      combine3(anyClosure, optional(anyHash), optional(anyHash)),
    ).map((parts) {
      final (
        observed,
        provenance,
        exercise,
        presentation,
        decision,
        scope,
        timing,
        input,
      ) = parts.$1;
      final (closure, before, after) = parts.$2;
      return (
        observedWallTime: observed,
        provenance: ModelProvenance(
          learnerModelVersion: provenance.$1,
          schedulerModelVersion: provenance.$2,
          appBuildVersion: provenance.$3,
        ),
        exercise: exercise,
        presentation: presentation,
        decision: decision,
        scope: scope,
        timing: timing,
        input: input,
        closure: agreeingWith(closure, presentation),
        stateBeforeHash: before,
        stateAfterHash: after,
      );
    });

/// [closure], with its outcome claiming the pulse [presentation] delivered.
AttemptClosure agreeingWith(
  AttemptClosure closure,
  PresentationRecord? presentation,
) => switch (closure.measurement) {
  Measured(:final outcome, :final weights, :final memoryUpdate)
      when presentation != null =>
    AttemptClosure.measured(
      termination: closure.termination,
      outcome: withPulse(
        outcome,
        PulseMaintenance.under(presentation.delivery),
      ),
      weights: weights,
      memoryUpdate: memoryUpdate,
    ),
  _ => closure,
};

AttemptRecord recordOf(
  Content content, {
  required int journalSequence,
  required AttemptIdentity identity,
}) => AttemptRecord(
  journalSequence: journalSequence,
  identity: identity,
  observedWallTime: content.observedWallTime,
  provenance: content.provenance,
  exercise: content.exercise,
  presentation: content.presentation,
  decision: content.decision,
  scope: content.scope,
  timing: content.timing,
  input: content.input,
  closure: content.closure,
  stateBeforeHash: content.stateBeforeHash,
  stateAfterHash: content.stateAfterHash,
);

final Arbitrary<AttemptRecord> anyRecord =
    combine2(
      anyContent,
      combine5(anyProfileId, anyText, anyText, anyCount, anyTime),
    ).map((parts) {
      final (profileId, attemptId, sessionId, index, occurredAt) = parts.$2;
      return recordOf(
        parts.$1,
        journalSequence: index,
        identity: AttemptIdentity(
          profileId: profileId,
          attemptId: attemptId,
          sessionId: sessionId,
          indexInSession: index,
          occurredAt: occurredAt,
        ),
      );
    });

/// What a record says, compared with the domain's own equality rather than
/// through the codec under test.
List<Object?> meaningOf(AttemptRecord record) => [
  record.schemaVersion,
  record.journalSequence,
  record.identity,
  record.observedWallTime,
  record.provenance,
  record.exercise,
  record.exercise.guidance,
  record.exercise.opportunities,
  record.exercise.opportunitySites,
  record.presentation,
  switch (record.decision) {
    null => null,
    final decision => [
      decision.prediction,
      decision.eligibilityTier,
      decision.eligibilityReason,
      decision.safetyReason,
      decision.withinChallengeBand,
      decision.challengeBandMin,
      decision.challengeBandMax,
      decision.challengeFloorReason,
      decision.challengeBypass,
      decision.rankKey,
    ],
  },
  record.scope,
  record.timing,
  record.input,
  record.closure,
  record.stateBeforeHash,
  record.stateAfterHash,
];

AttemptRecord reread(AttemptRecord record) => AttemptRecord.fromJson(
  jsonDecode(stored(canonicalJson(record.toJson()))) as Map<String, Object?>,
);

/// [record] rebuilt with every set and map filled in the opposite order.
AttemptRecord builtBackward(AttemptRecord record) {
  final exercise = record.exercise;
  final scope = record.scope;
  final closure = record.closure;
  return AttemptRecord(
    journalSequence: record.journalSequence,
    identity: record.identity,
    observedWallTime: record.observedWallTime,
    provenance: record.provenance,
    exercise: Exercise.recorded(
      material: exercise.material,
      conditions: exercise.conditions,
      pattern: exercise.pattern,
      guidance: exercise.guidance,
      opportunities: exercise.opportunities.toList().reversed.toSet(),
      opportunitySites: exercise.opportunitySites.toList().reversed.toSet(),
    ),
    presentation: record.presentation,
    decision: record.decision,
    scope: scope == null
        ? null
        : DecisionScope(
            goalId: scope.goalId,
            curriculumId: scope.curriculumId,
            curriculumVersion: scope.curriculumVersion,
            exclusiveRequirementIds: scope.exclusiveRequirementIds
                ?.toList()
                .reversed
                .toSet(),
            emphasisByRequirementId: Map.fromEntries(
              scope.emphasisByRequirementId.entries.toList().reversed,
            ),
          ),
    timing: record.timing,
    input: record.input,
    closure: switch (closure.measurement) {
      Measured(:final outcome, :final weights, :final memoryUpdate) =>
        AttemptClosure.measured(
          termination: closure.termination,
          outcome: outcome,
          weights: EvidenceWeights(
            competencies: Map.fromEntries(
              weights.competencies.entries.toList().reversed,
            ),
            materialExecution: weights.materialExecution,
            materialMemory: weights.materialMemory,
          ),
          memoryUpdate: memoryUpdate,
        ),
      MeasurementUnavailable() => closure,
    },
    stateBeforeHash: record.stateBeforeHash,
    stateAfterHash: record.stateAfterHash,
  );
}

/// Arranges [contents] into a journal that could have been appended: one
/// profile, contiguous sequence, time that never runs backward, and indices
/// that advance within each session.
AttemptJournal journalOf(
  String profileId,
  DateTime createdAt,
  List<(Content, int, int, int)> contents,
) {
  final journal = AttemptJournal(
    JournalHeader(profileId: profileId, createdAt: createdAt),
  );
  var occurredAt = createdAt;
  final nextIndex = <String, int>{};
  for (final (sequence, (content, session, gapMicros, skip))
      in contents.indexed) {
    final sessionId = 'session-$session';
    final index = (nextIndex[sessionId] ?? 0) + skip;
    nextIndex[sessionId] = index + 1;
    final later = occurredAt.add(Duration(microseconds: gapMicros));
    occurredAt = later.year > 9999 ? occurredAt : later;
    journal.append(
      recordOf(
        content,
        journalSequence: sequence,
        identity: AttemptIdentity(
          profileId: profileId,
          attemptId: 'attempt-$sequence',
          sessionId: sessionId,
          indexInSession: index,
          occurredAt: occurredAt,
        ),
      ),
    );
  }
  return journal;
}

/// Every variant a generated record has to be able to reach.
Reached<Enum> everyVariant() => Reached({
  ...AttemptTermination.values,
  ...MeasurementUnavailableReason.values,
  ...FactualRetrieval.values,
  ...PulseMaintenance.values,
  ...Competency.values,
  ...PitchCue.values,
  ...CueModality.values,
  ...MotorCue.values,
  ...PerformanceFeedback.values,
  ...TempoSupport.values,
  ...LocatorFeedback.values,
  ...EligibilityTier.values,
  ...EligibilityReason.values,
  ...ChallengeFloorReason.values,
  ...ChallengeBypass.values,
  ...RealizationRank.values,
});

void noteReached(Reached<Enum> reached, AttemptRecord record) {
  reached.add(record.closure.termination);
  if (record.presentation case final presentation?) {
    final conditions = presentation.conditions;
    reached.addAll([
      conditions.pitchCue,
      ?conditions.cueModality,
      conditions.motorCue,
      conditions.performanceFeedback,
      conditions.tempoSupport,
      conditions.locatorFeedback,
    ]);
  }
  if (record.decision case final decision?) {
    reached.addAll([
      decision.eligibilityTier,
      ?decision.eligibilityReason,
      ?decision.challengeFloorReason,
      ?decision.challengeBypass,
      decision.rankKey.tier,
      decision.rankKey.realization,
    ]);
  }
  switch (record.closure.measurement) {
    case Measured(:final outcome, :final weights):
      reached.addAll([
        outcome.retrieval,
        outcome.pulseMaintenance,
        ...weights.competencies.keys,
      ]);
    case MeasurementUnavailable(:final reason):
      reached.add(reason);
  }
}

void main() {
  property('a record reads back as what was written', () {
    final reached = everyVariant();
    forAll(
      anyRecord,
      seed: propertySeed,
      maxExamples: propertyBudget(500),
      onFalsify: reached.falsified,
      tearDownAll: reached.check,
      failingOnErrors<AttemptRecord>((record) {
        noteReached(reached, record);
        final back = reread(record);

        expect(meaningOf(back), meaningOf(record));
        expect(
          canonicalJson(back.toJson()),
          canonicalJson(record.toJson()),
          reason: 'reading back and writing again changes nothing',
        );
        expect(contentHash(back.toJson()), contentHash(record.toJson()));
      }),
    );
  });

  property('equal records write the same bytes however they were built', () {
    forAll(
      anyRecord,
      seed: propertySeed,
      maxExamples: propertyBudget(300),
      failingOnErrors<AttemptRecord>((record) {
        expect(
          canonicalJson(builtBackward(record).toJson()),
          canonicalJson(record.toJson()),
        );
      }),
    );
  });

  property('a journal reads back whole, in order, with its history', () {
    forAll(
      combine3(
        anyProfileId,
        anyTime,
        list(
          combine4(
            anyContent,
            integer(min: 0, max: 3),
            weighted<int>([
              (4, integer(min: 0, max: 86400000000)),
              (1, constant(0)),
            ]),
            weighted<int>([(4, constant(0)), (1, integer(min: 1, max: 5))]),
          ),
          maxLength: 12,
        ),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(100),
      failingOnErrors<(String, DateTime, List<(Content, int, int, int)>)>((
        parts,
      ) {
        final journal = journalOf(parts.$1, parts.$2, parts.$3);
        final back = AttemptJournal.fromJsonLines(
          stored(journal.toJsonLines()),
        );

        expect(back.header.profileId, journal.header.profileId);
        expect(back.header.createdAt, journal.header.createdAt);
        expect(back.records.map(meaningOf), journal.records.map(meaningOf));
        expect(back.toJsonLines(), journal.toJsonLines());
        const genesis = 'genesis';
        for (var i = 0; i < journal.length; i++) {
          expect(
            back.historyHashThrough(i, genesisStateHash: genesis),
            journal.historyHashThrough(i, genesisStateHash: genesis),
            reason: 'history through sequence $i',
          );
          expect(
            journal.append(back.records[i]),
            isFalse,
            reason: 'a record read back is the one already appended',
          );
        }
      }),
    );
  });
}
