import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';

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
/// An adapter and nothing more: every pitch, its spelling, and its order come
/// from [realization], so the staff and the keyboard diagram are two views of
/// one answer to what the exercise asks for.
///
/// Eighth notes in 4/4, with the final tonic held for a quarter, which is how
/// scales are written for practice. The value is presentation only: what the
/// exercise asks for is an even run of onsets ending on the tonic, and nothing
/// measures how long the last one is held.
///
/// Written in [keySignature] when one is given, and with an accidental on every
/// altered note when it is not. Whether to write one is the caller's decision,
/// because a signature is itself information: four sharps tell a learner most
/// of E major before they play a note.
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

/// The staff spaces, in logical pixels, a staff may be drawn at.
class StaffSpaceBounds {
  const StaffSpaceBounds({
    required this.minimum,
    required this.readable,
    required this.largest,
  });

  /// Where a staff stops being drawn any smaller whatever it costs.
  final double minimum;

  /// The smallest a staff is comfortably read at. A system that would fall
  /// below it gives up a bar, and then tightens its note spacing, first.
  final double readable;

  /// The largest a staff is drawn. One with room to spare spreads its notes
  /// to the width instead.
  final double largest;
}

/// How a staff fills a width: the bars to a system it was measured at, its
/// pixels per staff space, and the stretch on its note spacing.
typedef StaffFit = ({
  int barsPerSystem,
  double staffSpace,
  double spacingStretch,
});

/// How [score] fills [width] within [bounds].
///
/// Measured rather than looked up. What decides it is the width a bar of this
/// score actually lays out at, which already accounts for how many notes are
/// in it, how wide their accidentals are and what is written over them, so a
/// scale in eighths takes fewer bars to the line than one in quarters without
/// anything here being told about note values. Every row is measured and the
/// widest decides, so a trailing half-row is drawn at the size of the rest.
///
/// The time signature is left off: every exercise is in 4/4, as a scale book
/// leaves unsaid.
///
/// Null before the engraving font's metrics are loaded, since nothing can be
/// measured until they are.
StaffFit? fitStaff(
  crisp.Score score, {
  required double width,
  required StaffSpaceBounds bounds,
}) {
  final settings = _layoutSettings();
  if (settings == null || score.measures.isEmpty) return null;

  const engine = crisp.LayoutEngine();
  return _fit(
    width: width,
    bounds: bounds,
    widestAt: (bars) {
      final rows = rowsOf(score, measuresPerRow: bars);
      return (stretch) => _widest(
        rows.map(
          (row) => engine
              .layout(
                row,
                settings,
                spacingStretch: stretch,
                drawTimeSignature: false,
              )
              .width,
        ),
      );
    },
  );
}

/// How the braced [grandStaff] fills [width] within [bounds].
///
/// [width] runs from the systems' start line. The brace hangs in the margin
/// to its left, as engraved music sets it.
StaffFit? fitGrandStaff(
  crisp.GrandStaff grandStaff, {
  required double width,
  required StaffSpaceBounds bounds,
}) {
  final settings = _layoutSettings();
  if (settings == null || grandStaff.upper.measures.isEmpty) return null;

  return _fit(
    width: width,
    bounds: bounds,
    widestAt: (bars) {
      final rows = rowsOfGrandStaff(grandStaff, measuresPerRow: bars);
      return (stretch) => _widest(
        rows.map(
          (row) => crisp
              .layoutGrandStaff(
                row,
                settings,
                spacingStretch: stretch,
                drawTimeSignature: false,
              )
              .width,
        ),
      );
    },
  );
}

/// As many bars as a system is ever given however wide the window is.
const int _barsPerSystemCap = 4;

/// The tightest note spacing a crowded bar is drawn at before its staff is
/// drawn smaller. The engraver still keeps a gap after every note's ink.
const double _tightestSpacingStretch = 0.75;

/// The widest note spacing a short exercise is spread to.
const double _widestSpacingStretch = 4;

