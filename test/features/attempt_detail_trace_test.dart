import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'package:keyrecall/features/practice/attempt_detail_trace.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  final exercise = Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    direction: ScaleDirection.upDown,
    tempoBpm: 60,
  );
  final expected = [
    for (final moment in realize(exercise).moments)
      moment.noteFor(Hand.right)!.midiNote,
  ];

  PerformanceReading read(List<int> notes, List<int> gaps) {
    var transcript = PerformanceTranscript.empty;
    var timestamp = 0;
    for (final (index, note) in notes.indexed) {
      if (index > 0) timestamp += gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(note, material: material),
        timestampMs: timestamp,
      );
    }
    return readPerformance(exercise: exercise, transcript: transcript);
  }

  test('pulse is interval deviation from the performed median', () {
    final gaps = List<int>.filled(expected.length - 1, 1000)
      ..[0] = 900
      ..[2] = 1100;

    final trace = attemptDetailTraceFor(read(expected, gaps));

    expect(trace.flowGap, isNull);
    expect(trace.pulse[0].position, 1);
    expect(trace.pulse[0].value, 100);
    expect(trace.pulse[2].position, 3);
    expect(trace.pulse[2].value, -100);
  });

  test('a missing realization moment leaves no pulse interval across it', () {
    final played = [...expected]..removeAt(5);
    final gaps = List<int>.filled(played.length - 1, 1000);

    final trace = attemptDetailTraceFor(read(played, gaps));

    expect(trace.notes[5], NoteMomentStatus.missing);
    expect(trace.pulse.map((point) => point.position), isNot(contains(6)));
  });

  test('note departures and the longest break retain traversal positions', () {
    final played = [...expected]..[3] = 66;
    final gaps = List<int>.filled(expected.length - 1, 1000)..[8] = 3200;

    final trace = attemptDetailTraceFor(read(played, gaps));

    expect(trace.notes[3], NoteMomentStatus.departed);
    expect(
      trace.notes.where((note) => note == NoteMomentStatus.matched).length,
      expected.length - 1,
    );
    expect(trace.flowGap?.beforePosition, 9);
    expect(trace.flowGap?.durationMs, 3200);
  });

  test('the pronounced break belongs to flow rather than to pulse', () {
    final gaps = List<int>.filled(expected.length - 1, 1000)..[8] = 3200;

    final trace = attemptDetailTraceFor(read(expected, gaps));

    expect(trace.flowGap?.beforePosition, 9);
    expect(trace.pulse.map((point) => point.position), isNot(contains(9)));
    expect(trace.pulse.map((point) => point.value.abs()), everyElement(0));
  });

  test('repeated notes remain visible as departures', () {
    final played = [...expected]..insert(3, expected[2]);
    final gaps = List<int>.filled(played.length - 1, 1000);

    final trace = attemptDetailTraceFor(read(played, gaps));

    expect(trace.extraNotes, 1);
    final extra = trace.noteDepartures.singleWhere(
      (departure) => departure.kind == NoteDepartureKind.extra,
    );
    expect(extra.noteLabel, 'E');
    expect(extra.position, 1.5);
    expect(extra.beforePosition, 1);
    expect(extra.afterPosition, 2);
    expect(trace.notes, everyElement(NoteMomentStatus.matched));
  });

  test('expected departures retain the material spelling', () {
    final harmonicMinor = Exercise.linear(
      material: TechnicalMaterial('F#', ScaleForm.harmonicMinor),
      hands: HandConfiguration.right,
      direction: ScaleDirection.up,
      tempoBpm: 60,
    );
    final realization = realize(harmonicMinor);
    final played = [
      for (final moment in realization.moments)
        moment.noteFor(Hand.right)!.midiNote,
    ]..removeAt(6);
    var transcript = PerformanceTranscript.empty;
    for (final (index, note) in played.indexed) {
      transcript = transcript.appending(
        pitch: spellObservedPitch(note, material: harmonicMinor.material),
        timestampMs: index * 1000,
      );
    }

    final trace = attemptDetailTraceFor(
      readPerformance(exercise: harmonicMinor, transcript: transcript),
    );
    final missing = trace.noteDepartures.singleWhere(
      (departure) => departure.kind == NoteDepartureKind.missing,
    );

    expect(missing.noteLabel, 'E♯');
  });

  test('coordination is centered with the leading hand above zero', () {
    final handsTogether = Exercise.linear(
      material: material,
      hands: HandConfiguration.together,
      direction: ScaleDirection.up,
      tempoBpm: 60,
    );
    var transcript = PerformanceTranscript.empty;
    for (final (index, moment) in realize(handsTogether).moments.indexed) {
      final onset = index * 1000;
      transcript = transcript
          .appending(
            pitch: moment.noteFor(Hand.left)!.pitch,
            timestampMs: onset,
          )
          .appending(
            pitch: moment.noteFor(Hand.right)!.pitch,
            timestampMs: onset + 20,
          );
    }

    final trace = attemptDetailTraceFor(
      readPerformance(exercise: handsTogether, transcript: transcript),
    );

    expect(trace.coordination, isNotEmpty);
    expect(trace.coordination, everyElement(isA<AttemptTracePoint>()));
    expect(trace.coordination.map((point) => point.value), everyElement(-20));
  });
}
