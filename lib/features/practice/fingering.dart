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
