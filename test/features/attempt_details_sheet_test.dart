import 'package:fl_chart/fl_chart.dart';
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
        AttemptTracePoint(position: 5, value: 10),
        AttemptTracePoint(position: 6, value: 5),
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
      noteDepartures: const [
        NoteDeparture(
          kind: NoteDepartureKind.changed,
          noteLabel: 'B',
          position: 13,
        ),
        NoteDeparture(
          kind: NoteDepartureKind.missing,
          noteLabel: 'C',
          position: 14,
        ),
        NoteDeparture(
          kind: NoteDepartureKind.extra,
          noteLabel: 'F♯',
          position: 3.5,
          beforePosition: 3,
          afterPosition: 4,
        ),
      ],
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
    expect(find.text('Changed: B on the way down'), findsOneWidget);
    expect(find.text('Missing: C at the end'), findsOneWidget);
    expect(
      find.text('Extra: F♯ between F and G on the way up'),
      findsOneWidget,
    );
    expect(
      find.text('Longest break · 2.4 s before A on the way down'),
      findsOneWidget,
    );
    expect(find.text('PULSE'), findsOneWidget);
    expect(
      find.text(
        "How early or late the spacing between notes fell around this run's pulse. "
        'Largest deviation: 30 ms.',
      ),
      findsOneWidget,
    );
    expect(find.text('COORDINATION'), findsOneWidget);
    expect(
      find.text('How far apart the hands arrived. Furthest apart: 12 ms.'),
      findsOneWidget,
    );
    expect(find.text('58 BPM overall · target 60'), findsOneWidget);
    final pulse = tester.widget<LineChart>(find.byType(LineChart).first);
    expect(pulse.data.lineBarsData, hasLength(2));
    expect(pulse.data.minX, closeTo(-0.21, 0.001));
    expect(pulse.data.maxX, closeTo(14.21, 0.001));
    expect(pulse.data.extraLinesData.verticalLines.single.x, 7);
    expect(pulse.data.extraLinesData.verticalLines.single.dashArray, [4, 4]);
  });

  testWidgets('details summarize a missing suffix', (tester) async {
    final suffixExercise = Exercise.linear(
      material: TechnicalMaterial('A', ScaleForm.naturalMinor),
      hands: HandConfiguration.together,
      direction: ScaleDirection.upDown,
      tempoBpm: 104,
    );
    final realization = realize(suffixExercise);
    final missing = [
      for (final moment in realization.moments.skip(8))
        for (final note in moment.notes)
          NoteDeparture(
            kind: NoteDepartureKind.missing,
            noteLabel: note.pitch.prettyLabel,
            position: moment.position.toDouble(),
          ),
    ];
    final trace = AttemptDetailTrace(
      momentCount: realization.moments.length,
      pulse: const [],
      coordination: const [],
      notes: [
        ...List.filled(8, NoteMomentStatus.matched),
        ...List.filled(7, NoteMomentStatus.missing),
      ],
      noteDepartures: missing,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptDetailsSheet(
            exercise: suffixExercise,
            trace: trace,
            achievedTempoBpm: 104,
          ),
        ),
      ),
    );

    expect(find.text('14 missing'), findsOneWidget);
    expect(
      find.text('Missing: G at the turn and everything after it'),
      findsOneWidget,
    );
    expect(find.textContaining('F on the way down'), findsNothing);
  });

  testWidgets('details summarize an internal run and isolated misses', (
    tester,
  ) async {
    final realization = realize(exercise);
    final positions = [1, 2, 3, 6];
    final trace = AttemptDetailTrace(
      momentCount: realization.moments.length,
      pulse: const [],
      coordination: const [],
      notes: [
        for (
          var position = 0;
          position < realization.moments.length;
          position++
        )
          positions.contains(position)
              ? NoteMomentStatus.missing
              : NoteMomentStatus.matched,
      ],
      noteDepartures: [
        for (final position in positions)
          NoteDeparture(
            kind: NoteDepartureKind.missing,
            noteLabel:
                realization.moments[position].notes.first.pitch.prettyLabel,
            position: position.toDouble(),
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptDetailsSheet(
            exercise: exercise,
            trace: trace,
            achievedTempoBpm: 60,
          ),
        ),
      ),
    );

    expect(
      find.text('Missing: D through F on the way up, B at the turn'),
      findsOneWidget,
    );
  });

  testWidgets('details cap long lists of separate locations', (tester) async {
    final realization = realize(exercise);
    final positions = [1, 3, 5, 10];
    final trace = AttemptDetailTrace(
      momentCount: realization.moments.length,
      pulse: const [],
      coordination: const [],
      notes: [
        for (
          var position = 0;
          position < realization.moments.length;
          position++
        )
          positions.contains(position)
              ? NoteMomentStatus.departed
              : NoteMomentStatus.matched,
      ],
      noteDepartures: [
        for (final position in positions)
          NoteDeparture(
            kind: NoteDepartureKind.changed,
            noteLabel:
                realization.moments[position].notes.first.pitch.prettyLabel,
            position: position.toDouble(),
          ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttemptDetailsSheet(
            exercise: exercise,
            trace: trace,
            achievedTempoBpm: 60,
          ),
        ),
      ),
    );

    expect(find.text('4 changed'), findsOneWidget);
    expect(
      find.text(
        'Changed: D on the way up, F on the way up, and 2 more locations',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('A on the way up'), findsNothing);
  });
}
