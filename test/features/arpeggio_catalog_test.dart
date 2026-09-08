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

  test('a run offers both families without being asked', () {
    final container = launch();

    expect(holdsArpeggios(container), isTrue);
    expect(
      container
          .read(practiceCatalogProvider)
          .any(
            (material) => material.familyId == TechnicalMaterial.scaleFamilyId,
          ),
      isTrue,
    );
    expect(
      focusSuggestionsFor(container.read(practiceCatalogProvider))
          .map((suggestion) => suggestion.label),
      contains('Arpeggios'),
      reason: 'the focuses on offer follow what the catalog holds',
    );
  });

  test('a mixed catalog reaches an exercise', () async {
    final container = launch();
    await container
        .read(profileRosterProvider.notifier)
        .place(PlacementTier.someExperience);

    final loop = await container.read(practiceLoopProvider.future);

    expect(loop.presented, isNotNull);
  });

  test('a focus on a family the catalog lost is invalid, not empty', () async {
    final repository = profileRepositoryProvider.overrideWith(
      (ref) async => InMemoryProfileRepository(),
    );
    final store = practiceStoreProvider.overrideWith(
      (ref) async => InMemoryPracticeStore(),
    );
    final container = ProviderContainer(
      overrides: [
        repository,
        inProcessScheduling,
        store,
        practiceCatalogProvider.overrideWithValue([
          ...allScales,
          ...allRootPositionArpeggios,
        ]),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
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

    // A catalog that no longer holds the family, which is what a narrowed
    // product scope would look like from here.
    container.updateOverrides([
      profileRepositoryProvider.overrideWith(
        (ref) async => InMemoryProfileRepository(),
      ),
      inProcessScheduling,
      practiceStoreProvider.overrideWith(
        (ref) async => InMemoryPracticeStore(),
      ),
      practiceCatalogProvider.overrideWithValue(allScales),
    ]);

    // The attempt on screen closes normally: it is history the moment it was
    // decided, and the catalog it came from is not what commits it. The scope
    // is only asked about again for the slot after it.
    await container.read(practiceLoopProvider.future);
    await container
        .read(practiceLoopProvider.notifier)
        .finish(termination: AttemptTermination.inactivityTimeout);

    final loop = container.read(practiceLoopProvider).value!;
    expect(loop.idle, PracticeIdleReason.invalidScope);
  });
}
