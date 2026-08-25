import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/piano/piano.dart';
import 'package:keyrecall/features/practice/attempt_screen.dart';
import 'package:keyrecall/features/practice/reported_result.dart';

void main() {
  Exercise exerciseUnder(GuidanceContext guidance) => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    guidance: guidance,
  );

  /// Pumps one attempt and returns what it reported, in order.
  Future<List<ReportedResult>> pumpAttempt(
    WidgetTester tester,
    GuidanceContext guidance,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final reported = <ReportedResult>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AttemptView(
              // A fresh view per rung: pumping the same type without a key
              // would keep the previous attempt's phase.
              key: ValueKey(guidance.independence),
              exercise: exerciseUnder(guidance),
              onReport: (result) async => reported.add(result),
            ),
          ),
        ),
      ),
    );
    return reported;
  }

  /// The notes the diagram is marking right now.
  Set<int> markers(WidgetTester tester) =>
      tester.widget<PianoKeyboard>(find.byType(PianoKeyboard)).scaleNoteNumbers;

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

  testWidgets('the instrument is on screen at every rung and phase', (
    tester,
  ) async {
    for (final guidance in GuidanceContext.ladder) {
      await pumpAttempt(tester, guidance);
      expect(find.byType(PianoKeyboard), findsOneWidget);

      await readyAndCountIn(tester);
      expect(
        find.byType(PianoKeyboard),
        findsOneWidget,
        reason: 'withdrawal takes information away, not the keyboard',
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

  testWidgets('finishing hands over to the stand-in for measurement', (
    tester,
  ) async {
    final reported = await pumpAttempt(tester, GuidanceContext.unguided);
    await readyAndCountIn(tester);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(find.text('How did that go?'), findsOneWidget);

    await tester.tap(find.text('Clean'));
    await tester.pump();
    expect(reported, [ReportedResult.clean]);
  });
}
