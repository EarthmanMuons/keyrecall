import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_review.dart';

/// What the screen between attempts is allowed to say about what comes next.
void main() {
  final cMajor = TechnicalMaterial('C', ScaleForm.major);
  final gMajor = TechnicalMaterial('G', ScaleForm.major);

  Exercise exerciseOf({
    TechnicalMaterial? material,
    HandConfiguration hands = HandConfiguration.right,
    GuidanceContext guidance = GuidanceContext.unguided,
    int octaves = 1,
    ExerciseDirection direction = ExerciseDirection.up,
    double tempoBpm = 60,
  }) => Exercise.linear(
    material: material ?? cMajor,
    hands: hands,
    guidance: guidance,
    octaves: octaves,
    direction: direction,
    tempoBpm: tempoBpm,
  );

  final previous = exerciseOf();

  SchedulerDecision decisionOf(ChallengeBypass? bypass) => SchedulerDecision(
    prediction: const Prediction(
      independentRetrievalP: 0.5,
      materialAvailableP: 0.5,
      executionP: 0.5,
      coordinationP: 1,
      topologyP: 0.5,
    ),
    eligibilityTier: EligibilityTier.fullyEligible,
    eligibilityReason: null,
    safetyReason: 'safe',
    withinChallengeBand: true,
    challengeBandMin: 0.4,
    challengeBandMax: 0.7,
    challengeBypass: bypass,
    rankKey: const RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0,
      information: 0,
      diversity: 0,
      goals: 0,
    ),
  );

  PresentedAttempt presented(Exercise exercise) => PresentedAttempt(
    PendingDecision(
      attemptId: 'next-attempt',
      profileId: 'profile',
      sessionId: 'session',
      indexInSession: 1,
      journalSequence: 1,
      decidedAt: DateTime.utc(2026),
      provenance: const ModelProvenance(
        learnerModelVersion: 'learner',
        schedulerModelVersion: 'scheduler',
      ),
      exercise: exercise,
      decision: decisionOf(ChallengeBypass.newMaterial),
      stateBeforeHash: 'state',
    ),
  );

  group('what is different about the next exercise', () {
    test('says nothing when nothing about the playing changed', () {
      expect(differenceTo(exerciseOf(material: gMajor), previous), isNull);
    });

    test('names the change a learner would notice first', () {
      expect(
        differenceTo(
          exerciseOf(
            hands: HandConfiguration.together,
            guidance: GuidanceContext.continuouslyCued,
            octaves: 2,
            tempoBpm: 80,
          ),
          previous,
        ),
        'Both hands this time.',
        reason: 'four changes at once is a changelog, not a sentence',
      );
    });

    test('describes the rung it is going to, in either direction', () {
      const cued = GuidanceContext.continuouslyCued;

      expect(
        differenceTo(exerciseOf(guidance: cued), previous),
        'The notes stay up for this one.',
      );
      expect(
        differenceTo(previous, exerciseOf(guidance: cued)),
        'This one is from memory.',
      );
    });

    test('reads the conditions rather than characterizing them', () {
      expect(
        differenceTo(exerciseOf(octaves: 2), previous),
        '2 octaves this time.',
      );
      expect(
        differenceTo(exerciseOf(direction: ExerciseDirection.upDown), previous),
        'Up and back down this time.',
      );
      expect(
        differenceTo(exerciseOf(tempoBpm: 72), previous),
        'A little quicker.',
      );
    });
  });

  group('why the next exercise is what it is', () {
    String? reasonFor(ChallengeBypass? bypass, Exercise next) => reasonForNext(
      decision: decisionOf(bypass),
      next: next,
      previous: previous,
    );

    test('names the hand whatever the reason was', () {
      final otherHand = exerciseOf(hands: HandConfiguration.left);

      expect(
        reasonFor(ChallengeBypass.newMaterial, otherHand),
        'New with the left hand, so it comes with the notes.',
      );
      expect(
        reasonFor(ChallengeBypass.consolidation, otherHand),
        'Now the left hand, from memory.',
      );
      expect(
        reasonFor(
          ChallengeBypass.tempoProbe,
          exerciseOf(hands: HandConfiguration.together),
        ),
        'Now both hands, at the speed you played it.',
      );
    });

    test('says the same scale is new when the hand it is new in is not', () {
      expect(
        reasonFor(ChallengeBypass.newMaterial, exerciseOf(material: gMajor)),
        'New here, so it comes with the notes.',
      );
    });
  });

  group('an attempt nothing was played in', () {
    final silent = AttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: 'profile',
        attemptId: 'attempt',
        sessionId: 'session',
        indexInSession: 0,
        occurredAt: DateTime.utc(2026),
      ),
      provenance: const ModelProvenance(
        learnerModelVersion: 'learner',
        schedulerModelVersion: 'scheduler',
      ),
      exercise: previous,
      closure: AttemptClosure.unmeasured(
        termination: AttemptTermination.inactivityTimeout,
        reason: MeasurementUnavailableReason.nothingPlayed,
      ),
    );

    Future<void> pumpReview(
      WidgetTester tester,
      InstrumentReadiness instrument,
    ) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptReview(
            record: silent,
            history: [silent],
            next: presented(exerciseOf(material: gMajor)),
            instrument: instrument,
            onNext: () {},
          ),
        ),
      ),
    );

    testWidgets('names the missing instrument when there is none', (
      tester,
    ) async {
      await pumpReview(tester, InstrumentReadiness.disconnected);

      expect(find.text('No piano connected.'), findsOneWidget);
      expect(
        find.text('Connect your piano, then try the exercise again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(FilledButton, 'Connect'), findsOneWidget);
    });

    testWidgets('sends a connected learner to their own connection', (
      tester,
    ) async {
      await pumpReview(tester, InstrumentReadiness.connected);

      expect(find.text('No notes came through.'), findsOneWidget);
      expect(
        find.text(
          'KeyRecall received nothing from your piano. Check that it’s '
          'still connected, then try again.',
        ),
        findsOneWidget,
        reason:
            'a connected piano that sent nothing is a different problem from '
            'one that was never attached',
      );
      expect(
        find.widgetWithText(FilledButton, 'Check connection'),
        findsOneWidget,
      );
    });

    testWidgets('offers nothing to connect where nothing was wanted', (
      tester,
    ) async {
      await pumpReview(tester, InstrumentReadiness.notNeeded);

      expect(find.textContaining('piano'), findsNothing);
      expect(find.byIcon(Icons.piano), findsNothing);
    });
  });

  testWidgets('a measured review scrolls on a compact screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final outcome = Outcome(
      started: true,
      retrieval: FactualRetrieval.succeeded,
      completed: true,
      materialRetrieval: 1,
      pitchIntegrity: 1,
      continuity: 1,
      temporalStability: 1,
      achievedTempoRatio: 2.033,
      topologyAccuracy: 1,
    );
    final record = AttemptRecord(
      journalSequence: 0,
      identity: AttemptIdentity(
        profileId: 'profile',
        attemptId: 'attempt',
        sessionId: 'session',
        indexInSession: 0,
        occurredAt: DateTime.utc(2026),
      ),
      provenance: const ModelProvenance(
        learnerModelVersion: 'learner',
        schedulerModelVersion: 'scheduler',
      ),
      exercise: previous,
      closure: AttemptClosure.measured(
        termination: AttemptTermination.learnerStopped,
        outcome: outcome,
        weights: evidenceWeightsFor(previous, outcome),
        memoryUpdate: const MemoryUpdateDiagnostics(),
      ),
    );
    var transcript = PerformanceTranscript.empty;
    for (final moment in realize(previous).moments) {
      transcript = transcript.appending(
        pitch: moment.noteFor(Hand.right)!.pitch,
        timestampMs: transcript.length * 492,
      );
    }
    final reading = readPerformance(exercise: previous, transcript: transcript);
    var detailsViewed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptReview(
            record: record,
            history: [record],
            reading: reading,
            next: presented(exerciseOf(material: gMajor)),
            instrument: InstrumentReadiness.connected,
            onNext: () {},
            onDetailsViewed: () => detailsViewed++,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Notes'), findsOneWidget);
    expect(
      find.text('First clean right-hand run from memory at 122 BPM.'),
      findsOneWidget,
    );
    expect(find.text('PROGRESS'), findsOneWidget);
    expect(find.text('122 BPM · target 60'), findsOneWidget);
    expect(find.text('Next exercise'), findsOneWidget);
    expect(find.text('G major'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('What KeyRecall heard'), findsOneWidget);
    expect(
      find.text(
        'These lines describe this exercise attempt, not your overall skill '
        'level.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('How evenly the notes were spaced in time.'),
      findsOneWidget,
    );
    expect(find.text('Coordination'), findsNothing);
    Navigator.of(tester.element(find.text('What KeyRecall heard'))).pop();
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('View details')).dy,
      lessThan(
        tester
            .getTopLeft(
              find.text('First clean right-hand run from memory at 122 BPM.'),
            )
            .dy,
      ),
    );
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();
    expect(find.text('Attempt details'), findsOneWidget);
    expect(detailsViewed, 1);
    Navigator.of(tester.element(find.text('Attempt details'))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Continue'), 200);
    expect(find.text('Continue'), findsOneWidget);
  });
}
