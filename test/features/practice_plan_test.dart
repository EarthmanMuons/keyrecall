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

final _catalog = <TechnicalMaterial>[
  ScaleMaterial('C', ScaleForm.major),
  ScaleMaterial('G', ScaleForm.major),
  ScaleMaterial('A', ScaleForm.naturalMinor),
];

final _minorMaterial = ActiveFocus(
  label: 'Minor material',
  strength: FocusStrength.emphasis,
  material: MaterialFocus(scaleFormIds: {ScaleForm.naturalMinor.id}),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late InMemoryProfileRepository profiles;
  late InMemoryPracticeStore practice;

  setUp(() {
    profiles = InMemoryProfileRepository();
    practice = InMemoryPracticeStore();
  });

  ProviderContainer launch() {
    final container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWith((ref) async => profiles),
        inProcessScheduling,
        practiceStoreProvider.overrideWith((ref) async => practice),
        practiceCatalogProvider.overrideWithValue(_catalog),
      ],
    );
    addTearDown(container.dispose);
    container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
    return container;
  }

  Future<void> place(ProviderContainer container) => container
      .read(profileRosterProvider.notifier)
      .place(PlacementTier.someExperience);

  test('an install nobody has focused practices normally', () async {
    final container = launch();
    await place(container);

    final plan = await container.read(practicePlanProvider.future);

    expect(plan.isFocused, isFalse);
    expect((await container.read(practiceLoopProvider.future)).plan, plan);
  });

  test('a focus outlives the run that asked for it', () async {
    final container = launch();
    await place(container);
    await container.read(practicePlanProvider.future);

    await container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));

    final relaunched = launch();
    final plan = await relaunched.read(practicePlanProvider.future);
    expect(plan.focus?.label, 'Minor material');
    expect(plan.focus?.strength, FocusStrength.emphasis);
  });

  test('an exclusive focus is the only thing presented', () async {
    final container = launch();
    await place(container);
    await container.read(practiceLoopProvider.future);

    await container
        .read(practicePlanProvider.notifier)
        .apply(
          PracticePlan.normal.focusedOn(
            ActiveFocus(
              label: 'A natural minor',
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {'A'}),
            ),
          ),
        );

    // The attempt already on screen is unaffected: its decision is durable,
    // so the reopened sitting finds it pending. The focus governs the slot
    // after it.
    final reopened = await container.read(practiceLoopProvider.future);
    expect(reopened.pending, isNotNull);
    // Closed unmeasured rather than as a failure, which would open a recovery
    // context and put the failed exercise back in front of the learner.
    await container
        .read(practiceLoopProvider.notifier)
        .finish(termination: AttemptTermination.inactivityTimeout);

    final loop = container.read(practiceLoopProvider).value!;
    expect(loop.presented, isNotNull);
    expect(loop.presented!.exercise.material.tonic, 'A');
  });

  test('an emphasis focus leaves the rest of the goal reachable', () async {
    final container = launch();
    await place(container);
    await container.read(practiceLoopProvider.future);

    await container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));
    await container.read(practiceLoopProvider.future);
    await container
        .read(practiceLoopProvider.notifier)
        .finish(termination: AttemptTermination.inactivityTimeout);

    final loop = container.read(practiceLoopProvider).value!;
    expect(loop.presented, isNotNull, reason: 'nothing was excluded');
  });

  test('recovery still answers a failure from outside the focus', () async {
    final container = launch();
    await place(container);
    final first = await container.read(practiceLoopProvider.future);
    final failed = first.presented!.exercise;

    await container
        .read(practicePlanProvider.notifier)
        .apply(
          PracticePlan.normal.focusedOn(
            ActiveFocus(
              label: 'A natural minor',
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {'A'}),
            ),
          ),
        );
    await container.read(practiceLoopProvider.future);
    await container.read(practiceLoopProvider.notifier).finish();

    final loop = container.read(practiceLoopProvider).value!;
    expect(
      loop.presented!.exercise.material.materialId,
      failed.material.materialId,
      reason:
          'a recovery context is exclusive and outranks the focus for the '
          'exercise that was just failed',
    );
  });

  test('practicing normally again drops the focus', () async {
    final container = launch();
    await place(container);
    await container.read(practicePlanProvider.future);
    await container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));

    await container.read(practicePlanProvider.notifier).practiceNormally();

    expect(container.read(practicePlanProvider).value!.isFocused, isFalse);
  });

  test('suggestions describe the catalog rather than a fixed taxonomy', () {
    final labels = focusSuggestionsFor(_catalog)
        .map((suggestion) => suggestion.label);

    expect(
      labels,
      isNot(contains('Arpeggios')),
      reason: 'this catalog holds no arpeggios to focus on',
    );
    expect(labels, contains('Minor material'));
    expect(
      focusSuggestionsFor([_catalog.first]),
      isEmpty,
      reason: 'a focus that reaches everything narrows nothing',
    );
  });
}
