import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_measurement/keyrecall_measurement.dart';

/// One performance of one exercise, by name.
Map<String, (Exercise, PerformanceTranscript)> singleHandCases() {
  final cases = <String, (Exercise, PerformanceTranscript)>{};

  final exercises = <String, Exercise>{
    'rh-up': Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
      direction: ScaleDirection.up,
    ),
    'rh-up-down': Exercise.linear(
      material: TechnicalMaterial('C', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 1,
    ),
    'lh-harmonic-minor': Exercise.linear(
      material: TechnicalMaterial('A', ScaleForm.harmonicMinor),
      hands: HandConfiguration.left,
      octaves: 1,
      direction: ScaleDirection.up,
    ),
    'rh-two-octaves': Exercise.linear(
      material: TechnicalMaterial('Bb', ScaleForm.major),
      hands: HandConfiguration.right,
      octaves: 2,
      direction: ScaleDirection.up,
    ),
  };

  List<int> notesOf(Exercise exercise) {
    final realization = realize(exercise);
    return [
      for (final moment in realization.moments) moment.notes.single.midiNote,
    ];
  }

  PerformanceTranscript played(
    Exercise exercise,
    List<int> midiNotes, {
    List<int>? gaps,
  }) {
    var transcript = PerformanceTranscript.empty;
    var at = 1000;
    for (final (index, midiNote) in midiNotes.indexed) {
      if (index > 0) at += gaps == null ? 500 : gaps[index - 1];
      transcript = transcript.appending(
        pitch: spellObservedPitch(midiNote, material: exercise.material),
        timestampMs: at,
      );
    }
    return transcript;
  }

  /// The performances every exercise is put through.
  ///
  /// [gaps] is the wait before each note after the first; a null gap list is
  /// steady playing.
  final deviations = <String, (List<int>, List<int>?) Function(List<int>)>{
    'clean': (notes) => (notes, null),
    'clean-uneven': (notes) => (
      notes,
      [for (var i = 0; i < notes.length - 1; i++) i.isEven ? 300 : 700],
    ),
    'clean-with-pause': (notes) => (
      notes,
      [for (var i = 0; i < notes.length - 1; i++) i == 3 ? 2500 : 500],
    ),
    'nothing-played': (notes) => (const [], null),
    'wrong-note': (notes) => (
      [for (final (index, note) in notes.indexed) index == 4 ? note + 1 : note],
      null,
    ),
    'octave-slip': (notes) => (
      [
        for (final (index, note) in notes.indexed)
          index == 4 ? note - 12 : note,
      ],
      null,
    ),
    'repeated-note': (notes) =>
        ([...notes.take(4), notes[3], ...notes.skip(4)], null),
    'extra-note': (notes) =>
        ([...notes.take(4), notes[3] + 1, ...notes.skip(4)], null),
    'skipped-note': (notes) => (
      [
        for (final (index, note) in notes.indexed)
          if (index != 4) note,
      ],
      null,
    ),
    'stopped-halfway': (notes) =>
        (notes.take(notes.length ~/ 2).toList(), null),
    'restarted': (notes) => ([...notes.take(3), ...notes], null),
    'all-wrong': (notes) =>
        ([for (var i = 0; i < notes.length; i++) notes.first + 1 + i], null),
  };

  const exhaustive = 'rh-up';
  const elsewhere = [
    'clean',
    'wrong-note',
    'octave-slip',
    'repeated-note',
    'skipped-note',
    'restarted',
  ];

  for (final exerciseEntry in exercises.entries) {
    for (final deviation in deviations.entries) {
      if (exerciseEntry.key != exhaustive &&
          !elsewhere.contains(deviation.key)) {
        continue;
      }
      final exercise = exerciseEntry.value;
      final (midiNotes, gaps) = deviation.value(notesOf(exercise));
      cases['${exerciseEntry.key} ${deviation.key}'] = (
        exercise,
        played(exercise, midiNotes, gaps: gaps),
      );
    }
  }
  return cases;
}

/// What single-hand alignment and measurement produce, pinned.
///
/// Every case renders the whole observable surface of one performance: the
/// edit script, the readings taken off it, and every number measurement
/// derives. A change to any of them shows up here as a changed line.
///
/// Hands-together material extends the script rather than replacing it, so
/// these lines must survive that work unchanged. A single-hand line that moves
/// means the representation is wrong, not that the line was.
void main() {
  for (final entry in singleHandCases().entries) {
    test(entry.key, () {
      final (exercise, transcript) = entry.value;
      expect(
        renderPin(exercise: exercise, transcript: transcript),
        singleHandPins[entry.key],
      );
    });
  }
}

