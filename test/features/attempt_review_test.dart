import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

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
    ScaleDirection direction = ScaleDirection.up,
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
      decision: const SchedulerDecision(
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
        challengeBypass: ChallengeBypass.newMaterial,
        rankKey: RankKey(
          tier: EligibilityTier.fullyEligible,
          retention: 0,
          information: 0,
          diversity: 0,
          goals: 0,
        ),
      ),
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
        differenceTo(exerciseOf(direction: ScaleDirection.upDown), previous),
        'Up and back down this time.',
      );
      expect(
        differenceTo(exerciseOf(tempoBpm: 72), previous),
        'A little quicker.',
      );
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
            onNext: () {},
            onDetailsViewed: () => detailsViewed++,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.textContaining('termination'), findsNothing);
    expect(
      find.text('First clean right-hand run from memory at 122 BPM.'),
      findsOneWidget,
    );
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('122 BPM · target 60'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    expect(find.text('G major'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('What KeyRecall heard'), findsOneWidget);
    expect(
      find.text(
        'These lines describe this attempt, not your overall skill level.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('How evenly the notes were spaced in time.'),
      findsOneWidget,
    );
    expect(find.text('Measurement details'), findsOneWidget);
    expect(find.textContaining('termination'), findsOneWidget);
    expect(find.textContaining('motor score'), findsOneWidget);
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
