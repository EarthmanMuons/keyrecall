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

/// The finger each key takes on the keyboard diagram, or nothing when the
/// diagram cannot say whose finger it is.
///
/// A key takes one digit, and hands together share keys where their registers
/// meet, so two hands have no unambiguous rendering here. The staff writes the
/// digits over the notes instead, where each hand has its own line.
Map<int, int> keyboardFingeringFor(Exercise exercise) {
  final realization = realize(exercise);
  if (realization.hands.length > 1) return const {};
  return fingeringByKeyFor(exercise, realization.hands.single);
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
///
/// A crossing is written with the finger before it, because a lone digit says
/// which finger to arrive on and not what the hand is doing: 1 on its own is a
/// thumb, 3 then 1 is the thumb passing under a third finger, which is the
/// motion being named.
List<int?>? displayFingeringFor(Exercise exercise, Hand hand) {
  final fingers = fingeringFor(exercise, hand);
  if (fingers == null) return null;

  final firstOctave = exercise.material.topology.degreesPerOctave;

  return [
    for (final (position, finger) in fingers.indexed)
      if (position <= firstOctave ||
          position == fingers.length - 1 ||
          _isCrossing(fingers, position) ||
          _isCrossing(fingers, position + 1))
        finger
      else
        null,
  ];
}

/// Whether the finger at [position] is not the neighbor of the one before it.
///
/// A scale moves by step, so an adjacent finger is what a reader expects.
/// Anything else is a thumb passing under or a finger crossing over, which is
/// the thing worth naming.
bool _isCrossing(List<int> fingers, int position) =>
    position > 0 &&
    position < fingers.length &&
    (fingers[position] - fingers[position - 1]).abs() != 1;