/// The whole observable surface of one performance, as one line.
String renderPin({
  required Exercise exercise,
  required PerformanceTranscript transcript,
}) {
  final measurement = measure(
    realization: realize(exercise),
    transcript: transcript,
  );
  final reading = measurement.reading;

  final script = [
    for (final (:realizationPosition, :edit) in measurement.alignment.noteEdits)
      switch (edit) {
        Match(:final observedSequence) =>
          'M$realizationPosition<$observedSequence',
        Substitution(
          :final observedSequence,
          :final expected,
          :final observed,
          :final kind,
        ) =>
          'S$realizationPosition<$observedSequence'
              ':${expected.label}>${observed.label}:${kind.id}',
        Insertion(:final observedSequence, :final observed) =>
          'I<$observedSequence:${observed.label}',
        Deletion(:final expected) => 'D$realizationPosition:${expected.label}',
      },
  ].join(' ');

  final departure = switch (reading.firstDeparture) {
    null => '-',
    AtExpectedPosition(:final position) => 'at$position',
    BeforeExpectedPosition(:final position) => 'before$position',
    AfterRealization() => 'after',
  };

  String ratio(double value) => value.toStringAsFixed(6);
  String orDash(num? value) => value == null ? '-' : '$value';

  return [
    script,
    '${reading.matched}/${reading.substituted}/${reading.inserted}'
        '/${reading.deleted}',
    'complete=${reading.isComplete} clean=${reading.isFirstPassClean} '
        'repairs=${reading.immediateRepairs} final='
        '${reading.reachedFinalPosition} first=$departure',
    'started=${measurement.started} completed=${measurement.completed} '
        'retrieved=${measurement.retrievedIndependently}',
    '${measurement.materialProduced}/${measurement.expectedNotes} '
        'sounded=${measurement.soundedCorrectly} '
        'degrees=${measurement.degreesCorrect} '
        'repeats=${measurement.repeats} '
        'intrusions=${measurement.intrusions}',
    '${ratio(measurement.materialAppeared)} '
        '${ratio(measurement.pitchIntegrity)} '
        '${ratio(measurement.topologyAccuracy)} '
        '${ratio(measurement.continuity)} '
        '${ratio(measurement.temporalStability)} '
        '${ratio(measurement.achievedTempoRatioFor(exercise.conditions))}',
    '${orDash(measurement.dispersion)} ${orDash(measurement.worstIntervalRatio)}'
        ' ${orDash(measurement.medianIntervalMs)}',
    'cost=${measurement.alignment.cost}',
  ].join(' | ');
}

