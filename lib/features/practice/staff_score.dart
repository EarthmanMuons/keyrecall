import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';

/// Turns a realization into the score a staff draws.
///
/// An adapter and nothing more: every pitch, its spelling, and its order come
/// from [ExerciseRealization], so the staff and the keyboard diagram are two
/// views of one answer to what the exercise asks for.
///
/// V1 draws quarter notes in 4/4 with no key signature and an accidental on
/// every altered note. That is deliberately plain rather than idiomatic: a key
/// signature is itself a cue, since four sharps tell a learner most of E major
/// before they play a note, so which attempts get one is a policy question
/// this layer should not answer by default.

/// Beats in a bar. One moment to a beat, so also moments in a bar.
const int _beatsPerMeasure = 4;

const crisp.TimeSignature _fourFour = crisp.TimeSignature(4, 4);

/// No key signature: accidentals are written where they occur.
const crisp.KeySignature _noKeySignature = crisp.KeySignature(0);

/// The id the element for [hand] at [position] is drawn under.
///
/// Stable and derived from the realization, so a later layer that knows where
/// the learner is can colour or highlight by moment without this adapter
/// needing to know anything about a performance.
String staffElementId(Hand hand, int position) => '${hand.id}-$position';

/// The staff [hand] reads from.
crisp.Score staffScoreFor(ExerciseRealization realization, Hand hand) {
  final elements = <crisp.MusicElement>[
    for (final moment in realization.moments)
      if (moment.noteFor(hand) case final note?)
        crisp.NoteElement.note(
          _pitchOf(note.pitch),
          crisp.NoteDuration.quarter,
          // Always written, since nothing establishes the accidentals for the
          // reader: there is no key signature to imply them.
          showAccidental: note.pitch.alteration != 0 ? true : null,
          id: staffElementId(hand, moment.position),
        ),
  ];

  return crisp.Score(
    clef: hand == Hand.left ? crisp.Clef.bass : crisp.Clef.treble,
    keySignature: _noKeySignature,
    timeSignature: _fourFour,
    measures: [
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

/// Both staves, braced together, for an exercise played with both hands.
crisp.GrandStaff grandStaffFor(ExerciseRealization realization) =>
    crisp.GrandStaff(
      upper: staffScoreFor(realization, Hand.right),
      lower: staffScoreFor(realization, Hand.left),
    );

/// The grand staff broken into rows of [measuresPerRow] bars.
///
/// A grand staff draws one system however long it is, so two octaves hands
/// together runs off the side of a phone. Breaking it here keeps each row
/// fitting the width, at the cost of restating the clefs on every row, which
/// is what a new system does anyway.
List<crisp.GrandStaff> grandStaffRowsFor(
  ExerciseRealization realization, {
  int measuresPerRow = 2,
}) {
  final whole = grandStaffFor(realization);
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
/// claim a metre.
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
