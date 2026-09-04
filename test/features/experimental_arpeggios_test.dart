import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/practice_focus.dart';
import 'package:keyrecall/features/practice/practice_providers.dart';

import '../support/scheduler_override.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith(
          (ref) async => InMemoryProfileRepository(),
        ),
        inProcessScheduling,
        practiceStoreProvider.overrideWith(
          (ref) async => InMemoryPracticeStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    return container;
  }

  bool holdsArpeggios(ProviderContainer container) => container
      .read(practiceCatalogProvider)
      .any(
        (material) => material.familyId == TechnicalMaterial.arpeggioFamilyId,
      );

  test('a run offers scales alone until somebody asks otherwise', () {
    final container = launch();

    expect(container.read(experimentalArpeggiosProvider), isFalse);
    expect(holdsArpeggios(container), isFalse);
  });

  test('the switch is what puts arpeggios in the catalog', () {
    final container = launch();

    container.read(experimentalArpeggiosProvider.notifier).use(true);

    expect(holdsArpeggios(container), isTrue);
    expect(
      focusSuggestionsFor(container.read(practiceCatalogProvider))
          .map((suggestion) => suggestion.label),
      contains('Arpeggios'),
      reason: 'the focuses on offer follow what the catalog holds',
    );
  });

  test('a mixed catalog still reaches an exercise', () async {
    final container = launch();
    container.read(experimentalArpeggiosProvider.notifier).use(true);
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);

    final loop = await container.read(practiceLoopProvider.future);

    expect(loop.presented, isNotNull);
  });

  test(
    'withdrawing the catalog leaves a focus on it invalid, not empty',
    () async {
      final container = launch();
      container.read(experimentalArpeggiosProvider.notifier).use(true);
      await container
          .read(profileRosterProvider.notifier)
          .place(PlacementTier.someExperience);
      await container.read(practiceLoopProvider.future);
      await container
          .read(practicePlanProvider.notifier)
          .apply(
            PracticePlan.normal.focusedOn(
              ActiveFocus(
                label: 'Arpeggios',
                strength: FocusStrength.exclusive,
                material: MaterialFocus(
                  familyIds: const {TechnicalMaterial.arpeggioFamilyId},
                ),
              ),
            ),
          );

      container.read(experimentalArpeggiosProvider.notifier).use(false);
      // The attempt on screen closes normally: it is history the moment it was
      // decided, and the catalog it came from is not what commits it. The scope
      // is only asked about again for the slot after it.
      await container.read(practiceLoopProvider.future);
      await container
          .read(practiceLoopProvider.notifier)
          .finish(termination: AttemptTermination.inactivityTimeout);

      final loop = container.read(practiceLoopProvider).value!;
      expect(loop.idle, PracticeIdleReason.invalidScope);
    },
  );
}
