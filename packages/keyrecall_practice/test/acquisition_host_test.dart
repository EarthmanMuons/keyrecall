import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

void main() {
  final material = fixtureMaterials.first;
  final goal = PracticeGoal(
    id: 'ONE_SCALE',
    curriculum: Curriculum(
      id: 'PSEUDO',
      version: '2026',
      requirements: [
        CurriculumRequirement(
          id: 'ONE',
          familyId: material.familyId,
          materialId: material.materialId,
        ),
      ],
    ),
  );

  final resolution =
      PracticeScopeResolver().resolve(
            goal: goal,
            focus: PracticeFocus.unrestricted,
            catalog: fixtureMaterials,
            instrument: InstrumentProfile(),
          )
          as ValidPracticeScope;
  final scope = resolution.scope;
  final requirement = scope.requirements.single;
  final floor = PracticeScopeResolver().acquisitionFloorFor([requirement]);
  final floorExercises = {for (final entry in floor.entries) entry.exercise};

  /// A learner who has attempted the family's floor and demonstrated nothing.
  ///
  /// The state the entry rule names: the gentlest ordinary question has been
  /// asked at those exact exercises and has produced no frontier.
  LearnerState stuck() {
    final state = LearnerState.atPlacement(
      PlacementTier.someExperience,
      params,
      at: t0,
    );
    for (final exercise in floorExercises) {
      state
              .materialExecutionFor(
                executionContextOf(exercise),
                t0,
                params,
                familyId: material.familyId,
              )
              .lastEvidenceAt =
          t0;
    }
    return state;
  }

  Future<SchedulerHost> boundHost(SchedulerHost host) async {
    await host.bind(
      scope: scope,
      entry: resolution.entryPolicy,
      learner: learner,
      config: v1SchedulerConfig,
    );
    return host;
  }

  Future<SchedulerVerdict> decideOn(
    SchedulerHost host, {
    AcquisitionProgress? acquisition,
    Set<Exercise> attempted = const {},
  }) => host.decide(
    epoch: 0,
    state: stuck(),
    session: SessionState(),
    dueRequirementIds: [requirement.requirement.id],
    at: t0.plusDays(0.5),
    acquisitionFloor: floor,
    acquisition: acquisition,
    attemptedExercises: attempted,
  );

  test('a host carries an offered task rather than a blocked slot', () async {
    final host = await boundHost(
      InProcessScheduler(const SchedulerPipeline(learner: learner)),
    );

    final verdict = await decideOn(
      host,
      acquisition: const AcquisitionProgress.empty(),
      attempted: floorExercises,
    );

    expect(floorExercises, contains(verdict.acquisitionTask?.parent));
    expect(verdict.acquisitionTask?.timing, TimingDemand.unmetered);
    expect(verdict.chosen, isNull);
    expect(verdict.blockedReason, isNull);
  });

  test(
    'a host given no acquisition history decides as it always did',
    () async {
      // The compatibility boundary. A caller that has not adopted acquisition
      // reaches the verdict it reached before any of this existed.
      final host = await boundHost(
        InProcessScheduler(const SchedulerPipeline(learner: learner)),
      );

      final verdict = await decideOn(host);

      expect(verdict.acquisitionTask, isNull);
      expect(verdict.chosen, isNotNull);
    },
  );

  test('a worker carries the same task the calling isolate would', () async {
    // The task crosses the port intact, which is the whole of what the
    // transport owes: an acquisition task is not a candidate and cannot ride
    // back as one.
    final worker = await boundHost(IsolateScheduler());
    final inProcess = await boundHost(
      InProcessScheduler(const SchedulerPipeline(learner: learner)),
    );
    addTearDown(worker.dispose);

    final onWorker = await decideOn(
      worker,
      acquisition: const AcquisitionProgress.empty(),
      attempted: floorExercises,
    );
    final directly = await decideOn(
      inProcess,
      acquisition: const AcquisitionProgress.empty(),
      attempted: floorExercises,
    );

    expect(onWorker.acquisitionTask, directly.acquisitionTask);
    expect(floorExercises, contains(onWorker.acquisitionTask?.parent));
    expect(onWorker.diagnostics, directly.diagnostics);
  });
}
