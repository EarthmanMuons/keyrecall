import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';

/// Turns a realization into the score a staff draws.
///
/// An adapter and nothing more: every pitch, its spelling, and its order come
/// from [ExerciseRealization], so the staff and the keyboard diagram are two
/// views of one answer to what the exercise asks for.
///
/// Eighth notes in 4/4, with the final tonic held for a quarter, which is how
/// scales are written for practice: an even stream of notes, beamed by beat,
/// arriving somewhere and stopping. The value is presentation and nothing
/// else. What the exercise asks for is an even run of onsets ending on the
/// tonic, and nothing measures how long the last one is held.
///
/// Whether a key signature is written is the caller's to decide and not this
/// layer's, because a signature is itself information: four sharps tell a
/// learner most of E major before they play a note. The cue staff writes one,
/// since it is showing them the scale on purpose. The staff that grows from
/// what they played does not, because by then it would be telling them what
/// they were supposed to have done.

/// Eighth notes in a bar of 4/4, which is the unit the bars are packed in.
const int _eighthsPerMeasure = 8;

/// Quarter notes in a bar, for the transcript, which writes one note a beat.
const int _beatsPerMeasure = 4;

/// How many eighths [duration] takes up.
int _eighthsIn(crisp.NoteDuration duration) {
  final (numerator, denominator) = duration.fraction;
  return numerator * _eighthsPerMeasure ~/ denominator;
}

/// The value the last note is written at, given the [eighths] left in its bar.
///
/// Long enough to finish the bar, so a scale is metrically whole however many
/// notes it has: fourteen eighths leave a quarter, twenty-eight leave a half.
/// The one remainder no single value spells is five eighths, which takes the
/// longest value that fits and leaves the bar short rather than tying a note
/// across a beat nobody is playing.
crisp.NoteDuration _closingDuration(int eighths) => switch (eighths) {
  0 || >= 8 => crisp.NoteDuration.whole,
  7 => const crisp.NoteDuration(crisp.DurationBase.half, dots: 2),
  6 => const crisp.NoteDuration(crisp.DurationBase.half, dots: 1),
  >= 4 => crisp.NoteDuration.half,
  3 => const crisp.NoteDuration(crisp.DurationBase.quarter, dots: 1),
  2 => crisp.NoteDuration.quarter,
  _ => crisp.NoteDuration.eighth,
};

/// [elements] packed into bars that hold [_eighthsPerMeasure] eighths each.
///
/// The last bar runs short wherever the material does not fill one. A scale is
/// as long as it is, and padding it with rests would be writing music nobody
/// asked for.
List<crisp.Measure> _barsOf(List<crisp.NoteElement> elements) {
  final bars = <crisp.Measure>[];
  var bar = <crisp.MusicElement>[];
  var filled = 0;

  for (final element in elements) {
    final eighths = _eighthsIn(element.duration);
    if (filled + eighths > _eighthsPerMeasure) {
      bars.add(crisp.Measure(bar));
      bar = [];
      filled = 0;
    }
    bar.add(element);
    filled += eighths;
  }
  if (bar.isNotEmpty) bars.add(crisp.Measure(bar));
  return bars;
}

const crisp.TimeSignature _fourFour = crisp.TimeSignature(4, 4);

/// No key signature: accidentals are written where they occur.
const crisp.KeySignature _noKeySignature = crisp.KeySignature(0);

/// The id the element for [hand] at [position] is drawn under.
///
/// Stable and derived from the realization, so a later layer that knows where
/// the learner is can color or highlight by moment without this adapter
/// needing to know anything about a performance.
String staffElementId(Hand hand, int position) => '${hand.id}-$position';

/// The staff [hand] reads from.
///
/// Written in [keySignature] when one is given, and with an accidental on
/// every altered note when it is not.
crisp.Score staffScoreFor(
  ExerciseRealization realization,
  Hand hand, {
  List<int?>? fingering,
  crisp.KeySignature? keySignature,
}) {
  final sounded = [
    for (final moment in realization.moments)
      if (moment.noteFor(hand) case final note?) (moment, note),
  ];
  // Arrive and stop: the note the scale ends on is the only one nothing
  // follows, and it is written long enough to finish the bar it lands in.
  final closing = _closingDuration(
    (_eighthsPerMeasure - (sounded.length - 1) % _eighthsPerMeasure) %
        _eighthsPerMeasure,
  );
  final elements = <crisp.NoteElement>[
    for (final (index, (moment, note)) in sounded.indexed)
      crisp.NoteElement.note(
        _pitchOf(note.pitch),
        index == sounded.length - 1 ? closing : crisp.NoteDuration.eighth,
        // Forced only where nothing establishes the accidentals for the
        // reader. Under a signature the engraver decides, which is what puts
        // harmonic minor's raised seventh on the page and leaves the notes the
        // signature already covers alone.
        showAccidental: keySignature != null
            ? null
            : note.pitch.alteration != 0
            ? true
            : null,
        fingerings: switch (fingering?[moment.position]) {
          // A null is a digit deliberately left off, not a missing one.
          null => const <int>[],
          final finger => [finger],
        },
        id: staffElementId(hand, moment.position),
      ),
  ];

  return crisp.Score(
    clef: hand == Hand.left ? crisp.Clef.bass : crisp.Clef.treble,
    keySignature: keySignature ?? _noKeySignature,
    timeSignature: _fourFour,
    measures: _barsOf(elements),
  );
}

