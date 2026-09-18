import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/features/fluency/fluency_screen.dart';
import 'package:keyrecall/features/fluency/fluency_summary.dart';
import 'package:keyrecall/features/fluency/playing_pace_chart.dart';
import 'package:keyrecall/features/fluency/recall_milestones_chart.dart';

void main() {
  setUp(() {
    final handle = TestWidgetsFlutterBinding.instance.ensureSemantics();
    addTearDown(handle.dispose);
  });

  testWidgets('wheel keys have one semantic target and keyboard activation', (
    tester,
  ) async {
    final activated = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: KeyWheel(
              sectors: keySectors(allScales),
              fill: (_) => Colors.blue,
              emptyColor: Colors.white,
              labelStyle: const TextStyle(fontSize: 14),
              describe: (sector) => 'Key ${sector.pitchClass}',
              onTap: (sector, form) => activated.add(sector),
            ),
          ),
        ),
      ),
    );

    for (var index = 0; index < 12; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final label = 'Key ${index * 7 % 12}';
      final target = find.bySemanticsLabel(label);
      expect(target, findsOneWidget);
      expect(
        tester.getSemantics(target).flagsCollection.isFocused,
        Tristate.isTrue,
      );
      final indicator = find.descendant(
        of: target,
        matching: find.byType(DecoratedBox),
      );
      expect(
        (tester.widget<DecoratedBox>(indicator).decoration as BoxDecoration)
            .border,
        isNotNull,
      );
      await tester.sendKeyEvent(
        index.isEven ? LogicalKeyboardKey.enter : LogicalKeyboardKey.space,
      );
      await tester.pump();
      expect(activated.last, index);
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(activated.last, 10);

    final wheel = tester.getRect(find.byType(KeyWheel));
    await tester.tapAt(wheel.center + Offset(0, -wheel.width * 0.15));
    expect(activated.last, 0);
  });

  testWidgets('pace semantics expose old weeks, counts, support, and gaps', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayingPaceChart(
            days: [_day(7), _day(14)],
            today: CalendarDay(2026, 9, 17),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp(r'^Week of ')), findsNWidgets(8));
    expect(
      find.bySemanticsLabel(
        'Week of Sep 7. Right hand: 72 BPM, 1 attempt, Notes previewed. '
        'Left hand: not measured. Together: not measured.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Week of Aug 31. Right hand: not measured. '
        'Left hand: not measured. Together: not measured.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('milestone semantics expose every week including zero counts', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecallMilestonesChart(
            days: [_day(7)],
            materialIds: {'C_MAJOR'},
            today: CalendarDay(2026, 9, 17),
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel(RegExp(r'^Week of ')), findsNWidgets(8));
    expect(
      find.bySemanticsLabel(
        'Week of Sep 7. 0 from memory. 1 notes previewed. 0 with cues.',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Week of Aug 31. 0 from memory. 0 notes previewed. 0 with cues.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pace empty state names the excluded realization', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayingPaceChart(
            days: [_day(14, octaves: 2)],
            today: CalendarDay(2026, 9, 17),
          ),
        ),
      ),
    );
    expect(
      find.text(
        'No measured one-octave, parallel-motion playing pace in the last 8 weeks.',
      ),
      findsOneWidget,
    );
  });
}

FluencyDay _day(int day, {int octaves = 1}) => FluencyDay(
  day: CalendarDay(2026, 9, day),
  attempts: 1,
  demonstrations: {
    'C_MAJOR': Demonstration(
      materialId: 'C_MAJOR',
      level: DemonstrationLevel.notesPreviewed,
      lastAt: DateTime.utc(2026, 9, day),
    ),
  },
  tempos: [
    TempoObservation(
      materialId: 'C_MAJOR',
      hands: HandConfiguration.right,
      handMotion: HandMotion.parallel,
      octaves: octaves,
      guidanceIndependence: 1,
      requestedTempoBpm: 72,
      tempoRatio: 1,
      motorScore: 0.9,
      occurredAt: DateTime.utc(2026, 9, day),
    ),
  ],
);
