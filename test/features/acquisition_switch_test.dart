import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a profile switch while a supported attempt saves, and back, records '
      'it once and leaves practice usable', () async {
    final practice = _GatedAcquisition();
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) async => InMemoryProfileRepository(),
        ),
        schedulerHostFactoryProvider.overrideWith(
          (ref) =>
              () => InProcessScheduler(const _OffersAcquisition()),
        ),
        practiceStoreProvider.overrideWith((ref) async => practice),
        practiceCatalogProvider.overrideWithValue([
          ScaleMaterial('C', ScaleForm.major),
          ScaleMaterial('G', ScaleForm.major),
        ]),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    final roster = container.read(profileRosterProvider.notifier);
    await roster.place(PlacementTier.someExperience);
    final first = await container.read(practiceLoopProvider.future);
    expect(first.acquisition, isNotNull);

    practice.gate = Completer<void>();
    final saving = container
        .read(practiceLoopProvider.notifier)
        .finishAcquisition(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: first.attempt!,
        );
    await roster.add('Bo', PlacementTier.someExperience);
    await container.read(practiceLoopProvider.future);
    await roster.select(first.profile.id);
    final back = await container.read(practiceLoopProvider.future);
    practice.gate!.complete();
    await saving;

    final log = await practice.loadAcquisitionJournal(first.profile.id);
    expect(log.attempts, hasLength(1));
    expect(
      log.attempts.single.identity.attemptId,
      first.acquisition!.attemptId,
    );

    final resumed = container.read(practiceLoopProvider).value ?? back;
    await container
        .read(practiceLoopProvider.notifier)
        .finishAcquisition(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: resumed.attempt!,
        );
    expect(container.read(practiceLoopProvider).error, isNull);
    final both = await practice.loadAcquisitionJournal(first.profile.id);
    expect(both.attempts, hasLength(2));
    final folded = AllocationHistory.of(
      await practice.loadJournal(first.profile.id),
      both,
    );
    expect(folded.observed, 2);
    expect(folded.staleDecisions, 1);
  });
}

/// Holds acquisition writes until [gate] opens, when one is set.
class _GatedAcquisition extends InMemoryPracticeStore {
  Completer<void>? gate;

  @override
  Future<void> appendAcquisitionEntry(AcquisitionEntry entry) async {
    await gate?.future;
    await super.appendAcquisitionEntry(entry);
  }
}

/// Offers supported work at the floor of the first material, every slot.
class _OffersAcquisition extends SchedulerPipeline {
  const _OffersAcquisition() : super(learner: const LearnerModel());

  @override
  ({
    SelectionResult result,
    bool guidanceProbeAvailable,
    bool guidanceProbeSelected,
  })
  evaluateSlot({
    required LearnerState state,
    required SessionState session,
    required List<Exercise> candidates,
    required DateTime at,
    Map<Exercise, ChallengeBypass> overrides = const {},
    AcquisitionFloor? acquisitionFloor,
    AcquisitionFloor? acquisitionFamilyFloor,
    AcquisitionProgress? acquisition,
    AttemptHistory? history,
    PracticeEntryPolicy? practiceEntryPolicy,
    GoalEmphasis emphasis = GoalEmphasis.none,
    UncoveredTargets uncoveredTargets = UncoveredTargets.none,
    bool diagnose = true,
  }) {
    final slot = super.evaluateSlot(
      state: state,
      session: session,
      candidates: candidates,
      at: at,
      overrides: overrides,
      acquisitionFloor: acquisitionFloor,
      acquisitionFamilyFloor: acquisitionFamilyFloor,
      acquisition: acquisition,
      history: history,
      practiceEntryPolicy: practiceEntryPolicy,
      emphasis: emphasis,
      uncoveredTargets: uncoveredTargets,
      diagnose: diagnose,
    );
    final floor = (acquisitionFamilyFloor ?? acquisitionFloor)?.entries.first;
    if (floor == null) return slot;
    return (
      result: AcquisitionOffered(
        traces: slot.result.traces,
        selectable: slot.result.selectable,
        pacing: slot.result.pacing,
        introductions: slot.result.introductions,
        task: AcquisitionTask.unmeteredTraversal(floor.exercise),
        stuck: null,
      ),
      guidanceProbeAvailable: slot.guidanceProbeAvailable,
      guidanceProbeSelected: slot.guidanceProbeSelected,
    );
  }
}
