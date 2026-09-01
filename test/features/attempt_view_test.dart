import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

import 'package:crisp_notation/crisp_notation.dart' as crisp;

import 'package:keyrecall/features/demo_input/demo_input.dart';
import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';
import 'package:keyrecall/features/piano/piano.dart';
import 'package:keyrecall/features/practice/attempt_screen.dart';

import '../support/synthetic_instrument.dart';

void main() {
  /// Two octaves, so the task statement under test is the plural one. Every
  /// other exercise here takes the one-octave default.
  Exercise exerciseUnder(GuidanceContext guidance) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    octaves: 2,
    guidance: guidance,
  );

  /// Pumps one attempt and returns how many times it was finished.
  Future<List<AttemptTermination>> pumpAttempt(
    WidgetTester tester,
    GuidanceContext guidance, {
    PresentationConditions? presentation,
  }) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final finished = <AttemptTermination>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [syntheticInstrument],
        child: MaterialApp(
          home: Scaffold(
            body: AttemptView(
              // A fresh view per rung: pumping the same type without a key
              // would keep the previous attempt's phase.
              key: ValueKey(guidance.independence),
              exercise: exerciseUnder(guidance),
              presentation: presentation,
              onFinish: (termination) async => finished.add(termination),
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
      // Where the hand goes is part of the task, not a cue: an unguided
      // attempt cannot infer the register the exercise placed the scale in,
      // and playing it correctly an octave away scores as every note wrong.

      for (final fact in const [
        'RIGHT HAND',
        'Up and down · 2 octaves · from C4',
        '80 bpm',
      ]) {
        expect(
          find.text(fact),
          findsOneWidget,
          reason:
              'the conditions are the task, not a cue, so guidance does '
              'not take them away',
        );
      }
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
      find.byType(crisp.MultiSystemView),
      findsOneWidget,
      reason:
          'what the learner sees of the attempt is what they played, '
          'which says nothing about what was asked for',
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

  group('playing before the attempt', () {
    /// What the transcript holds right now.
    PerformanceTranscript transcriptIn(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(AttemptView)))
            .read(attemptTranscriptProvider);

    testWidgets('is visible and is not evidence', (tester) async {
      await pumpAttempt(tester, GuidanceContext.unguided);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AttemptView)),
      );

      container.read(demoInputProvider.notifier).playSequence(const [60, 62]);
      await tester.pump(const Duration(seconds: 2));

      expect(
        container.read(inputActivityProvider).eventCount,
        greaterThan(0),
        reason: 'warming up is visible, and the keyboard reacts',
      );
      expect(
        transcriptIn(tester).isEmpty,
        isTrue,
        reason: 'an attempt that has not begun cannot have been played',
      );
    });

    testWidgets('does not make a later attempt look started', (tester) async {
      await pumpAttempt(tester, GuidanceContext.unguided);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AttemptView)),
      );
      container.read(demoInputProvider.notifier).playSequence(const [60, 62]);
      await tester.pump(const Duration(seconds: 2));

      await readyAndCountIn(tester);

      expect(
        transcriptIn(tester).isEmpty,
        isTrue,
        reason:
            'the transcript begins at Ready, so noodling beforehand is '
            'not the opening of the performance',
      );
    });

    testWidgets('what arrives after Ready is', (tester) async {
      await pumpAttempt(tester, GuidanceContext.unguided);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AttemptView)),
      );

      await readyAndCountIn(tester);
      container.read(demoInputProvider.notifier).playSequence(const [60, 62]);
      await tester.pump(const Duration(seconds: 2));

      expect(transcriptIn(tester).length, 2);
    });
  });

  testWidgets('an attempt ends when the traversal is covered, not counted', (
    tester,
  ) async {
    final finished = await pumpAttempt(tester, GuidanceContext.unguided);
    await readyAndCountIn(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AttemptView)),
    );

    // C major, right hand, two octaves up and down: 29 positions, played here
    // with one extra note partway. Counting arrivals would stop at 29 and cut
    // off the last note of the scale. Realized from the exercise that was
    // actually pumped, so the two cannot drift apart.
    final realization = realize(exerciseUnder(GuidanceContext.unguided));
    final expectedNotes = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.right)!.midiNote,
    ];
    container
        .read(demoInputProvider.notifier)
        .playSequence(
          [...expectedNotes]..insert(4, 61),
          tempo: DemoInputTempo.brisk,
        );
    await tester.pump(const Duration(seconds: 2));

    expect(
      finished,
      hasLength(1),
      reason: 'the attempt ended once, after the whole traversal was covered',
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

  testWidgets('a new attempt does not inherit the last one\'s notes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: [syntheticInstrument]);
    addTearDown(container.dispose);

    Future<void> mount(Key key) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AttemptView(
              key: key,
              exercise: exerciseUnder(GuidanceContext.unguided),
              onFinish: (_) async {},
              onDecline: () async {},
            ),
          ),
        ),
      ),
    );

    await mount(const ValueKey('first'));
    await readyAndCountIn(tester);
    container.read(demoInputProvider.notifier).playSequence(const [60, 62, 64]);
    await tester.pump(const Duration(seconds: 3));
    expect(container.read(attemptTranscriptProvider).length, 3);

    // Closing an attempt reads the transcript after recording has stopped, so
    // those notes are still here when the next attempt is put on screen.
    await mount(const ValueKey('second'));
    await tester.pump();

    expect(
      container.read(attemptTranscriptProvider).length,
      0,
      reason:
          'those notes belong to the attempt that recorded them, and this '
          'screen can be asked about its own before it has played any',
    );
  });
}
