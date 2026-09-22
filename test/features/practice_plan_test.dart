import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/focus_sheet.dart';
import 'package:keyrecall/features/practice/loop_failure.dart';
import 'package:keyrecall/features/practice/practice_failure.dart';
import 'package:material_ui/material_ui.dart';
import 'package:keyrecall/features/practice/exercise_presentation.dart';
import 'package:keyrecall/features/practice/practice_focus.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
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

    // The attempt on screen goes with the material it came from. Nobody
    // answered it, so there is nothing to keep, and showing it again is what
    // makes a focus look like it did nothing.
    final reopened = await container.read(practiceLoopProvider.future);
    expect(reopened.pending, isNull);
    expect(reopened.presented, isNotNull);
    expect(reopened.presented!.exercise.material.tonic, 'A');
  });

  test('an attempt the new focus still reaches is kept', () async {
    final container = launch();
    await place(container);
    final opened = await container.read(practiceLoopProvider.future);
    final presented = opened.presented!.exercise.material;

    await container
        .read(practicePlanProvider.notifier)
        .apply(
          PracticePlan.normal.focusedOn(
            ActiveFocus(
              label: materialName(presented),
              strength: FocusStrength.exclusive,
              material: MaterialFocus(tonics: {presented.tonic}),
            ),
          ),
        );

    final reopened = await container.read(practiceLoopProvider.future);
    expect(reopened.pending, isNotNull);
    expect(reopened.exercise!.material.materialId, presented.materialId);
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
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.inactivityTimeout),

          attempt: container.read(practiceLoopProvider).requireValue.attempt!,
        );

    final loop = container.read(practiceLoopProvider).value!;
    expect(loop.presented, isNotNull, reason: 'nothing was excluded');
  });

  test('exclusive focus suspends a recovery outside its envelope', () async {
    final container = launch();
    await place(container);
    final first = await container.read(practiceLoopProvider.future);
    expect(
      first.presented!.exercise.material.materialId,
      isNot('A_NATURAL_MINOR'),
    );

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
    await container
        .read(practiceLoopProvider.notifier)
        .finish(
          AttemptCompletion.unplayed(AttemptTermination.learnerStopped),
          attempt: container.read(practiceLoopProvider).requireValue.attempt!,
        );

    final loop = container.read(practiceLoopProvider).value!;
    expect(
      loop.presented!.exercise.material.materialId,
      'A_NATURAL_MINOR',
      reason: 'the new exclusive focus no longer permits the failed material',
    );
  });

  test(
    'a goal this build cannot read stops the loop rather than widening it',
    () async {
      final container = launch();
      await place(container);
      final profile = (await profiles.selectedOrOldest())!;
      await practice.savePracticePlan(
        profile.id,
        const PracticePlan(goalId: 'UNKNOWN_EXAM'),
      );

      final relaunched = launch();

      await expectLater(
        relaunched.read(practiceLoopProvider.future),
        throwsA(
          isA<PracticeLoopFailure>().having(
            (failure) => failure.kind,
            'kind',
            PracticeFailure.plan,
          ),
        ),
      );
    },
  );

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

  group('a stored plan this build cannot read', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('keyrecall_plan_test');
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    ProviderContainer onDisk() {
      final container = ProviderContainer(
        overrides: [
          storageRootProvider.overrideWith((ref) async => root),
          inProcessScheduling,
          practiceCatalogProvider.overrideWithValue(_catalog),
        ],
      );
      addTearDown(container.dispose);
      container.read(inputSourceProvider.notifier).use(InputSourceKind.demo);
      return container;
    }

    Future<Profile> placedOn(ProviderContainer container) async {
      await place(container);
      return (await container.read(practiceLoopProvider.future)).profile;
    }

    void corruptPlanOf(Profile profile) =>
        File('${root.path}/${profile.id}/plan.json')
            .writeAsStringSync('{not json');

    Future<Object?> failureFrom(ProviderContainer container) => container
        .read(practiceLoopProvider.future)
        .then<Object?>((_) => null, onError: (Object error) => error);

    test('reports the plan rather than the sitting it stopped', () async {
      final started = onDisk();
      final profile = await placedOn(started);
      started.dispose();
      corruptPlanOf(profile);

      final failure = await failureFrom(onDisk());

      expect(
        failure,
        isA<PracticeLoopFailure>()
            .having((failure) => failure.kind, 'kind', PracticeFailure.plan)
            .having((failure) => failure.profileId, 'profileId', profile.id)
            .having(
              (failure) => failure.cause,
              'cause',
              isA<UnusablePracticePlan>().having(
                (cause) => cause.fault,
                'fault',
                PlanFault.unreadable,
              ),
            ),
      );
    });

    test('is replaceable although it never decoded', () async {
      final started = onDisk();
      final profile = await placedOn(started);
      started.dispose();
      corruptPlanOf(profile);

      final relaunched = onDisk();
      expect(await failureFrom(relaunched), isA<PracticeLoopFailure>());
      await relaunched
          .read(practicePlanProvider.notifier)
          .replaceWithNormalPractice();

      expect(
        await FilePracticeStore(root).loadPracticePlan(profile.id),
        PracticePlan.normal,
        reason: 'the replacement is addressed to the profile that failed',
      );
      relaunched.dispose();
      final reopened = await onDisk().read(practiceLoopProvider.future);
      expect(reopened.profile.id, profile.id);
      expect(reopened.plan, PracticePlan.normal);
    });

    test('a replacement leaves everybody else alone', () async {
      final started = onDisk();
      final profile = await placedOn(started);
      final repository = FileProfileRepository(root);
      final other = await repository.create(
        displayName: 'Bob',
        placement: PlacementTier.beginner,
      );
      final store = FilePracticeStore(root);
      final held = PracticePlan.normal.focusedOn(_minorMaterial);
      await store.savePracticePlan(other.id, held);
      started.dispose();
      corruptPlanOf(profile);

      final relaunched = onDisk();
      await failureFrom(relaunched);
      await relaunched
          .read(practicePlanProvider.notifier)
          .replaceWithNormalPractice();

      expect(await store.loadPracticePlan(other.id), held);
    });

    test('a replacement does not follow the profile into a new life', () async {
      final started = onDisk();
      final profile = await placedOn(started);
      started.dispose();
      corruptPlanOf(profile);

      final relaunched = onDisk();
      await failureFrom(relaunched);
      // The history the failed plan belonged to is destroyed while the
      // failure is on screen, so the learner holding it is no longer the
      // learner the repair would write for.
      await relaunched
          .read(profileRosterProvider.notifier)
          .eraseHistory(profile.id);
      await relaunched
          .read(practicePlanProvider.notifier)
          .replaceWithNormalPractice();

      expect(
        await FilePracticeStore(root).loadPracticePlan(profile.id),
        isNull,
        reason: 'a stale incarnation writes nothing over the new one',
      );
    });
  });

  testWidgets('the plan failure offers replacement and no retry', (
    tester,
  ) async {
    final container = launch();
    await place(container);
    final profile = (await profiles.selectedOrOldest())!;
    await container.read(practicePlanProvider.future);
    await container
        .read(practicePlanProvider.notifier)
        .apply(PracticePlan.normal.focusedOn(_minorMaterial));
    final replaced = Completer<PracticePlan>();
    final subscription = container.listen(practicePlanProvider, (_, next) {
      if (next case AsyncData(:final value) when !value.isFocused) {
        if (!replaced.isCompleted) replaced.complete(value);
      }
    });
    addTearDown(subscription.close);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LoopFailure(
            error: PracticeLoopFailure(
              PracticeFailure.plan,
              const UnusablePracticePlan(PlanFault.unreadable, 'unreadable'),
              profileId: profile.id,
            ),
          ),
        ),
      ),
    );

    expect(
      find.text('Try again'),
      findsNothing,
      reason:
          'the plan reads the same every time, so asking again answers it '
          'with the same failure',
    );
    expect(find.text('Practice normally instead'), findsOneWidget);

    await tester.tap(find.text('Practice normally instead'));
    await tester.pump();
    await replaced.future;

    expect(await practice.loadPracticePlan(profile.id), PracticePlan.normal);
  });

  test('the focus control says its state where the icon cannot', () {
    expect(focusButtonLabel(PracticePlan.normal), 'Practice focus. None set.');
    expect(
      focusButtonLabel(PracticePlan.normal.focusedOn(_minorMaterial)),
      'Practice focus. Minor material.',
    );
    expect(
      focusButtonLabel(
        PracticePlan.normal.focusedOn(
          ActiveFocus(
            label: '3 materials',
            strength: FocusStrength.exclusive,
            material: MaterialFocus(tonics: {'A'}),
          ),
        ),
      ),
      'Practice focus. Only 3 materials.',
    );
  });

  test('a minor form reaches the scales that spell it and no chords', () {
    final catalog = <TechnicalMaterial>[
      ..._catalog,
      ScaleMaterial('A', ScaleForm.harmonicMinor),
      ArpeggioMaterial('A', ArpeggioQuality.minor),
    ];

    expect(formFacets({FocusForm.harmonicMinor}).selectionOf(catalog), [
      ScaleMaterial('A', ScaleForm.harmonicMinor),
    ], reason: 'a minor triad is not a harmonic-minor scale');
    expect(
      formFacets({FocusForm.minor})
          .selectionOf(catalog)
          .map((material) => material.materialId),
      containsAll([
        ScaleMaterial('A', ScaleForm.naturalMinor).materialId,
        ScaleMaterial('A', ScaleForm.harmonicMinor).materialId,
        ArpeggioMaterial('A', ArpeggioQuality.minor).materialId,
      ]),
      reason: 'minor material is one question across both families',
    );
  });

  test('a focus reopens on what it asked for, not on what it contains', () {
    expect(formsOf(formFacets({FocusForm.minor})), {FocusForm.minor});
    expect(formsOf(formFacets({FocusForm.harmonicMinor})), {
      FocusForm.harmonicMinor,
    });
    expect(formsOf(MaterialFocus(tonics: {'A'})), isEmpty);
  });

  test('only the forms a catalog holds are offered', () {
    expect(formsIn(_catalog), [
      FocusForm.major,
      FocusForm.minor,
      FocusForm.naturalMinor,
    ]);
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
