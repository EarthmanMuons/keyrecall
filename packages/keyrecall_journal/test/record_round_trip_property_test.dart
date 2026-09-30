import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

/// Fixed so every run explores the same records; a failure names its seed.
const seed = 20260930;

/// Multiplied by `KEYRECALL_SEED_SCALE` for a wider search on demand.
int examples(int count) {
  final value = Platform.environment['KEYRECALL_SEED_SCALE'];
  if (value == null) return count;
  final scale = int.tryParse(value);
  if (scale == null || scale < 1) {
    throw ArgumentError.value(
      value,
      'KEYRECALL_SEED_SCALE',
      'must be a positive integer',
    );
  }
  return count * scale;
}

Arbitrary<T> weighted<T>(List<(int, Arbitrary<T>)> choices) =>
    frequency(choices).map((value) => value as T);

Arbitrary<T?> optional<T>(Arbitrary<T> present) => weighted<T?>([
  (1, constant<T?>(null)),
  (3, present.map<T?>((value) => value)),
]);

Arbitrary<T> anyOf<T>(List<T> values) => constantFrom(values);

/// Text JSON has to work at: quotes, escapes, a newline inside a line-based
/// file, a NUL, and characters outside ASCII and outside the BMP.
final Arbitrary<String> anyText = list(
  anyOf(['a', 'Z', '7', '-', ' ', '"', r'\', '\n', '\u0000', 'é', '中', '🎹']),
  minLength: 1,
  maxLength: 12,
).map((pieces) => pieces.join());

const _idHead = 'abcXYZ019';
const _idTail = 'abcXYZ019_-';

final Arbitrary<String> anyProfileId = combine2(
  anyOf(_idHead.split('')),
  list(anyOf(_idTail.split('')), maxLength: 20),
).map((parts) => parts.$1 + parts.$2.join());

final Arbitrary<String> anyHash = list(
  anyOf('0123456789abcdef'.split('')),
  minLength: 64,
  maxLength: 64,
).map((digits) => digits.join());

/// Every microsecond a stored timestamp can hold, years 1 through 9999.
final Arbitrary<DateTime> anyTime = integer(
  min: DateTime.utc(1).microsecondsSinceEpoch,
  max: DateTime.utc(9999, 12, 31, 23, 59, 59, 999, 999).microsecondsSinceEpoch,
).map((micros) => DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true));

/// A probability, with the values a shortest round-trip encoding is most
/// likely to get wrong.
final Arbitrary<double> anyScore = weighted<double>([
  (6, float(min: 0, max: 1)),
  (1, anyOf([0.0, 1.0, 0.1, 1 / 3, 5e-324, 1 - 1e-16])),
]);

/// Any finite magnitude, signed, including negative zero.
final Arbitrary<double> anyFinite = weighted<double>([
  (6, float(min: -1e12, max: 1e12)),
  (1, anyOf([-0.0, 1e-300, -1e300, 2.5, 9007199254740993.0])),
]);

final Arbitrary<int> anyCount = weighted<int>([
  (6, integer(min: 0, max: 100000)),
  (1, anyOf([0, 1, 9007199254740991])),
]);

final List<TechnicalMaterial> materials = [
  ...allScales,
  for (final arpeggio in allRootPositionArpeggios)
    for (final inversion in ArpeggioInversion.values)
      ArpeggioMaterial(arpeggio.tonic, arpeggio.quality, inversion: inversion),
];

final List<Exercise> shapes = generateCandidates(
  InstrumentProfile(),
  materials,
);

/// A presentable exercise at any tempo, sometimes carrying motor structure
/// derivation would not produce, the way a recorded one can.
final Arbitrary<Exercise> anyExercise =
    combine4(
      anyOf(shapes),
      float(min: 20, max: 320),
      list(boolean(), minLength: 64, maxLength: 64),
      boolean(),
    ).map((parts) {
      final (shape, tempo, keep, altered) = parts;
      final exercise = shape.atTempo(tempo);
      if (!altered) return exercise;
      final sites = [
        for (final (index, site) in exercise.opportunitySites.indexed)
          if (keep[index % keep.length]) site,
      ];
      final opportunities = {
        for (final site in sites) site.opportunity,
        for (final (index, opportunity) in exercise.opportunities.indexed)
          if (keep[(index * 7) % keep.length]) opportunity,
      };
      return Exercise.recorded(
        material: exercise.material,
        conditions: exercise.conditions,
        guidance: exercise.guidance,
        opportunities: opportunities,
        opportunitySites: sites.toSet(),
      );
    });

final Arbitrary<PresentationConditions> anyConditions =
    combine6(
      anyOf(PitchCue.values),
      anyOf(CueModality.values),
      anyOf(MotorCue.values),
      anyOf(PerformanceFeedback.values),
      anyOf(TempoSupport.values),
      anyOf(LocatorFeedback.values),
    ).map((parts) {
      final (pitch, modality, motor, feedback, tempo, locator) = parts;
      return PresentationConditions(
        pitchCue: pitch,
        cueModality: pitch.suppliesMaterial ? modality : null,
        motorCue: motor,
        performanceFeedback: feedback,
        tempoSupport: tempo,
        locatorFeedback: feedback == PerformanceFeedback.none
            ? LocatorFeedback.none
            : locator,
      );
    });

final Arbitrary<PresentationDelivery> anyDelivery =
    combine6(
      integer(min: 0, max: 8),
      integer(min: 0, max: 32),
      integer(min: 0, max: 8),
      integer(min: 0, max: 32),
      optional(anyText),
      integer(min: 0, max: 32),
    ).map((parts) {
      final (countIn, continuing, gotCountIn, gotContinuing, reason, shown) =
          parts;
      return PresentationDelivery(
        tempo: TempoDelivery(
          countInBeats: countIn,
          continuingBeats: continuing,
          deliveredCountInBeats: gotCountIn > countIn ? countIn : gotCountIn,
          deliveredContinuingBeats: gotContinuing > continuing
              ? continuing
              : gotContinuing,
          failureReason: reason,
        ),
        shownContinuingBeats: shown,
      );
    });

final Arbitrary<PresentationRecord> anyPresentation =
    combine3(anyText, anyConditions, anyDelivery).map(
      (parts) => PresentationRecord(
        policyVersion: parts.$1,
        conditions: parts.$2,
        delivery: parts.$3,
      ),
    );

final Arbitrary<Outcome> anyOutcome =
    combine3(
      combine8(
        boolean(),
        anyOf(FactualRetrieval.values),
        boolean(),
        anyScore,
        anyScore,
        optional(anyScore),
        optional(anyScore),
        weighted<double>([(4, float(min: 0, max: 4)), (1, constant(0.0))]),
      ),
      combine2(anyScore, optional(anyScore)),
      anyOf(PulseMaintenance.values),
    ).map((parts) {
      final (
        started,
        retrieval,
        completed,
        material,
        pitch,
        continuity,
        temporal,
        tempo,
      ) = parts.$1;
      return Outcome(
        started: started,
        retrieval: retrieval,
        completed: completed,
        materialRetrieval: material,
        pitchIntegrity: pitch,
        continuity: continuity,
        temporalStability: temporal,
        achievedTempoRatio: tempo,
        topologyAccuracy: parts.$2.$1,
        coordination: parts.$2.$2,
        pulseMaintenance: parts.$3,
      );
    });

/// [outcome] claiming [pulse], everything else held fixed.
Outcome withPulse(Outcome outcome, PulseMaintenance pulse) => Outcome(
  started: outcome.started,
  retrieval: outcome.retrieval,
  completed: outcome.completed,
  materialRetrieval: outcome.materialRetrieval,
  pitchIntegrity: outcome.pitchIntegrity,
  continuity: outcome.continuity,
  temporalStability: outcome.temporalStability,
  achievedTempoRatio: outcome.achievedTempoRatio,
  topologyAccuracy: outcome.topologyAccuracy,
  coordination: outcome.coordination,
  pulseMaintenance: pulse,
);

final Arbitrary<EvidenceWeights> anyWeights =
    combine3(
      list(combine2(anyOf(Competency.values), anyScore), maxLength: 8),
      anyScore,
      anyScore,
    ).map(
      (parts) => EvidenceWeights(
        competencies: {for (final (key, value) in parts.$1) key: value},
        materialExecution: parts.$2,
        materialMemory: parts.$3,
      ),
    );

final Arbitrary<MemoryUpdateDiagnostics> anyMemoryUpdate =
    combine2(anyFinite, anyFinite).map(
      (parts) => MemoryUpdateDiagnostics(
        consolidationDeltaFromRetrievalInference: parts.$1,
        consolidationDeltaFromCausalFormation: parts.$2,
      ),
    );

final Arbitrary<AttemptClosure> anyClosure =
    combine6(
      anyOf(AttemptTermination.values),
      boolean(),
      anyOutcome,
      anyWeights,
      anyMemoryUpdate,
      anyOf(MeasurementUnavailableReason.values),
    ).map((parts) {
      final (termination, measured, outcome, weights, update, reason) = parts;
      return measured
          ? AttemptClosure.measured(
              termination: termination,
              outcome: outcome,
              weights: weights,
              memoryUpdate: update,
            )
          : AttemptClosure.unmeasured(termination: termination, reason: reason);
    });

final Arbitrary<Prediction> anyPrediction =
    combine5(anyScore, anyScore, anyScore, anyScore, anyScore).map(
      (parts) => Prediction(
        independentRetrievalP: parts.$1,
        materialAvailableP: parts.$2,
        executionP: parts.$3,
        coordinationP: parts.$4,
        topologyP: parts.$5,
      ),
    );

final Arbitrary<RankKey> anyRankKey =
    combine2(
      combine8(
        anyOf(EligibilityTier.values),
        anyFinite,
        boolean(),
        boolean(),
        anyFinite,
        anyFinite,
        anyFinite,
        boolean(),
      ),
      combine4(boolean(), boolean(), anyOf(RealizationRank.values), anyFinite),
    ).map((parts) {
      final (
        tier,
        retention,
        transition,
        contrary,
        information,
        diversity,
        goals,
        shaped,
      ) = parts.$1;
      final (advances, shapedGoal, realization, fit) = parts.$2;
      return RankKey(
        tier: tier,
        retention: retention,
        coordinationTransition: transition,
        contraryCoordination: contrary,
        information: information,
        diversity: diversity,
        goals: goals,
        targetShaped: shaped,
        advancesFrontier: advances,
        targetShapedGoal: shapedGoal,
        realization: realization,
        realizationFit: fit,
      );
    });

final Arbitrary<SchedulerDecision> anyDecision =
    combine2(
      combine8(
        anyPrediction,
        anyOf(EligibilityTier.values),
        optional(anyOf(EligibilityReason.values)),
        anyText,
        boolean(),
        anyScore,
        anyScore,
        optional(anyOf(ChallengeFloorReason.values)),
      ),
      combine2(optional(anyOf(ChallengeBypass.values)), anyRankKey),
    ).map((parts) {
      final (prediction, tier, reason, safety, within, low, high, floor) =
          parts.$1;
      return SchedulerDecision(
        prediction: prediction,
        eligibilityTier: tier,
        eligibilityReason: reason,
        safetyReason: safety,
        withinChallengeBand: within,
        challengeBandMin: low,
        challengeBandMax: high,
        challengeFloorReason: floor,
        challengeBypass: parts.$2.$1,
        rankKey: parts.$2.$2,
      );
    });

final Arbitrary<DecisionScope> anyScope =
    combine5(
      anyText,
      anyText,
      anyText,
      optional(list(anyText, maxLength: 6)),
      list(combine2(anyText, anyFinite), maxLength: 6),
    ).map(
      (parts) => DecisionScope(
        goalId: parts.$1,
        curriculumId: parts.$2,
        curriculumVersion: parts.$3,
        exclusiveRequirementIds: parts.$4?.toSet(),
        emphasisByRequirementId: {
          for (final (key, value) in parts.$5) key: value,
        },
      ),
    );

final Arbitrary<AttemptTiming> anyTiming =
    combine4(anyCount, optional(anyCount), optional(anyCount), boolean()).map(
      (parts) => AttemptTiming(
        openMs: parts.$1,
        firstNoteMs: parts.$2,
        playingMs: parts.$3,
        leftForeground: parts.$4,
      ),
    );

final Arbitrary<InputProvenance> anyInput =
    combine4(
      anyText,
      optional(anyText),
      optional(anyCount),
      optional(anyCount),
    ).map(
      (parts) => InputProvenance(
        source: parts.$1,
        transport: parts.$2,
        clockGranularity: parts.$3,
        clockModulus: parts.$4,
      ),
    );

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

/// [text] as storage hands it back: written as UTF-8 and read again.
String stored(String text) => utf8.decode(utf8.encode(text));

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

/// [body], with any thrown [Error] reported as a failure.
///
/// kiri_check shrinks only what is thrown as an [Exception], so a crash would
/// otherwise surface unshrunk and without its seed.
void Function(T) failingOnErrors<T>(void Function(T) body) => (value) {
  try {
    body(value);
  } on Error catch (error, stackTrace) {
    fail('$error\n$stackTrace');
  }
};

/// Every enum value the generated records reached.
final Set<Enum> reached = {};

void noteReached(AttemptRecord record) {
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
    forAll(
      anyRecord,
      seed: seed,
      maxExamples: examples(500),
      failingOnErrors<AttemptRecord>((record) {
        noteReached(record);
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
      seed: seed,
      maxExamples: examples(300),
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
      seed: seed,
      maxExamples: examples(100),
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

  test('the generated records reach every variant', () {
    for (final values in <List<Enum>>[
      AttemptTermination.values,
      MeasurementUnavailableReason.values,
      FactualRetrieval.values,
      PulseMaintenance.values,
      Competency.values,
      PitchCue.values,
      CueModality.values,
      MotorCue.values,
      PerformanceFeedback.values,
      TempoSupport.values,
      LocatorFeedback.values,
      EligibilityTier.values,
      EligibilityReason.values,
      ChallengeFloorReason.values,
      ChallengeBypass.values,
      RealizationRank.values,
    ]) {
      expect(
        reached,
        containsAll(values),
        reason: '${values.first.runtimeType}',
      );
    }
  });
}
