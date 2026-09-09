import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/acquisition_review.dart';
import 'package:keyrecall/features/practice/attempt_review.dart';

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
  NextPracticePreview upcoming(Exercise exercise, ChallengeBypass? bypass) =>
      NextPracticePreview(
        material: exercise.material,
        explanation: bypass == ChallengeBypass.acquisitionProbe
            ? restoredTempoLine(exercise)
            : null,
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: child));
  }

  testWidgets('names what comes next and why, and stops there', (tester) async {
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

    // Orientation, not instruction. The Ready screen states the hand, the
    // direction, the span and the tempo; repeating them here was busy and said
    // nothing the next screen was not about to say.
    expect(find.text('C major'), findsNWidgets(2));
    expect(find.textContaining('1 octave'), findsNothing);
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
