import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/practice/attempt_detail_trace.dart';
import 'package:keyrecall/features/practice/attempt_details_sheet.dart';

void main() {
  final exercise = Exercise.linear(
    material: TechnicalMaterial('C', ScaleForm.major),
    hands: HandConfiguration.together,
    direction: ScaleDirection.upDown,
    tempoBpm: 60,
  );

  testWidgets('details render distinct traversal evidence', (tester) async {
    final trace = AttemptDetailTrace(
      momentCount: 15,
      pulse: const [
        AttemptTracePoint(position: 1, value: 20),
        AttemptTracePoint(position: 2, value: -30),
      ],
      coordination: const [
        AttemptTracePoint(position: 1, value: 12),
        AttemptTracePoint(position: 2, value: -8),
      ],
      notes: [
        ...List.filled(13, NoteMomentStatus.matched),
        NoteMomentStatus.departed,
        NoteMomentStatus.missing,
      ],
      extraNotePositions: const [3.5],
      extraNotes: 1,
      flowGap: const FlowGap(beforePosition: 9, durationMs: 2400),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptDetailsSheet(
            exercise: exercise,
            trace: trace,
            achievedTempoBpm: 58.4,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('1 changed · 1 missing · 1 extra'), findsOneWidget);
    expect(find.text('Longest break · 2.4 s'), findsOneWidget);
    expect(find.text('Pulse'), findsOneWidget);
    expect(find.text('Coordination'), findsOneWidget);
    expect(find.text('58 BPM overall · target 60'), findsOneWidget);
  });
}