/// One line per case, from the implementation that produced them.
///
/// A failure prints the line the run produced, which is what a
/// deliberate change is updated from.
const Map<String, String> singleHandPins = {
  'rh-up clean':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 | 8/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=0',
  'rh-up clean-uneven':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 | 8/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 1.000000 0.000000 2.500000 | 1.3333333333333333 1.0 300 | cost=0',
  'rh-up clean-with-pause':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 | 8/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 0.000000 1.000000 1.500000 | 0.0 5.0 500 | cost=0',
  'rh-up nothing-played':
      'D0:C D1:D D2:E D3:F D4:G D5:A D6:B D7:C | 0/0/0/8 | complete=false clean=false repairs=0 final=false first=at0 | started=false completed=false retrieved=false | 0/8 sounded=0 degrees=0 repeats=0 intrusions=0 | 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000 | - - - | cost=24',
  'rh-up wrong-note':
      'M0<0 M1<1 M2<2 M3<3 S4<4:G>G#:PITCH M5<5 M6<6 M7<7 | 7/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=false | 7/8 sounded=7 degrees=7 repeats=0 intrusions=0 | 0.875000 0.875000 0.875000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-up octave-slip':
      'M0<0 M1<1 M2<2 M3<3 S4<4:G>G:REGISTER M5<5 M6<6 M7<7 | 7/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=true | 8/8 sounded=7 degrees=8 repeats=0 intrusions=0 | 1.000000 0.875000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-up repeated-note':
      'M0<0 M1<1 M2<2 I<3:F M3<4 M4<5 M5<6 M6<7 M7<8 | 8/0/1/0 | complete=true clean=false repairs=1 final=true first=before3 | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=1 intrusions=0 | 1.000000 0.888889 1.000000 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=3',
  'rh-up extra-note':
      'M0<0 M1<1 M2<2 M3<3 I<4:F# M4<5 M5<6 M6<7 M7<8 | 8/0/1/0 | complete=true clean=false repairs=1 final=true first=before4 | started=true completed=true retrieved=false | 8/8 sounded=8 degrees=8 repeats=0 intrusions=1 | 1.000000 0.888889 0.888889 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=3',
  'rh-up skipped-note':
      'M0<0 M1<1 M2<2 M3<3 D4:G M5<4 M6<5 M7<6 | 7/0/0/1 | complete=false clean=false repairs=0 final=true first=at4 | started=true completed=false retrieved=false | 7/8 sounded=7 degrees=7 repeats=0 intrusions=0 | 0.875000 0.875000 0.875000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=3',
  'rh-up stopped-halfway':
      'M0<0 M1<1 M2<2 M3<3 D4:G D5:A D6:B D7:C | 4/0/0/4 | complete=false clean=false repairs=0 final=false first=at4 | started=true completed=false retrieved=false | 4/8 sounded=4 degrees=4 repeats=0 intrusions=0 | 0.500000 0.500000 0.500000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=12',
  'rh-up restarted':
      'I<0:C I<1:D I<2:E M0<3 M1<4 M2<5 M3<6 M4<7 M5<8 M6<9 M7<10 | 8/0/3/0 | complete=true clean=false repairs=1 final=true first=before0 | started=true completed=true retrieved=false | 8/8 sounded=8 degrees=8 repeats=0 intrusions=3 | 1.000000 0.727273 0.727273 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=9',
  'rh-up all-wrong':
      'S0<0:C>C#:PITCH M1<1 I<2:D# M2<3 M3<4 S4<5:G>F#:PITCH S5<6:A>G:PITCH S6<7:B>G#:PITCH D7:C | 3/4/1/1 | complete=false clean=false repairs=1 final=false first=at0 | started=true completed=false retrieved=false | 3/8 sounded=3 degrees=3 repeats=0 intrusions=1 | 0.375000 0.333333 0.333333 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=14',
  'rh-up-down clean':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 15/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 15/15 sounded=15 degrees=15 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=0',
  'rh-up-down wrong-note':
      'M0<0 M1<1 M2<2 M3<3 S4<4:G>G#:PITCH M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 14/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=false | 14/15 sounded=14 degrees=14 repeats=0 intrusions=0 | 0.933333 0.933333 0.933333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-up-down octave-slip':
      'M0<0 M1<1 M2<2 M3<3 S4<4:G>G:REGISTER M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 14/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=true | 15/15 sounded=14 degrees=15 repeats=0 intrusions=0 | 1.000000 0.933333 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-up-down repeated-note':
      'M0<0 M1<1 M2<2 I<3:F M3<4 M4<5 M5<6 M6<7 M7<8 M8<9 M9<10 M10<11 M11<12 M12<13 M13<14 M14<15 | 15/0/1/0 | complete=true clean=false repairs=1 final=true first=before3 | started=true completed=true retrieved=true | 15/15 sounded=15 degrees=15 repeats=1 intrusions=0 | 1.000000 0.937500 1.000000 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=3',
  'rh-up-down skipped-note':
      'M0<0 M1<1 M2<2 M3<3 D4:G M5<4 M6<5 M7<6 M8<7 M9<8 M10<9 M11<10 M12<11 M13<12 M14<13 | 14/0/0/1 | complete=false clean=false repairs=0 final=true first=at4 | started=true completed=false retrieved=false | 14/15 sounded=14 degrees=14 repeats=0 intrusions=0 | 0.933333 0.933333 0.933333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=3',
  'rh-up-down restarted':
      'I<0:C I<1:D I<2:E M0<3 M1<4 M2<5 M3<6 M4<7 M5<8 M6<9 M7<10 M8<11 M9<12 M10<13 M11<14 M12<15 M13<16 M14<17 | 15/0/3/0 | complete=true clean=false repairs=1 final=true first=before0 | started=true completed=true retrieved=false | 15/15 sounded=15 degrees=15 repeats=0 intrusions=3 | 1.000000 0.833333 0.833333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=9',
  'lh-harmonic-minor clean':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 | 8/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=0',
  'lh-harmonic-minor wrong-note':
      'M0<0 M1<1 M2<2 M3<3 S4<4:E>F:PITCH M5<5 M6<6 M7<7 | 7/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=false | 7/8 sounded=7 degrees=7 repeats=0 intrusions=0 | 0.875000 0.875000 0.875000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'lh-harmonic-minor octave-slip':
      'M0<0 M1<1 M2<2 M3<3 S4<4:E>E:REGISTER M5<5 M6<6 M7<7 | 7/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=true | 8/8 sounded=7 degrees=8 repeats=0 intrusions=0 | 1.000000 0.875000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'lh-harmonic-minor repeated-note':
      'M0<0 M1<1 M2<2 I<3:D M3<4 M4<5 M5<6 M6<7 M7<8 | 8/0/1/0 | complete=true clean=false repairs=1 final=true first=before3 | started=true completed=true retrieved=true | 8/8 sounded=8 degrees=8 repeats=1 intrusions=0 | 1.000000 0.888889 1.000000 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=3',
  'lh-harmonic-minor skipped-note':
      'M0<0 M1<1 M2<2 M3<3 D4:E M5<4 M6<5 M7<6 | 7/0/0/1 | complete=false clean=false repairs=0 final=true first=at4 | started=true completed=false retrieved=false | 7/8 sounded=7 degrees=7 repeats=0 intrusions=0 | 0.875000 0.875000 0.875000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=3',
  'lh-harmonic-minor restarted':
      'I<0:A I<1:B I<2:C M0<3 M1<4 M2<5 M3<6 M4<7 M5<8 M6<9 M7<10 | 8/0/3/0 | complete=true clean=false repairs=1 final=true first=before0 | started=true completed=true retrieved=false | 8/8 sounded=8 degrees=8 repeats=0 intrusions=3 | 1.000000 0.727273 0.727273 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=9',
  'rh-two-octaves clean':
      'M0<0 M1<1 M2<2 M3<3 M4<4 M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 15/0/0/0 | complete=true clean=true repairs=0 final=true first=- | started=true completed=true retrieved=true | 15/15 sounded=15 degrees=15 repeats=0 intrusions=0 | 1.000000 1.000000 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=0',
  'rh-two-octaves wrong-note':
      'M0<0 M1<1 M2<2 M3<3 S4<4:F>Gb:PITCH M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 14/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=false | 14/15 sounded=14 degrees=14 repeats=0 intrusions=0 | 0.933333 0.933333 0.933333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-two-octaves octave-slip':
      'M0<0 M1<1 M2<2 M3<3 S4<4:F>F:REGISTER M5<5 M6<6 M7<7 M8<8 M9<9 M10<10 M11<11 M12<12 M13<13 M14<14 | 14/1/0/0 | complete=true clean=false repairs=0 final=true first=at4 | started=true completed=true retrieved=true | 15/15 sounded=14 degrees=15 repeats=0 intrusions=0 | 1.000000 0.933333 1.000000 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=2',
  'rh-two-octaves repeated-note':
      'M0<0 M1<1 M2<2 I<3:Eb M3<4 M4<5 M5<6 M6<7 M7<8 M8<9 M9<10 M10<11 M11<12 M12<13 M13<14 M14<15 | 15/0/1/0 | complete=true clean=false repairs=1 final=true first=before3 | started=true completed=true retrieved=true | 15/15 sounded=15 degrees=15 repeats=1 intrusions=0 | 1.000000 0.937500 1.000000 0.540541 1.000000 1.500000 | 0.0 2.0 500 | cost=3',
  'rh-two-octaves skipped-note':
      'M0<0 M1<1 M2<2 M3<3 D4:F M5<4 M6<5 M7<6 M8<7 M9<8 M10<9 M11<10 M12<11 M13<12 M14<13 | 14/0/0/1 | complete=false clean=false repairs=0 final=true first=at4 | started=true completed=false retrieved=false | 14/15 sounded=14 degrees=14 repeats=0 intrusions=0 | 0.933333 0.933333 0.933333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=3',
  'rh-two-octaves restarted':
      'I<0:Bb I<1:C I<2:D M0<3 M1<4 M2<5 M3<6 M4<7 M5<8 M6<9 M7<10 M8<11 M9<12 M10<13 M11<14 M12<15 M13<16 M14<17 | 15/0/3/0 | complete=true clean=false repairs=1 final=true first=before0 | started=true completed=true retrieved=false | 15/15 sounded=15 degrees=15 repeats=0 intrusions=3 | 1.000000 0.833333 0.833333 1.000000 1.000000 1.500000 | 0.0 1.0 500 | cost=9',
};
