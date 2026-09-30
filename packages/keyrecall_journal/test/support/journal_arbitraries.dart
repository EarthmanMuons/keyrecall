import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:keyrecall_testing/keyrecall_testing.dart';
import 'package:kiri_check/kiri_check.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

export 'package:keyrecall_testing/keyrecall_testing.dart';

/// Text JSON has to work at: quotes, escapes, a newline inside a line-based
/// file, a NUL, and characters outside ASCII and outside the BMP.
final Arbitrary<String> anyText = list(
  choiceOf([
    'a',
    'Z',
    '7',
    '-',
    ' ',
    '"',
    r'\',
    '\n',
    '\u0000',
    'é',
    '中',
    '🎹',
  ]),
  minLength: 1,
  maxLength: 12,
).map((pieces) => pieces.join());

const _idHead = 'abcXYZ019';
const _idTail = 'abcXYZ019_-';

final Arbitrary<String> anyProfileId = combine2(
  choiceOf(_idHead.split('')),
  list(choiceOf(_idTail.split('')), maxLength: 20),
).map((parts) => parts.$1 + parts.$2.join());

final Arbitrary<String> anyHash = list(
  choiceOf('0123456789abcdef'.split('')),
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
  (1, choiceOf([0.0, 1.0, 0.1, 1 / 3, 5e-324, 1 - 1e-16])),
]);

/// Any finite magnitude, signed, including negative zero.
final Arbitrary<double> anyFinite = weighted<double>([
  (6, float(min: -1e12, max: 1e12)),
  (1, choiceOf([-0.0, 1e-300, -1e300, 2.5, 9007199254740993.0])),
]);

/// A finite magnitude that is zero or more, including the smallest subnormal.
final Arbitrary<double> anyNonnegative = anyFinite.map((value) => value.abs());

/// A finite weight greater than zero.
final Arbitrary<double> anyPositive = weighted<double>([
  (6, float(min: 1e-9, max: 1e6)),
  (1, choiceOf([5e-324, 1.0, 1e300])),
]);

