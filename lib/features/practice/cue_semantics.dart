import 'package:keyrecall_domain/keyrecall_domain.dart';

import 'exercise_presentation.dart';
import 'traversal_locator.dart';

/// The cue, in words, for a learner who is not reading the screen.
///
/// The same information the marked keys and the written notes carry, on the
/// channel a screen reader has. A cue supplied only in pixels is not supplied
/// to everybody, and an attempt recorded as cued would then be describing an
/// exposure that did not happen.
///
/// Governed by the resolved presentation rather than by what is on screen, so
/// it withdraws exactly when the cue does and it names a finger only where the
/// motor channel is open. Nothing here reads the performance: this is what the
/// exercise asks for, in the order it asks for it.
///
/// Null when nothing is supplied, so the semantics tree carries no node at all
/// rather than an empty one.
String? cueSemantics({
  required Exercise exercise,
  required PresentationConditions presentation,
  required bool showsCue,
}) {
  if (!showsCue || !presentation.pitchCue.suppliesMaterial) return null;

  // One traversal, which is what the staff and the keyboard draw. A supported
  // task repeats what is on screen rather than showing more of it, and the
  // task statement is where how many times belongs.
  final realization = realize(exercise);
  final fingering = presentation.motorCue == MotorCue.fingering
      ? {
          for (final hand in realization.hands)
            hand: fingeringFor(exercise, hand),
        }
      : const <Hand, List<int>?>{};

  return [
    _heading(exercise, realization),
    for (final hand in realization.hands)
      _line(
        hand,
        realization,
        fingering[hand],
        named: realization.hands.length > 1,
      ),
  ].join(' ');
}

/// What a learner has played so far, in words.
///
/// The echo's channel, and only the echo's: it reads back arrivals in the
/// order they came and places none of them in the exercise. The reserved slots
/// a transcript staff draws to hold its width are not here, because nothing
/// was played into them and drawing one would say a learner rested.
///
/// Null with nothing played, and null where the presentation shows the learner
/// nothing of their own playing.
String? echoSemantics({
  required PerformanceTranscript transcript,
  required PresentationConditions presentation,
}) {
  if (presentation.performanceFeedback == PerformanceFeedback.none) return null;
  if (transcript.isEmpty) return null;
  return 'Played so far: '
      '${transcript.notes.map((note) => note.pitch.prettyLabel).join(', ')}.';
}

String _heading(Exercise exercise, ExerciseRealization realization) =>
    '${materialName(exercise.material)}, '
    '${handsName(exercise.conditions.hands).toLowerCase()}, '
    '${traversalName(exercise.conditions).toLowerCase()}, '
    '${octavesName(exercise.conditions.octaves)}, '
    '${realization.moments.length} notes.';

String _line(
  Hand hand,
  ExerciseRealization realization,
  List<int>? fingering, {
  required bool named,
}) {
  final notes = <String>[];
  for (final (position, moment) in realization.moments.indexed) {
    final note = moment.noteFor(hand);
    if (note == null) continue;
    final finger = fingering == null || position >= fingering.length
        ? null
        : fingering[position];
    notes.add(
      finger == null
          ? note.pitch.prettyLabel
          : '${note.pitch.prettyLabel} finger $finger',
    );
  }
  final line = '${notes.join(', ')}.';
  return named ? '${_handName(hand)}: $line' : line;
}

String _handName(Hand hand) => hand == Hand.right ? 'Right hand' : 'Left hand';

/// Where the locator says each hand has got to, in words.
///
/// The locator's channel and only its: it places a held note into the material
/// and says nothing about whether anything was right. Governed by
/// [LocatorFeedback] rather than by the echo, because it is contingent on what
/// was played matching what was expected and the echo is not.
///
/// Null when the channel is closed or nothing is currently located, so a
/// screen reader is told where a hand is exactly when the staff shows it.
String? locatorSemantics({
  required ExerciseRealization realization,
  required PerformanceTranscript transcript,
  required Set<int> pressedNotes,
  required PresentationConditions presentation,
  int? traversalLength,
}) {
  if (presentation.locatorFeedback != LocatorFeedback.positionTracking) {
    return null;
  }
  final total = traversalLength ?? realization.moments.length;
  final reached = <String>[];
  for (final MapEntry(key: hand, value: position) in reachedMoments(
    realization,
    transcript,
  ).entries) {
    final note = realization.moments[position].noteFor(hand)!;
    if (!pressedNotes.contains(note.midiNote)) continue;
    reached.add(
      '${_handName(hand)} on note ${position % total + 1} of $total, '
      '${note.pitch.prettyLabel}.',
    );
  }
  return reached.isEmpty ? null : reached.join(' ');
}
