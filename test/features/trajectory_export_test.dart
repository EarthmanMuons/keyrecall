import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/trajectory_export.dart';

/// The tables a device session is read from afterwards.
void main() {
  CoordinationSample sampleWith(List<int> asynchronies) => CoordinationSample(
    profileId: 'learner',
    attemptId: 'attempt',
    observedAt: DateTime.utc(2026, 9, 6),
    materialId: 'F_MAJOR',
    familyId: 'SCALE',
    hands: 'TOGETHER',
    handMotion: 'PARALLEL',
    direction: 'UP_DOWN',
    octaves: 1,
    tempoBpm: 60,
    achievedTempoRatio: 1.19,
    guidanceIndependence: 2,
    coordinationScore: 0.93,
    synchronizedAsynchronyMs: 30,
    reportedAsFault: true,
    moments: [
      for (final (index, ms) in asynchronies.indexed)
        (position: index, asynchronyMs: ms),
    ],
  );

  final learner = Profile(
    id: 'learner',
    displayName: 'Me',
    createdAt: DateTime.utc(2026),
    placement: PlacementTier.beginner,
  );

  group('the latest session across both journals', () {
    final parent = Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ExerciseDirection.up,
      tempoBpm: 60,
      guidance: GuidanceContext.continuouslyCued,
    );
    late AttemptJournal ordinary;
    late AcquisitionJournal acquisition;

    setUp(() {
      ordinary = AttemptJournal(
        JournalHeader(profileId: learner.id, createdAt: learner.createdAt),
      );
      acquisition = AcquisitionJournal(
        AcquisitionJournalHeader(
          profileId: learner.id,
          createdAt: learner.createdAt,
        ),
      );
    });

    AttemptIdentity identity(String session, int minute, String id) =>
        AttemptIdentity(
          profileId: learner.id,
          attemptId: id,
          sessionId: session,
          indexInSession: 0,
          occurredAt: learner.createdAt.add(Duration(minutes: minute)),
        );

    void supported(String session, int minute) {
      acquisition.append(
        AcquisitionAttemptRecord(
          journalSequence: acquisition.length,
          identity: identity(session, minute, 'supported-$minute'),
          task: AcquisitionTask.unmeteredTraversal(parent),
          started: false,
          termination: AttemptTermination.learnerStopped,
          completion: AcquisitionCompletion.notCompleted,
          repairs: 0,
          repeats: 0,
          intrusions: 0,
          earnedProbe: false,
          sequence: CriterionVerdict.notMet,
          continuity: CriterionVerdict.unavailable,
          gaps: const [],
        ),
      );
    }

    void measured(String session, int minute) {
      final outcome = readPerformance(
        exercise: parent,
        transcript: PerformanceTranscript.empty,
      ).outcome;
      ordinary.append(
        AttemptRecord(
          journalSequence: ordinary.length,
          identity: identity(session, minute, 'ordinary-$minute'),
          provenance: const ModelProvenance(
            learnerModelVersion: 'learner',
            schedulerModelVersion: 'scheduler',
          ),
          exercise: parent,
          closure: AttemptClosure.measured(
            termination: AttemptTermination.learnerStopped,
            outcome: outcome,
            weights: evidenceWeightsFor(parent, outcome),
            memoryUpdate: const MemoryUpdateDiagnostics(),
          ),
        ),
      );
    }

    SessionExport export() =>
        sessionExportOf(learner, ordinary, acquisition: acquisition);

    test('a newer supported-only session replaces the ordinary one', () {
      measured('old', 1);
      supported('new', 2);
      final result = export();
      expect(result.sessionId, 'new');
      expect(
        result.startedAt,
        learner.createdAt.add(const Duration(minutes: 2)),
      );
      expect(result.attempts, isEmpty);
      expect(result.acquisition.single.identity.sessionId, 'new');
    });

    test('supported work can be exported without ordinary history', () {
      supported('only', 2);
      final result = export();
      expect(result.sessionId, 'only');
      expect(
        result.startedAt,
        learner.createdAt.add(const Duration(minutes: 2)),
      );
      expect(result.acquisition, hasLength(1));
    });

    test('a mixed session starts with its earlier supported work', () {
      supported('mixed', 1);
      measured('mixed', 2);
      final result = export();
      expect(result.sessionId, 'mixed');
      expect(
        result.startedAt,
        learner.createdAt.add(const Duration(minutes: 1)),
      );
      expect(result.attempts, hasLength(1));
      expect(result.acquisition, hasLength(1));
    });

    test('a newer ordinary session excludes older supported work', () {
      supported('old', 1);
      measured('new', 2);
      final result = export();
      expect(result.sessionId, 'new');
      expect(
        result.startedAt,
        learner.createdAt.add(const Duration(minutes: 2)),
      );
      expect(result.attempts, hasLength(1));
      expect(result.acquisition, isEmpty);
    });

    test('empty history keeps the empty export', () {
      final result = export();
      expect(result.sessionId, isEmpty);
      expect(result.startedAt, learner.createdAt);
      expect(result.attempts, isEmpty);
      expect(result.acquisition, isEmpty);
    });
  });

  group('why a tempo was the tempo asked for', () {
    const model = LearnerModel();
    final material = TechnicalMaterial('C', ScaleForm.major);

    test('reports the frontier, the pace, and where hands together enters', () {
      final state = model.placementState(
        PlacementTier.beginner,
        at: DateTime.utc(2026),
      );
      for (final hands in [HandConfiguration.right, HandConfiguration.left]) {
        state.materialExecutionFor(
            (material.materialId, hands, HandMotion.parallel),
            DateTime.utc(2026),
            v1LearnerParams,
            familyId: material.familyId,
          )
          ..demonstrate(octaves: 1, tempoBpm: 60)
          ..readyForHandsTogether(octaves: 1, tempoBpm: 60)
          ..paced(126);
      }

      final pace = TempoProvenance.of(
        state,
        Exercise.linear(
          material: material,
          hands: HandConfiguration.right,
          octaves: 1,
        ),
      );

      expect(pace.frontierBpm, 60, reason: 'what has been asked for and met');
      expect(
        pace.pacedBpm,
        greaterThan(pace.frontierBpm),
        reason: 'the device shape: playing far faster than the last request',
      );
      expect(
        pace.handsTogetherEntryBpm,
        lessThan(60),
        reason: 'a rung below the slower hand',
      );
    });

    test('the table says which numbers a request was chosen against', () {
      final table = trajectoryOf(
        learner,
        AttemptJournal(
          JournalHeader(profileId: learner.id, createdAt: learner.createdAt),
        ),
      );

      expect(table, contains('front'));
      expect(table, contains('paced'));
      expect(table, contains('htentry'));
    });
  });

  group('an attempt\'s context', () {
    AttemptRecord recordWith({
      DecisionScope? scope,
      AttemptTiming? timing,
      InputProvenance? input,
      Outcome? outcome,
    }) {
      final exercise = Exercise.linear(
        material: TechnicalMaterial('C', ScaleForm.major),
        hands: HandConfiguration.right,
      );
      return AttemptRecord(
        journalSequence: 0,
        identity: AttemptIdentity(
          profileId: learner.id,
          attemptId: 'a',
          sessionId: 's',
          indexInSession: 0,
          occurredAt: learner.createdAt,
        ),
        provenance: const ModelProvenance(
          learnerModelVersion: 'learner',
          schedulerModelVersion: 'scheduler',
        ),
        exercise: exercise,
        scope: scope,
        timing: timing,
        input: input,
        closure: outcome == null
            ? AttemptClosure.unmeasured(
                termination: AttemptTermination.learnerStopped,
                reason: MeasurementUnavailableReason.nothingPlayed,
              )
            : AttemptClosure.measured(
                termination: AttemptTermination.learnerStopped,
                outcome: outcome,
                weights: evidenceWeightsFor(exercise, outcome),
                memoryUpdate: const MemoryUpdateDiagnostics(),
              ),
      );
    }

    test('reads flow and pulse apart, marking a supplied pulse', () {
      Outcome played(PulseMaintenance pulse) => Outcome(
        started: true,
        retrieval: FactualRetrieval.succeeded,
        completed: true,
        materialRetrieval: 1,
        pitchIntegrity: 1,
        continuity: 0.9,
        temporalStability: 0.4,
        achievedTempoRatio: 1,
        topologyAccuracy: 1,
        pulseMaintenance: pulse,
      );

      expect(
        trajectoryRow(0, recordWith(outcome: played(PulseMaintenance.tested))),
        contains('flow=0.90 pulse=0.40 '),
      );
      expect(
        trajectoryRow(
          0,
          recordWith(outcome: played(PulseMaintenance.notTested)),
        ),
        contains('flow=0.90 pulse=0.40(metronome) '),
      );
    });

    test('names the goal, the timing, and the input', () {
      final context = contextOf(
        recordWith(
          scope: DecisionScope(
            goalId: 'FOUNDATIONS',
            curriculumId: 'FOUNDATIONS',
            curriculumVersion: '1',
          ),
          timing: const AttemptTiming(
            openMs: 9250,
            firstNoteMs: 1500,
            playingMs: 6420,
            leftForeground: true,
          ),
          input: const InputProvenance(
            source: 'MIDI',
            transport: 'ble',
            clockGranularity: 1,
            clockModulus: 8192,
          ),
        ),
      );

      expect(context, contains('goal=FOUNDATIONS'));
      expect(context, contains('open=9.25s first=1.50s playing=6.42s'));
      expect(context, contains('left=true'));
      expect(context, contains('input=MIDI/ble/clock1mod8192'));
    });

    test('marks what an older record never carried', () {
      expect(
        contextOf(recordWith()),
        'goal=- open=- first=- playing=- left=- input=-',
      );
    });
  });

  group('the coordination counterfactuals', () {
    // The device run's F major: typically together, with a short tail over the
    // bound, and a fault reported for it.
    final sample = sampleWith(const [
      45,
      15,
      9,
      0,
      -7,
      31,
      -13,
      16,
      -1,
      12,
      -15,
      -14,
      -21,
      -1,
      25,
    ]);

    test('a looser bound forgives the tail this one was faulted for', () {
      expect(sample.looseMomentsAt(30), 2);
      expect(sample.looseMomentsAt(40), 1);
      expect(sample.looseMomentsAt(50), 0);
    });

    test('the score rises with the bound, on the same playing', () {
      final at30 = sample.scoreUnder(
        const MeasurementPolicy(synchronizedAsynchronyMs: 30),
      );
      final at50 = sample.scoreUnder(
        const MeasurementPolicy(synchronizedAsynchronyMs: 50),
      );

      expect(at50, greaterThan(at30));
      expect(at50, 1, reason: 'nothing in this series is outside 50 ms');
    });

    test('every bound is written beside what was actually in force', () {
      final table = coordinationTableOf(learner, [sample]);

      for (final bound in counterfactualBoundsMs) {
        expect(table, contains('@${bound.round()}ms'));
      }
      expect(
        table,
        contains('counterfactual'),
        reason: 'the columns must not read as what the learner was told',
      );
    });
  });
}
