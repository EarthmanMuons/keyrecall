import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
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
      achievedTempoRatio: 1,
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

    await tester.pumpWidget(
      MaterialApp(
        home: AttemptReview(
          record: record,
          history: [record],
          next: null,
          onNext: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('First clean right-hand pass at 60 BPM.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Done'), 200);
    expect(find.text('Done'), findsOneWidget);
  });
}
