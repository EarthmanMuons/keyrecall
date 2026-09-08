import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  final parent = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );

  group('the unmetered traversal', () {
    test('keeps everything about the parent but the tempo obligation', () {
      final task = AcquisitionTask.unmeteredTraversal(parent);

      expect(task.parent, parent);
      expect(task.portion, const FullTraversal());
      expect(task.advancement, TaskAdvancement.learnerDriven);
      expect(task.timing, TimingDemand.unmetered);
      expect(realizeAcquisition(task), realize(parent));
    });

    test('is not an exercise, so nothing ordinary can consume it', () {
      // The evidence boundary is the type. A guidance rung leaves an ordinary
      // realization behind and is still an Exercise; this relaxes the task, so
      // candidate ranking, the frontier, and the learner model cannot reach it
      // by any route that takes an exercise.
      expect(
        AcquisitionTask.unmeteredTraversal(parent),
        isNot(isA<Exercise>()),
      );
    });
  });

  group('timing demand', () {
    test('is what tempo evidence depends on', () {
      expect(TimingDemand.metered.requestsTempo, isTrue);
      expect(TimingDemand.metered.supportsTempoEvidence, isTrue);
      expect(TimingDemand.unmetered.requestsTempo, isFalse);
      expect(TimingDemand.unmetered.supportsTempoEvidence, isFalse);
    });

    test('round trips through its identifier', () {
      for (final demand in TimingDemand.values) {
        expect(TimingDemand.fromId(demand.id), demand);
      }
      expect(() => TimingDemand.fromId('SOMETIMES'), throwsArgumentError);
    });
  });

  group('a task that relaxes nothing', () {
    test('is refused, because it is its own parent', () {
      expect(
        () => AcquisitionTask(
          parent: parent,
          timing: TimingDemand.metered,
          advancement: TaskAdvancement.learnerDriven,
        ),
        throwsArgumentError,
      );
    });
  });

  group('presentation', () {
    PresentationConditions cuedWith(TempoSupport support) =>
        PresentationConditions(
          pitchCue: PitchCue.full,
          cueModality: CueModality.keyboard,
          motorCue: MotorCue.none,
          performanceFeedback: PerformanceFeedback.neutralEcho,
          tempoSupport: support,
        );

    test('may not sound a pulse an unmetered task never asked for', () {
      final task = AcquisitionTask.unmeteredTraversal(parent);

      expect(task.suitsPresentation(cuedWith(TempoSupport.none)), isTrue);
      expect(
        task.suitsPresentation(cuedWith(TempoSupport.countInOnly)),
        isFalse,
      );
      expect(
        task.suitsPresentation(cuedWith(TempoSupport.metronomeThroughout)),
        isFalse,
      );
    });
  });

  group('the axes', () {
    test('stay separate from the guidance ladder', () {
      final task = AcquisitionTask.unmeteredTraversal(parent);

      // Guidance is a property of the parent exercise and is unchanged here.
      // Reading the relaxed timing off the guidance rung would say the learner
      // was given more support for the same task, which is not what happened.
      expect(task.parent.guidance, GuidanceContext.continuouslyCued);
      expect(
        parent.withGuidance(GuidanceContext.unguided).conditions.tempoBpm,
        parent.conditions.tempoBpm,
      );
      expect(task.timing, isNot(TimingDemand.metered));
    });
  });
}
