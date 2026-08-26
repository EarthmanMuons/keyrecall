import 'package:keyrecall_domain/keyrecall_domain.dart';

/// The finger each key takes, for a diagram that marks keys rather than notes.
///
/// The fingering itself is the domain's; this only maps it onto the keys a
/// keyboard diagram draws.
Map<int, int> fingeringByKeyFor(Exercise exercise, Hand hand) {
  final fingers = fingeringFor(exercise, hand);
  if (fingers == null) return const {};

  final realization = realize(exercise);
  return {
    for (final (position, moment) in realization.moments.indexed)
      if (moment.noteFor(hand) case final note?)
        note.midiNote: fingers[position],
  };
}

/// The fingering to write on the staff, with a `null` wherever a digit would
/// repeat something already established.
///
/// A scale's fingering is a cycle: after the first octave every digit is the
/// one the learner has already read, and printing it again on every note is
/// how two octaves become a wall of numbers among the ledger lines. What stays
/// is the first octave, which teaches the pattern, and every crossing, which
/// is the only place the pattern does something a reader could not predict.
/// The first and last notes stay too, since where a scale starts and ends is
/// the part people check.
List<int?>? displayFingeringFor(Exercise exercise, Hand hand) {
  final fingers = fingeringFor(exercise, hand);
  if (fingers == null) return null;

  final firstOctave = scaleFormIntervals[exercise.material.form]!.length;

  return [
    for (final (position, finger) in fingers.indexed)
      if (position <= firstOctave ||
          position == fingers.length - 1 ||
          _isCrossing(fingers, position))
        finger
      else
        null,
  ];
}

/// Whether the finger at [position] is not the neighbour of the one before it.
///
/// A scale moves by step, so an adjacent finger is what a reader expects.
/// Anything else is a thumb passing under or a finger crossing over, which is
/// the thing worth naming.
bool _isCrossing(List<int> fingers, int position) =>
    position > 0 && (fingers[position] - fingers[position - 1]).abs() != 1;
