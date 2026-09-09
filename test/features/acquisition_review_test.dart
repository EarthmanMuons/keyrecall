import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/acquisition_review.dart';

void main() {
  final parent = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  final t0 = DateTime.utc(2026, 9, 9);

  AttemptIdentity identityFor(String id) => AttemptIdentity(
    profileId: 'abc12345',
    attemptId: id,
    sessionId: 'sitting-1',
    indexInSession: 0,
    occurredAt: t0,
  );

  AcquisitionAttemptRecord closed(AcquisitionCompletion completion) =>
      AcquisitionAttemptRecord(
        journalSequence: 0,
        identity: identityFor('acq-0'),
        task: AcquisitionTask.unmeteredTraversal(parent),
        started: true,
        completion: completion,
        repairs: 0,
        repeats: 0,
        intrusions: 0,
        earnedProbe: false,
        gaps: const [],
      );

  /// A decided next attempt, admitted through [bypass].
  PresentedAttempt upcoming(Exercise exercise, ChallengeBypass? bypass) =>
      PresentedAttempt(
        PendingDecision(
          attemptId: 'next-0',
          profileId: 'abc12345',
          sessionId: 'sitting-1',
          indexInSession: 1,
          journalSequence: 0,
          decidedAt: t0,
          provenance: const ModelProvenance(
            learnerModelVersion: 'learner',
            schedulerModelVersion: 'scheduler',
          ),
          exercise: exercise,
          decision: SchedulerDecision(
            prediction: const Prediction(
              independentRetrievalP: 0.5,
              materialAvailableP: 0.5,
              executionP: 0.5,
              coordinationP: 0.5,
              topologyP: 0.5,
            ),
            eligibilityTier: EligibilityTier.fullyEligible,
            eligibilityReason: null,
            safetyReason: 'ok',
            withinChallengeBand: true,
            challengeBandMin: 0.15,
            challengeBandMax: 0.85,
            challengeBypass: bypass,
            rankKey: const RankKey(
              tier: EligibilityTier.fullyEligible,
              retention: 0,
              information: 0,
              diversity: 0,
              goals: 0,
            ),
          ),
          stateBeforeHash: 'hash',
        ),
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
  }

  testWidgets('previews the whole next task, not just its name', (
    tester,
  ) async {
    final next = Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.left,
      octaves: 1,
      direction: ExerciseDirection.upDown,
      tempoBpm: 60,
      guidance: GuidanceContext.notesPreviewedOnly,
    );

    await pump(
      tester,
      AcquisitionReview(
        record: closed(AcquisitionCompletion.completedCleanly),
        next: upcoming(next, ChallengeBypass.newMaterial),
        onNext: () {},
      ),
    );

    // A material name alone says which scale and nothing about what is being
    // asked of it.
    expect(find.text('Left hand · Up and down · 1 octave · 60 BPM'), findsOne);
    expect(find.text('Continue'), findsOne);
    expect(find.textContaining('Back at'), findsNothing);
  });

  testWidgets('says the tempo is back only for the probe', (tester) async {
    await pump(
      tester,
      AcquisitionReview(
        record: closed(AcquisitionCompletion.completedCleanly),
        next: upcoming(parent, ChallengeBypass.acquisitionProbe),
        onNext: () {},
      ),
    );

    expect(find.text('Back at 60 BPM this time.'), findsOne);
  });

  testWidgets('does not claim a traversal that did not come out', (
    tester,
  ) async {
    await pump(
      tester,
      AcquisitionReview(
        record: closed(AcquisitionCompletion.notCompleted),
        onNext: () {},
      ),
    );

    expect(find.textContaining('all the way through'), findsNothing);
    expect(find.text('Not all of it came out that time.'), findsOne);
    expect(find.text('Done'), findsOne);
  });
}
