import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_review.dart';
import 'package:keyrecall/features/practice/presentation_exposure.dart';

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
    prediction: Prediction(
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
    rankKey: RankKey(
      tier: EligibilityTier.fullyEligible,
      retention: 0,
      information: 0,
      diversity: 0,
      goals: 0,
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

    test('says only whether the metronome is on, the rest being the same', () {
      expect(
        reasonFor(ChallengeBypass.pulseSupport, previous),
        'The same one again, with the metronome.',
      );
      expect(
        reasonFor(ChallengeBypass.pulseWithdrawal, previous),
        'The same one again, without the metronome.',
      );
      expect(metronomeLine(ChallengeBypass.pulseSupport), isNotNull);
      expect(metronomeLine(ChallengeBypass.pulseWithdrawal), isNotNull);
      expect(metronomeLine(ChallengeBypass.tempoProbe), isNull);
      expect(metronomeLine(null), isNull);
    });

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
        'Now both hands, at the speed you reached earlier.',
      );
    });

    test('says what an acquisition probe is asking for now', () {
      // What changed, not why it was chosen. The learner has been playing this
      // at their own pace, and the tempo is what comes back; naming a scaffold
      // or an earlier session would ask them to remember a presentation
      // instead of telling them what to do.
      expect(
        reasonFor(ChallengeBypass.acquisitionProbe, exerciseOf(tempoBpm: 60)),
        'Back at 60 BPM this time.',
      );
      expect(
        reasonFor(
          ChallengeBypass.acquisitionProbe,
          exerciseOf(hands: HandConfiguration.left, tempoBpm: 60),
        ),
        'Now the left hand, at 60 BPM.',
      );
    });

    test('says the same scale is new when the hand it is new in is not', () {
      expect(
        reasonFor(ChallengeBypass.newMaterial, exerciseOf(material: gMajor)),
        'New here, so it comes with the notes.',
      );
    });
  });

  group('which way the next exercise moves the challenge', () {
    test('what was demonstrated earning a harder version advances', () {
      for (final bypass in [
        ChallengeBypass.executionProgression,
        ChallengeBypass.guidanceProbe,
        ChallengeBypass.tempoProbe,
        ChallengeBypass.acquisitionProbe,
      ]) {
        expect(
          challengeDirectionOf(bypass),
          ChallengeDirection.advance,
          reason: '$bypass',
        );
      }
    });

    test('stepping back is support, not a demerit', () {
      for (final bypass in [
        ChallengeBypass.recovery,
        ChallengeBypass.pulseSupport,
        ChallengeBypass.acquisitionFloor,
      ]) {
        expect(
          challengeDirectionOf(bypass),
          ChallengeDirection.support,
          reason: '$bypass',
        );
      }
    });

    test('a harder step nothing demonstrated earned is neutral', () {
      for (final bypass in [
        ChallengeBypass.consolidation,
        ChallengeBypass.bootstrapProbe,
        ChallengeBypass.observationProbe,
        ChallengeBypass.pulseWithdrawal,
        ChallengeBypass.newMaterial,
        null,
      ]) {
        expect(
          challengeDirectionOf(bypass),
          ChallengeDirection.neutral,
          reason: '$bypass',
        );
      }
    });
  });

  group('how a review arrives', () {
    test('an ordinary review keeps what comes next close behind', () {
      expect(
        reviewArrivalDelay(ReviewPart.continuation, hasMeaning: false),
        lessThan(reviewArrivalDelay(ReviewPart.meaning, hasMeaning: true)),
      );
    });

    test('progress arrives before what comes next', () {
      expect(
        reviewArrivalDelay(ReviewPart.meaning, hasMeaning: true),
        lessThan(reviewArrivalDelay(ReviewPart.continuation, hasMeaning: true)),
      );
    });
  });

  testWidgets('a change of motion preference does not report a part again', (
    tester,
  ) async {
    var reports = 0;
    Widget review({required bool reduced}) => MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: ReviewArrival(
            delay: Duration.zero,
            child: ExposureGate(
              presentation: 'progress',
              onExposed: () async {
                reports++;
                return true;
              },
              child: const SizedBox(width: 100, height: 40),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(review(reduced: false));
    await tester.pumpAndSettle();
    expect(reports, 1);

    await tester.pumpWidget(review(reduced: true));
    await tester.pumpAndSettle();
    expect(reports, 1);
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
            next: NextPracticePreview(material: gMajor),
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
        memoryUpdate: MemoryUpdateDiagnostics(),
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
    final exposed = <ReviewExposure>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptReview(
            record: record,
            history: [record],
            reading: reading,
            next: NextPracticePreview(material: gMajor),
            instrument: InstrumentReadiness.connected,
            onNext: () {},
            onExposed: (exposure) async {
              exposed.add(exposure);
              return true;
            },
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
    expect(
      exposed.map((exposure) => exposure.feedback),
      contains(PostAttemptFeedback.detailedDiagnostic),
      reason: 'the sheet reports itself from the frame it drew',
    );
    Navigator.of(tester.element(find.text('Attempt details'))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Continue'), 200);
    expect(find.text('Continue'), findsOneWidget);
  });
}
