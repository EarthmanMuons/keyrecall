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

/// The most bars one system can hold before the notes stop being legible.
///
/// Measured rather than looked up. What decides it is the width a bar of this
/// score actually lays out at, which already accounts for how many notes are
/// in it, how wide their accidentals are and what is written over them, so a
/// scale in eighths takes fewer bars to the line than one in quarters without
/// anything here being told about note values.
///
/// [minimumStaffSpace] is the floor a note is still worth reading at, and
/// [cap] is as many bars as a system is ever given however wide the window is.
int barsPerSystem(
  crisp.Score score, {
  required double width,
  required double minimumStaffSpace,
  int cap = 4,
}) {
  for (var bars = cap; bars > 1; bars--) {
    final space = fittedStaffSpace(
      rowsOf(score, measuresPerRow: bars),
      width: width,
    );
    if (space != null && space >= minimumStaffSpace) return bars;
  }
  return 1;
}

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

/// [whole] broken into rows of [measuresPerRow] bars, which is how wide a
/// braced system of that many bars is measured. The engraver does the breaking
/// it draws.
List<crisp.GrandStaff> rowsOfGrandStaff(
  crisp.GrandStaff whole, {
  int measuresPerRow = 2,
}) {
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

/// The most bars a braced system can hold and stay legible.
///
/// [barsPerSystem], for two staves under a brace.
int barsPerBracedSystem(
  crisp.GrandStaff whole, {
  required double width,
  required double minimumStaffSpace,
  int cap = 4,
}) {
  for (var bars = cap; bars > 1; bars--) {
    final space = fittedGrandStaffSpace(
      rowsOfGrandStaff(whole, measuresPerRow: bars),
      width: width,
    );
    if (space != null && space >= minimumStaffSpace) return bars;
  }
  return 1;
}

/// The first [count] bars of [score], for a staff that is not drawing all of
/// them yet.
crisp.Score barsOf(crisp.Score score, int count) =>
    _measuresOf(score, 0, count.clamp(1, score.measures.length));

/// How many bars of a reserved staff are worth drawing for [notes] played.
///
/// The bar being filled, and the next one only once this one is full. What is
/// held open is the width; what is drawn is the part of it somebody has
/// reached, so an attempt does not open on empty bars nobody is in yet.
int barsReachedBy(int notes) => notes ~/ _eighthsPerMeasure + 1;

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

/// The id the [index]th held-open slot on [staff] is drawn under.
///
/// A rest standing in for a note that has not arrived, or for the staff the
/// note that did arrive was not written on. Whoever renders the score draws it
/// in nothing, so what it does is hold the space.
String reservedElementId(int index, {String staff = 'staff'}) =>
    'reserved-$staff-$index';

/// The slots in [score] that are held open rather than played.
Set<String> reservedIds(crisp.Score score) => {
  for (final measure in score.measures)
    for (final element in measure.elements)
      if (element is crisp.RestElement && element.id != null) element.id!,
};

/// The slots in [grandStaff] that are held open rather than played.
Set<String> reservedGrandStaffIds(crisp.GrandStaff grandStaff) => {
  ...reservedIds(grandStaff.upper),
  ...reservedIds(grandStaff.lower),
};

/// What was played, written out in the order it arrived.
///
/// Not a rhythmic transcription. Each note gets the same value and the same
/// space, because nothing here has decided what a beat was, let alone whether
/// a note fell on one. Eighths, and bars of eight, because that is how the
/// exercise was written and this staff stands where that one stood; the value
/// is a size on the page rather than a claim about when anything was played.
/// Nothing lengthens at the end either: what arrived last is only the last
/// thing so far.
///
/// Nothing is placed in an expected position, left out, or marked, so the
/// staff says only "this is what arrived".
crisp.Score transcriptScoreFor(
  PerformanceTranscript transcript, {
  required crisp.Clef clef,
  int reserve = 0,
}) {
  final slots = _slotsFor(transcript, reserve);
  return _transcriptStaff(clef, [
    for (var index = 0; index < slots; index++)
      if (index < transcript.length)
        _playedElement(transcript.notes[index])
      else
        _heldSlot(index),
  ]);
}

/// What was played, written across both staves of a grand staff.
///
/// A note goes to the staff its register belongs to. Which hand played it is
/// not something the input stream says, and it is not what a clef reports
/// either: a grand staff writes low notes low, whoever played them. Every
/// arrival takes a slot on both staves, so a note is written in one and the
/// other holds the space, and nothing is claimed about which arrivals belonged
/// to the same moment.
crisp.GrandStaff transcriptGrandStaffFor(
  PerformanceTranscript transcript, {
  required int splitMidiNote,
  int reserve = 0,
}) {
  final slots = _slotsFor(transcript, reserve);
  final upper = <crisp.MusicElement>[];
  final lower = <crisp.MusicElement>[];

  for (var index = 0; index < slots; index++) {
    final note = index < transcript.length ? transcript.notes[index] : null;
    final treble = note != null && note.midiNote >= splitMidiNote;
    upper.add(
      note != null && treble
          ? _playedElement(note)
          : _heldSlot(index, staff: 'treble'),
    );
    lower.add(
      note != null && !treble
          ? _playedElement(note)
          : _heldSlot(index, staff: 'bass'),
    );
  }

  return crisp.GrandStaff(
    upper: _transcriptStaff(crisp.Clef.treble, upper),
    lower: _transcriptStaff(crisp.Clef.bass, lower),
  );
}

/// The register a played note is written in the treble staff from.
///
/// Halfway between the top of what the left hand was asked for and the bottom
/// of what the right hand was, so what each hand was asked for lands on the
/// staff it was written on. Where the two meet on one pitch that pitch goes
/// above, which is where a reader looks for middle C. Middle C too where the
/// exercise does not say.
int registerSplitFor(ExerciseRealization realization) {
  var leftTop = -1;
  var rightBottom = 1 << 20;
  for (final moment in realization.moments) {
    if (moment.noteFor(Hand.left) case final note?) {
      if (note.midiNote > leftTop) leftTop = note.midiNote;
    }
    if (moment.noteFor(Hand.right) case final note?) {
      if (note.midiNote < rightBottom) rightBottom = note.midiNote;
    }
  }
  if (leftTop < 0 || rightBottom > 1 << 19) return _middleC;
  return (leftTop + rightBottom + 1) ~/ 2;
}

const int _middleC = 60;

/// Whole bars, enough for what the exercise asks for or for what arrived when
/// that is more. The staff is the size it is going to be before anything is
/// played, so notes land in it rather than stretching it a note at a time, and
/// somebody who plays extra ones is given another bar rather than another
/// note's width.
int _slotsFor(PerformanceTranscript transcript, int reserve) {
  final slots = transcript.length > reserve ? transcript.length : reserve;
  return (slots / _eighthsPerMeasure).ceil().clamp(1, slots + 1) *
      _eighthsPerMeasure;
}

crisp.NoteElement _playedElement(PlayedNote note) => crisp.NoteElement.note(
  _pitchOf(note.pitch),
  crisp.NoteDuration.eighth,
  showAccidental: note.pitch.alteration != 0 ? true : null,
  id: transcriptElementId(note.sequence),
);

crisp.RestElement _heldSlot(int index, {String staff = 'staff'}) =>
    crisp.RestElement(
      crisp.NoteDuration.eighth,
      id: reservedElementId(index, staff: staff),
    );

crisp.Score _transcriptStaff(
  crisp.Clef clef,
  List<crisp.MusicElement> elements,
) => crisp.Score(
  clef: clef,
  keySignature: _noKeySignature,
  timeSignature: _fourFour,
  measures: [
    for (var start = 0; start < elements.length; start += _eighthsPerMeasure)
      crisp.Measure(
        elements.sublist(
          start,
          (start + _eighthsPerMeasure).clamp(0, elements.length),
        ),
      ),
  ],
);

/// The first [count] bars of [grandStaff], for a system that is not drawing
/// all of them yet.
crisp.GrandStaff barsOfGrandStaff(crisp.GrandStaff grandStaff, int count) =>
    crisp.GrandStaff(
      upper: barsOf(grandStaff.upper, count),
      lower: barsOf(grandStaff.lower, count),
    );
