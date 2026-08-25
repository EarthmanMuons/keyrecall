import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'package:crisp_notation/crisp_notation.dart' as crisp;

import 'package:keyrecall/features/demo_input/demo_input.dart';
import 'package:keyrecall/features/piano/piano.dart';
import 'package:keyrecall/features/practice/attempt_screen.dart';

void main() {
  Exercise exerciseUnder(GuidanceContext guidance) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    guidance: guidance,
  );

  /// Pumps one attempt and returns how many times it was finished.
  Future<List<void>> pumpAttempt(
    WidgetTester tester,
    GuidanceContext guidance, {
    PresentationConditions? presentation,
  }) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final finished = <void>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AttemptView(
              // A fresh view per rung: pumping the same type without a key
              // would keep the previous attempt's phase.
              key: ValueKey(guidance.independence),
              exercise: exerciseUnder(guidance),
              presentation: presentation,
              onFinish: () async => finished.add(null),
            ),
          ),
        ),
      ),
    );
    return finished;
  }

  /// How many notes the staff on screen is showing.
  int staffNotes(WidgetTester tester) {
    final staff = find.byType(crisp.MultiSystemView);
    if (staff.evaluate().isEmpty) return 0;
    final score = tester.widget<crisp.MultiSystemView>(staff).score;
    return [
      for (final measure in score.measures)
        for (final element in measure.elements)
          if (element is crisp.NoteElement) element,
    ].length;
  }

  /// The notes the diagram is marking right now, or none when the keyboard is
  /// not on screen at all.
  Set<int> markers(WidgetTester tester) {
    final keyboard = find.byType(PianoKeyboard);
    return keyboard.evaluate().isEmpty
        ? const {}
        : tester.widget<PianoKeyboard>(keyboard).scaleNoteNumbers;
  }

  /// Taps Ready and lets the whole count-in run out.
  Future<void> readyAndCountIn(WidgetTester tester) async {
    await tester.tap(find.text('Ready'));
    await tester.pump();
    // Four beats at the default 80 bpm, plus a beat of margin.
    await tester.pump(const Duration(milliseconds: 750 * 5));
  }

  testWidgets('the task statement is there at every rung', (tester) async {
    for (final guidance in GuidanceContext.ladder) {
      await pumpAttempt(tester, guidance);

      expect(find.text('C major'), findsOneWidget);
      expect(
        find.text('Right hand · 2 octaves · up and down · 80 bpm'),
        findsOneWidget,
        reason:
            'the conditions are the task, not a cue, so guidance does not '
            'take them away',
      );
    }
  });

  testWidgets('a surface for playing is on screen at every rung and phase', (
    tester,
  ) async {
    for (final guidance in GuidanceContext.ladder) {
      await pumpAttempt(tester, guidance);
      expect(find.byType(PianoKeyboard), findsOneWidget);

      await readyAndCountIn(tester);
      expect(
        find.byType(PianoKeyboard).evaluate().length +
            find.byType(crisp.MultiSystemView).evaluate().length,
        greaterThan(0),
        reason:
            'withdrawal takes information away, not the surfaces: the '
            'keyboard carries the echo, or the staff carries the transcript',
      );
    }
  });

  testWidgets('continuous cues stay marked through the attempt', (
    tester,
  ) async {
    await pumpAttempt(tester, GuidanceContext.continuouslyCued);
    expect(markers(tester), isNotEmpty);

    await readyAndCountIn(tester);

    expect(markers(tester), isNotEmpty);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a preview is withdrawn at Ready and does not come back', (
    tester,
  ) async {
    await pumpAttempt(tester, GuidanceContext.notesPreviewedOnly);
    expect(markers(tester), isNotEmpty);

    await tester.tap(find.text('Ready'));
    await tester.pump();

    expect(
      markers(tester),
      isEmpty,
      reason:
          'the cue goes at Ready, which is what separates studying it '
          'from playing from memory',
    );
    await tester.pump(const Duration(milliseconds: 750 * 5));
    expect(markers(tester), isEmpty);
    expect(find.text('From memory now.'), findsOneWidget);
    expect(
      find.byType(crisp.MultiSystemView),
      findsOneWidget,
      reason:
          'with the cue withdrawn, the staff is free to carry what is '
          'actually played',
    );
  });

  testWidgets('an unguided attempt never marks the notes', (tester) async {
    await pumpAttempt(tester, GuidanceContext.unguided);

    expect(markers(tester), isEmpty);
    await readyAndCountIn(tester);
    expect(markers(tester), isEmpty);
    expect(
      find.text('Listening.'),
      findsOneWidget,
      reason:
          'the learner can see the app is listening without being told '
          'anything about pitch',
    );
  });

  group('a cue written on a staff', () {
    PresentationConditions onStaff(GuidanceContext guidance) =>
        PresentationConditions(
          pitchCue: guidance.isMaterialSupplied ? PitchCue.full : PitchCue.none,
          cueModality: guidance.isMaterialSupplied ? CueModality.staff : null,
          motorCue: MotorCue.none,
          performanceFeedback: PerformanceFeedback.neutralEcho,
          tempoSupport: TempoSupport.countInOnly,
        );

    testWidgets('is drawn instead of marking the keys', (tester) async {
      await pumpAttempt(
        tester,
        GuidanceContext.continuouslyCued,
        presentation: onStaff(GuidanceContext.continuouslyCued),
      );

      expect(find.byType(crisp.MultiSystemView), findsOneWidget);
      expect(
        markers(tester),
        isEmpty,
        reason:
            'the cue is on one surface at a time, and the keyboard is '
            'here to echo playing rather than to repeat the cue',
      );
    });

    testWidgets('is withdrawn like any other cue', (tester) async {
      await pumpAttempt(
        tester,
        GuidanceContext.notesPreviewedOnly,
        presentation: onStaff(GuidanceContext.notesPreviewedOnly),
      );
      expect(find.byType(crisp.MultiSystemView), findsOneWidget);

      await readyAndCountIn(tester);

      expect(
        staffNotes(tester),
        0,
        reason:
            'the written notes go at Ready; the staff that remains is '
            'carrying the transcript, which is empty until something is '
            'played',
      );
    });

    testWidgets('never appears when nothing is supplied', (tester) async {
      await pumpAttempt(
        tester,
        GuidanceContext.unguided,
        presentation: onStaff(GuidanceContext.unguided),
      );

      expect(find.byType(crisp.MultiSystemView), findsNothing);
      expect(find.byType(crisp.GrandStaffView), findsNothing);
    });
  });

  testWidgets('an unguided attempt writes down what was played', (
    tester,
  ) async {
    await pumpAttempt(tester, GuidanceContext.unguided);
    await readyAndCountIn(tester);
    expect(staffNotes(tester), 0);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AttemptView)),
    );
    // The wrong notes, in a descending order the exercise never asks for:
    // the transcript says what arrived, not what was expected.
    container.read(demoInputProvider.notifier).playSequence(const [
      66,
      63,
      61,
      61,
    ]);
    await tester.pump(const Duration(seconds: 3));

    expect(
      staffNotes(tester),
      4,
      reason: 'a repeated note was played twice, so it is written twice',
    );
    expect(
      markers(tester),
      isEmpty,
      reason: 'nothing about the exercise appears next to what was played',
    );
  });

  testWidgets('every rung counts in', (tester) async {
    for (final guidance in GuidanceContext.ladder) {
      await pumpAttempt(tester, guidance);
      await tester.tap(find.text('Ready'));
      await tester.pump();

      expect(
        find.text('Counting in'),
        findsOneWidget,
        reason:
            'tempo support is its own axis: the pulse is established '
            'whether or not the notes were shown',
      );
      expect(find.text('4'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 750));
      expect(find.text('3'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 750 * 4));
      expect(find.text('Counting in'), findsNothing);
    }
  });

  testWidgets('finishing commits what was played, asking nothing', (
    tester,
  ) async {
    final finished = await pumpAttempt(tester, GuidanceContext.unguided);
    await readyAndCountIn(tester);

    await tester.tap(find.text('Done'));
    await tester.pump();

    expect(
      finished,
      hasLength(1),
      reason: 'what arrived on the wire is the evidence',
    );
    expect(
      find.text('Clean'),
      findsNothing,
      reason: 'nobody is asked how it went once the app can read it',
    );
  });
}
