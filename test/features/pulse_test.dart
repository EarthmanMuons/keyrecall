import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/attempt_screen.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';

import '../support/synthetic_instrument.dart';

/// Tempo support changes what the learner hears and nothing else.
void main() {
  Exercise exerciseOf() => Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.right,
    guidance: GuidanceContext.notesPreviewedOnly,
  );

  PresentationConditions under(TempoSupport tempoSupport) =>
      PresentationConditions(
        pitchCue: PitchCue.full,
        cueModality: CueModality.keyboard,
        motorCue: MotorCue.none,
        performanceFeedback: PerformanceFeedback.neutralEcho,
        tempoSupport: tempoSupport,
      );

  testWidgets('the exercise is identical under every tempo support', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final transcripts = <PerformanceTranscript>[];
    for (final support in TempoSupport.values) {
      final container = ProviderContainer(overrides: [syntheticInstrument]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: AttemptView(
                key: ValueKey(support),
                exercise: exerciseOf(),
                presentation: under(support),
                onFinish: (_) async {},
              ),
            ),
          ),
        ),
      );

      // The task statement is what the exercise asks for, and no amount of
      // tempo support may change it.
      expect(find.text('C major'), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);

      await tester.tap(find.text('Ready'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750 * 5));
      transcripts.add(container.read(attemptTranscriptProvider).transcript);
    }

    expect(transcripts.map((t) => t.length).toSet(), {
      0,
    }, reason: 'a click is not a note, whichever way it is sounded');
  });
}