/// The fit for the most bars to a system that stays readable, given the width
/// in staff spaces of the widest row of `bars` bars at a spacing stretch.
StaffFit _fit({
  required double width,
  required StaffSpaceBounds bounds,
  required double Function(double stretch) Function(int bars) widestAt,
}) {
  for (var bars = _barsPerSystemCap; bars >= 1; bars--) {
    final widthAt = widestAt(bars);
    final natural = width / widthAt(1);
    if (natural >= bounds.largest) {
      return (
        barsPerSystem: bars,
        staffSpace: bounds.largest,
        spacingStretch: _largestStretchWithin(
          width / bounds.largest,
          widthAt,
          from: 1,
          to: _widestSpacingStretch,
        ),
      );
    }
    if (natural >= bounds.readable) {
      return (barsPerSystem: bars, staffSpace: natural, spacingStretch: 1);
    }
    if (bars > 1) continue;

    final tightest = width / widthAt(_tightestSpacingStretch);
    if (tightest < bounds.readable) {
      return (
        barsPerSystem: 1,
        staffSpace: tightest < bounds.minimum ? bounds.minimum : tightest,
        spacingStretch: _tightestSpacingStretch,
      );
    }
    return (
      barsPerSystem: 1,
      staffSpace: bounds.readable,
      spacingStretch: _largestStretchWithin(
        width / bounds.readable,
        widthAt,
        from: _tightestSpacingStretch,
        to: 1,
      ),
    );
  }
  throw StateError('a system always holds at least one bar');
}

/// The largest stretch between [from] and [to] whose [widthAt] stays within
/// [target].
double _largestStretchWithin(
  double target,
  double Function(double stretch) widthAt, {
  required double from,
  required double to,
}) {
  if (widthAt(to) <= target) return to;
  var fits = from;
  var overflows = to;
  for (var step = 0; step < 12; step++) {
    final middle = (fits + overflows) / 2;
    if (widthAt(middle) <= target) {
      fits = middle;
    } else {
      overflows = middle;
    }
  }
  return fits;
}

double _widest(Iterable<double> widths) =>
    widths.reduce((a, b) => a > b ? a : b);

crisp.LayoutSettings? _layoutSettings() {
  final metadata = crisp.MusicFonts.metadataOrNull(crisp.MusicFont.bravura);
  return metadata == null
      ? null
      : crisp.LayoutSettings(
          metadata: metadata,
          fingeringPlacement: crisp.FingeringPlacement.outsideStaff,
        );
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
/// Opposite-register arrivals that timing leans toward reading together share
/// a slot. Notes in one register stay successive however close they arrive, so
/// independent movement within a hand remains visible.
crisp.GrandStaff transcriptGrandStaffFor(
  PerformanceTranscript transcript, {
  required int splitMidiNote,
  int reserve = 0,
}) {
  final playedSlots = _grandStaffSlotsFor(transcript, splitMidiNote);
  final slots = _reservedSlots(playedSlots.length, reserve);
  final upperElements = <crisp.MusicElement>[];
  final lowerElements = <crisp.MusicElement>[];

  for (var index = 0; index < slots; index++) {
    final slot = index < playedSlots.length ? playedSlots[index] : null;
    upperElements.add(switch (slot?.upper) {
      final note? => _playedElement(note),
      null => _heldSlot(index, staff: 'treble'),
    });
    lowerElements.add(switch (slot?.lower) {
      final note? => _playedElement(note),
      null => _heldSlot(index, staff: 'bass'),
    });
  }

  return crisp.GrandStaff(
    upper: _transcriptStaff(crisp.Clef.treble, upperElements),
    lower: _transcriptStaff(crisp.Clef.bass, lowerElements),
  );
}

/// How many horizontal slots [transcript] has reached on a grand staff.
int grandStaffSlotsReachedBy(
  PerformanceTranscript transcript, {
  required int splitMidiNote,
}) => _grandStaffSlotsFor(transcript, splitMidiNote).length;

List<({PlayedNote? upper, PlayedNote? lower})> _grandStaffSlotsFor(
  PerformanceTranscript transcript,
  int splitMidiNote,
) {
  final slots = <({PlayedNote? upper, PlayedNote? lower})>[];
  final boundaries = groupObservations(transcript: transcript).boundaries;
  const groupingPolicy = ObservationGroupingPolicy.standard;
  final sharedSlotLimitMs =
      (groupingPolicy.confidentlySameMs +
          groupingPolicy.confidentlySeparateMs) ~/
      2;

  for (final (index, note) in transcript.notes.indexed) {
    final upper = note.midiNote >= splitMidiNote;
    final previous = slots.lastOrNull;
    final joinsPrevious =
        previous != null &&
        boundaries[index - 1].gapMs <= sharedSlotLimitMs &&
        (upper ? previous.upper == null : previous.lower == null);

    if (joinsPrevious) {
      slots[slots.length - 1] = (
        upper: upper ? note : previous.upper,
        lower: upper ? previous.lower : note,
      );
    } else {
      slots.add((upper: upper ? note : null, lower: upper ? null : note));
    }
  }
  return slots;
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
  return _reservedSlots(transcript.length, reserve);
}

int _reservedSlots(int played, int reserve) {
  final slots = played > reserve ? played : reserve;
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