/// [score] broken into rows of [measuresPerRow] bars.
///
/// A staff draws one system however long it is, so two octaves runs off the
/// side of a phone. Breaking it into rows here rather than letting a renderer
/// pack them to a width is what makes every row hold the same number of bars,
/// which is what lets them all be drawn at one size.
List<crisp.Score> rowsOf(crisp.Score score, {int measuresPerRow = 2}) => [
  for (var start = 0; start < score.measures.length; start += measuresPerRow)
    _measuresOf(
      score,
      start,
      (start + measuresPerRow).clamp(0, score.measures.length),
    ),
];

/// The pixels per staff space at which [rows] fill [width].
///
/// Read off the widest row so every row fits, and shared by all of them so a
/// trailing half-row is drawn at the size of the rest rather than blown up to
/// the width it happens to have to itself.
///
/// Null before the engraving font's metrics are loaded, since nothing can be
/// measured until they are.
double? fittedStaffSpace(List<crisp.Score> rows, {required double width}) {
  final settings = _layoutSettings();
  if (settings == null || rows.isEmpty) return null;

  const engine = crisp.LayoutEngine();
  final widest = rows
      .map((row) => engine.layout(row, settings).width)
      .reduce((a, b) => a > b ? a : b);
  return widest <= 0 ? null : width / widest;
}

/// The pixels per staff space at which the braced [rows] fill [width].
double? fittedGrandStaffSpace(
  List<crisp.GrandStaff> rows, {
  required double width,
}) {
  final settings = _layoutSettings();
  if (settings == null || rows.isEmpty) return null;

  final widest = rows
      .map(
        (row) =>
            crisp.layoutGrandStaff(row, settings).width +
            crisp.RenderGrandStaffView.braceInset,
      )
      .reduce((a, b) => a > b ? a : b);
  return widest <= 0 ? null : width / widest;
}

crisp.LayoutSettings? _layoutSettings() {
  final metadata = crisp.MusicFonts.metadataOrNull(crisp.MusicFont.bravura);
  return metadata == null ? null : crisp.LayoutSettings(metadata: metadata);
}

/// Both staves, braced together, for an exercise played with both hands.
///
/// Each staff carries its own hand's fingering, which is why a grand staff can
/// show it at all: the digits sit over the notes rather than over the keys two
/// hands share.
crisp.GrandStaff grandStaffFor(
  ExerciseRealization realization, {
  Map<Hand, List<int?>?> fingering = const {},
  crisp.KeySignature? keySignature,
}) => crisp.GrandStaff(
  upper: staffScoreFor(
    realization,
    Hand.right,
    fingering: fingering[Hand.right],
    keySignature: keySignature,
  ),
  lower: staffScoreFor(
    realization,
    Hand.left,
    fingering: fingering[Hand.left],
    keySignature: keySignature,
  ),
);

/// The grand staff broken into rows of [measuresPerRow] bars.
///
/// Rows restate the clefs, which is what a new system does anyway.
List<crisp.GrandStaff> grandStaffRowsFor(
  ExerciseRealization realization, {
  Map<Hand, List<int?>?> fingering = const {},
  int measuresPerRow = 2,
  crisp.KeySignature? keySignature,
}) {
  final whole = grandStaffFor(
    realization,
    fingering: fingering,
    keySignature: keySignature,
  );
  final rows = <crisp.GrandStaff>[];

  for (
    var start = 0;
    start < whole.upper.measures.length;
    start += measuresPerRow
  ) {
    final end = (start + measuresPerRow).clamp(0, whole.upper.measures.length);
    rows.add(
      crisp.GrandStaff(
        upper: _measuresOf(whole.upper, start, end),
        lower: _measuresOf(whole.lower, start, end),
      ),
    );
  }
  return rows;
}

crisp.Score _measuresOf(crisp.Score score, int start, int end) => crisp.Score(
  clef: score.clef,
  keySignature: score.keySignature,
  timeSignature: score.timeSignature,
  measures: score.measures.sublist(start, end),
);

crisp.Pitch _pitchOf(SpelledPitch pitch) => crisp.Pitch(
  switch (pitch.letter) {
    NoteLetter.c => crisp.Step.c,
    NoteLetter.d => crisp.Step.d,
    NoteLetter.e => crisp.Step.e,
    NoteLetter.f => crisp.Step.f,
    NoteLetter.g => crisp.Step.g,
    NoteLetter.a => crisp.Step.a,
    NoteLetter.b => crisp.Step.b,
  },
  alter: pitch.alteration,
  octave: pitch.octave,
);

/// The id the element for the [sequence]th played note is drawn under.
String transcriptElementId(int sequence) => 'played-$sequence';

/// What was played, written out in the order it arrived.
///
/// Not a rhythmic transcription. Each note gets the same value and the same
/// space, because nothing here has decided what a beat was, let alone whether
/// a note fell on one. Bars are there to keep long attempts readable, not to
/// claim a meter.
///
/// Nothing is placed in an expected position, left out, or marked, so the
/// staff says only "this is what arrived".
crisp.Score transcriptScoreFor(
  PerformanceTranscript transcript, {
  required crisp.Clef clef,
}) {
  final elements = <crisp.MusicElement>[
    for (final note in transcript.notes)
      crisp.NoteElement.note(
        _pitchOf(note.pitch),
        crisp.NoteDuration.quarter,
        showAccidental: note.pitch.alteration != 0 ? true : null,
        id: transcriptElementId(note.sequence),
      ),
  ];

  return crisp.Score(
    clef: clef,
    keySignature: _noKeySignature,
    timeSignature: _fourFour,
    measures: [
      if (elements.isEmpty)
        const crisp.Measure([])
      else
        for (var start = 0; start < elements.length; start += _beatsPerMeasure)
          crisp.Measure(
            elements.sublist(
              start,
              (start + _beatsPerMeasure).clamp(0, elements.length),
            ),
          ),
    ],
  );
}
