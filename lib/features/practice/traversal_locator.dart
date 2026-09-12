import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'staff_score.dart';

/// How far past the note it is expecting a hand looks for an arrival.
const int _lookahead = 2;

/// The notes of the moments each hand has reached, of those still held.
///
/// An orientation aid, built to stay with a learner rather than to be right
/// about their performance: it asks only which written note somebody is on, and
/// gives up the distinctions it does not need for that. A hand travels on its
/// own, so one hand's mistake leaves the other's highlight alone, and an
/// arrival the expected note did not match is looked for in the two notes after
/// it.
///
/// The register is not tolerated. A hand that enters the exercise in another
/// octave stays dark for the rest of the traversal rather than lighting up
/// wherever the registers happen to meet, which would read as something
/// happening.
///
/// What it draws is exact whatever it tolerates: a notehead lights only while
/// the key it is written for is down.
///
/// [traversalLength] projects repeated playing onto a single displayed
/// traversal.
Set<String> locatedElementIds(
  ExerciseRealization realization, {
  required PerformanceTranscript transcript,
  required Set<int> pressedNotes,
  int? traversalLength,
}) => {
  for (final MapEntry(key: hand, value: position) in reachedMoments(
    realization,
    transcript,
  ).entries)
    if (pressedNotes.contains(
      realization.moments[position].noteFor(hand)!.midiNote,
    ))
      staffElementId(
        hand,
        traversalLength == null ? position : position % traversalLength,
      ),
};

/// The last moment of [realization] each hand's arrivals reached.
///
/// A hand is absent until one of its notes arrives, and stays absent for the
/// whole traversal if the note it entered on was in another octave.
///
/// Which hand played an arrival is not something the input stream says, so
/// every hand is offered every note: a hand that matches it exactly takes it,
/// and only if none does is it offered as a note in another octave. Otherwise
/// the lower hand of an exercise in octaves would advance the upper one as
/// well.
Map<Hand, int> reachedMoments(
  ExerciseRealization realization,
  PerformanceTranscript transcript,
) {
  final lines = _linesOf(realization);
  final next = {for (final hand in lines.keys) hand: 0};
  final entered = <Hand>{};
  final displaced = <Hand>{};
  final reached = <Hand, int>{};

  for (final played in transcript.notes) {
    var hits = _hits(lines, next, played.midiNote, exact: true);
    final octaveOut = hits.isEmpty;
    if (octaveOut) hits = _hits(lines, next, played.midiNote, exact: false);

    for (final MapEntry(key: hand, value: index) in hits.entries) {
      if (entered.add(hand) && octaveOut) displaced.add(hand);
      reached[hand] = lines[hand]![index].position;
      next[hand] = index + 1;
    }
  }
  // Still traveled, so the hand that did play in the written register is not
  // dragged along by this one's arrivals.
  return {
    for (final MapEntry(key: hand, value: position) in reached.entries)
      if (!displaced.contains(hand)) hand: position,
  };
}

Map<Hand, int> _hits(
  Map<Hand, List<_Expected>> lines,
  Map<Hand, int> next,
  int midiNote, {
  required bool exact,
}) => {
  for (final MapEntry(key: hand, value: line) in lines.entries)
    hand: ?_match(line, next[hand]!, midiNote, exact: exact),
};

/// Where [midiNote] lands in [line] for a hand expecting [from], if anywhere.
///
/// The note being expected takes it whenever it can, so an exercise that
/// turns around on a note it plays twice does not read as ambiguous. Past
/// that, only one candidate may match: two would mean choosing which note the
/// learner left out, which is the guess this stops short of.
int? _match(
  List<_Expected> line,
  int from,
  int midiNote, {
  required bool exact,
}) {
  bool matches(_Expected note) =>
      exact ? note.midiNote == midiNote : note.midiNote % 12 == midiNote % 12;

  if (from < line.length && matches(line[from])) return from;

  int? found;
  for (
    var index = from + 1;
    index < line.length && index <= from + _lookahead;
    index++
  ) {
    if (!matches(line[index])) continue;
    if (found != null) return null;
    found = index;
  }
  return found;
}

/// What each hand plays, in order.
Map<Hand, List<_Expected>> _linesOf(ExerciseRealization realization) => {
  for (final hand in realization.hands)
    hand: [
      for (final moment in realization.moments)
        if (moment.noteFor(hand) case final note?)
          _Expected(moment.position, note.midiNote),
    ],
};

class _Expected {
  const _Expected(this.position, this.midiNote);

  final int position;
  final int midiNote;
}