final Arbitrary<int> anyCount = weighted<int>([
  (6, integer(min: 0, max: 100000)),
  (1, choiceOf([0, 1, 9007199254740991])),
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
      choiceOf(shapes),
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
      choiceOf(PitchCue.values),
      choiceOf(CueModality.values),
      choiceOf(MotorCue.values),
      choiceOf(PerformanceFeedback.values),
      choiceOf(TempoSupport.values),
      choiceOf(LocatorFeedback.values),
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
        choiceOf(FactualRetrieval.values),
        boolean(),
        anyScore,
        anyScore,
        optional(anyScore),
        optional(anyScore),
        weighted<double>([(4, float(min: 0, max: 4)), (1, constant(0.0))]),
      ),
      combine2(anyScore, optional(anyScore)),
      choiceOf(PulseMaintenance.values),
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
      list(combine2(choiceOf(Competency.values), anyScore), maxLength: 8),
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
      choiceOf(AttemptTermination.values),
      boolean(),
      anyOutcome,
      anyWeights,
      anyMemoryUpdate,
      choiceOf(MeasurementUnavailableReason.values),
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
        choiceOf(EligibilityTier.values),
        anyScore,
        boolean(),
        boolean(),
        anyNonnegative,
        anyNonnegative.map((count) => -count),
        anyFinite,
        boolean(),
      ),
      combine4(
        boolean(),
        boolean(),
        choiceOf(RealizationRank.values),
        anyNonnegative.map((distance) => -distance),
      ),
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
        choiceOf(EligibilityTier.values),
        optional(choiceOf(EligibilityReason.values)),
        anyText,
        boolean(),
        anyScore,
        anyScore,
        optional(choiceOf(ChallengeFloorReason.values)),
      ),
      combine2(optional(choiceOf(ChallengeBypass.values)), anyRankKey),
    ).map((parts) {
      final (prediction, tier, reason, safety, within, low, high, floor) =
          parts.$1;
      return SchedulerDecision(
        prediction: prediction,
        eligibilityTier: tier,
        eligibilityReason: reason,
        safetyReason: safety,
        withinChallengeBand: within,
        challengeBandMin: low < high ? low : high,
        challengeBandMax: low < high ? high : low,
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
      list(combine2(anyText, anyPositive), maxLength: 6),
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

/// [text] as storage hands it back: written as UTF-8 and read again.
String stored(String text) => utf8.decode(utf8.encode(text));

final Arbitrary<TaskPortion> anyPortion = weighted<TaskPortion>([
  (2, constant(const FullTraversal())),
  (1, integer(min: 2, max: 8).map(TraversalRepetitions.new)),
]);

final Arbitrary<RecordedGap> anyGap =
    combine4(
      anyCount,
      integer(min: 1, max: 64),
      anyCount,
      optional(anyScore),
    ).map(
      (parts) => (
        fromPosition: parts.$1,
        toPosition: parts.$1 + parts.$2,
        gapMs: parts.$3,
        ratio: parts.$4 == null ? null : parts.$4! * 8,
      ),
    );

/// Everything about an acquisition attempt but its parent and its place in a
/// log.
typedef AttemptContent = ({
  DateTime? observedWallTime,
  int? executionEvidenceRevision,
  TaskPortion portion,
  PresentationRecord? presentation,
  bool started,
  AttemptTermination? termination,
  AcquisitionCompletion completion,
  (int, int, int) corrections,
  int? firstAbsentPosition,
  List<RecordedGap> gaps,
  CriterionVerdict sequence,
  CriterionVerdict continuity,
});

final Arbitrary<AttemptContent> anyAttemptContent =
    combine2(
      combine8(
        optional(anyTime),
        optional(anyCount),
        anyPortion,
        optional(anyPresentation),
        boolean(),
        optional(choiceOf(AttemptTermination.values)),
        choiceOf(AcquisitionCompletion.values),
        combine3(anyCount, anyCount, anyCount),
      ),
      combine4(
        optional(anyCount),
        list(anyGap, maxLength: 6),
        choiceOf(CriterionVerdict.values),
        choiceOf(CriterionVerdict.values),
      ),
    ).map((parts) {
      final (
        observed,
        revision,
        portion,
        presentation,
        started,
        termination,
        completion,
        corrections,
      ) = parts.$1;
      final (firstAbsent, gaps, sequence, continuity) = parts.$2;
      // A capture that may have lost events judges no criterion, and a probe
      // is earned by both criteria and only as a completion.
      final interrupted = termination == AttemptTermination.inputInterrupted;
      final judgedSequence = interrupted
          ? CriterionVerdict.unavailable
          : sequence;
      final judgedContinuity = interrupted
          ? CriterionVerdict.unavailable
          : continuity;
      final earnsProbe =
          judgedSequence == CriterionVerdict.met &&
          judgedContinuity == CriterionVerdict.met;
      return (
        observedWallTime: observed,
        executionEvidenceRevision: revision,
        portion: portion,
        presentation: presentation,
        started: started,
        termination: termination,
        completion: earnsProbe && !completion.isComplete
            ? AcquisitionCompletion.completedWithCorrections
            : completion,
        corrections: corrections,
        firstAbsentPosition: firstAbsent,
        gaps: gaps,
        sequence: judgedSequence,
        continuity: judgedContinuity,
      );
    });

AcquisitionAttemptRecord attemptOf(
  AttemptContent content, {
  required Exercise parent,
  required int journalSequence,
  required AttemptIdentity identity,
}) => AcquisitionAttemptRecord(
  journalSequence: journalSequence,
  identity: identity,
  observedWallTime: content.observedWallTime,
  executionEvidenceRevision: content.executionEvidenceRevision,
  task: AcquisitionTask(
    parent: parent,
    timing: TimingDemand.unmetered,
    advancement: TaskAdvancement.learnerDriven,
    portion: content.portion,
  ),
  presentation: content.presentation,
  started: content.started,
  termination: content.termination,
  completion: content.completion,
  repairs: content.corrections.$1,
  repeats: content.corrections.$2,
  intrusions: content.corrections.$3,
  firstAbsentPosition: content.firstAbsentPosition,
  gaps: content.gaps,
  earnedProbe:
      content.sequence == CriterionVerdict.met &&
      content.continuity == CriterionVerdict.met,
  sequence: content.sequence,
  continuity: content.continuity,
);

final Arbitrary<AttemptIdentity> anyIdentity =
    combine5(anyProfileId, anyText, anyText, anyCount, anyTime).map(
      (parts) => AttemptIdentity(
        profileId: parts.$1,
        attemptId: parts.$2,
        sessionId: parts.$3,
        indexInSession: parts.$4,
        occurredAt: parts.$5,
      ),
    );

final Arbitrary<AcquisitionAttemptRecord> anyAttempt =
    combine4(anyAttemptContent, anyExercise, anyCount, anyIdentity).map(
      (parts) => attemptOf(
        parts.$1,
        parent: parts.$2,
        journalSequence: parts.$3,
        identity: parts.$4,
      ),
    );

final Arbitrary<AcquisitionProbeServedRecord> anyProbe =
    combine4(optional(anyTime), anyExercise, anyCount, anyIdentity).map(
      (parts) => AcquisitionProbeServedRecord(
        observedWallTime: parts.$1,
        parent: parts.$2,
        journalSequence: parts.$3,
        identity: parts.$4,
      ),
    );
