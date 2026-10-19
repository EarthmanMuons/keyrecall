import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
import 'package:keyrecall/features/practice/practice_failure.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an attempt another writer recorded first is reported unsaved, and '
      'practice continues from what was recorded', () async {
    final profiles = InMemoryProfileRepository();
    final practice = InMemoryPracticeStore();
    final catalog = [
      ScaleMaterial('C', ScaleForm.major),
      ScaleMaterial('G', ScaleForm.major),
    ];
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        inProcessScheduling,
        practiceStoreProvider.overrideWith((ref) async => practice),
        practiceCatalogProvider.overrideWithValue(catalog),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);
    final loop = await container.read(practiceLoopProvider.future);
    final issued = loop.attempt!;

    final elsewhere = await PracticeSession.open(
      store: practice,
      profile: loop.profile,
      materials: catalog,
      sessionId: 'elsewhere',
    );
    await elsewhere.closeUnmeasured(
      termination: AttemptTermination.inputInterrupted,
    );

    await container
        .read(practiceLoopProvider.notifier)
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: issued,
        );
    final failure = container.read(practiceLoopProvider).error;
    expect(
      failure,
      isA<PracticeLoopFailure>().having(
        (failure) => failure.kind,
        'kind',
        PracticeFailure.overtaken,
      ),
    );

    await container.read(practiceLoopProvider.notifier).retry();
    final resumed = await container.read(practiceLoopProvider.future);
    expect(resumed.attemptsRecorded, 1);
    expect(resumed.presented, isNotNull);
    expect(
      (await practice.loadJournal(loop.profile.id))
          .records
          .single
          .closure
          .termination,
      AttemptTermination.inputInterrupted,
    );
  });
}
