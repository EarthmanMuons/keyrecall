import 'dart:math' as math;

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';

import '../piano/models/piano_view_settings.dart';
import '../piano/services/piano_geometry.dart';

/// How an exercise reads and looks to a learner.
///
/// Naming and layout only. Which notes an exercise asks for is the domain's
/// answer to give, and `realize` gives it.

/// The learner-facing name of [material], such as `F♯ harmonic minor`.
String materialName(TechnicalMaterial material) => switch (material) {
  ScaleMaterial(:final tonic, :final form) =>
    '${prettyTonic(tonic)} ${_formName(form)}',
  ArpeggioMaterial(:final tonic, :final quality, :final inversion) =>
    '${prettyTonic(tonic)} ${_arpeggioQualityName(quality)} '
        '${_inversionName(inversion)}arpeggio',
};

/// What this kind of material is called inside a sentence.
///
/// The family's own word, because a learner playing an arpeggio is not playing
/// a scale and copy that says so is copy they have to translate.
String materialNoun(TechnicalMaterial material) => switch (material) {
  ScaleMaterial() => 'scale',
  ArpeggioMaterial() => 'arpeggio',
};

/// What a self-paced attempt asks for, before anything has been played.
///
/// Nothing here says slowly, or easier, or to take your time. Each of those is
/// an interpretation of why the ordinary attempt did not go well, and nothing
/// has made one. What changed is that the pace is the learner's.
///
/// A task asking for more than one traversal says how many, and leaves the rest
/// to the notes: what is on screen is one traversal, so playing it again is
/// playing what is there again rather than going on past it.
String selfPacedInstruction(int traversals) => traversals == 1
    ? 'Practice this at your own pace. Tap Done when finished.'
    : 'Play this ${_timesName(traversals)} at your own pace. '
          'Tap Done when finished.';

String _timesName(int times) => switch (times) {
  2 => 'twice',
  3 => 'three times',
  _ => '$times times',
};

/// What a supported attempt did, in the terms the record itself carries.
///
/// States what happened and stops there. Whether it was good is a question
/// supported work does not answer, and a line that implied an answer would be
/// making the claim the whole design exists to withhold.
///
/// Read from how the attempt ended and how far it got, never from what is
/// missing. "You stopped" attributes the ending to the learner, and only the
/// learner saying so supports that. An input fault says what was recorded
/// and leaves the ending unattributed, because the notes that did not arrive
/// may well have been played; a timeout, a limit and a record whose format
/// could not say get the same neutral wording, for the same reason.
///
/// An attempt that did not come out says so and stops there. Nothing here
/// locates where the playing ended, because no field records it:
/// `firstAbsentPosition` is the earliest moment nothing arrived for, and the
/// learner may have played on past it to the end of the last traversal. Only
/// an attempt that completed can say how much came out, and it says so by
/// having completed.
String acquisitionOutcomeLine(AcquisitionAttemptRecord record) {
  final noun = materialNoun(record.parent.material);
  final asked = record.task.portion.traversals;

  if (record.termination == AttemptTermination.inputInterrupted) {
    return record.completion.isComplete
        ? 'The connection was interrupted. The whole $noun was recorded'
              '${asked == 1 ? '' : ' ${_timesName(asked)}'}.'
        : 'The connection was interrupted before the $noun was fully '
              'recorded.';
  }

  if (!record.started) return 'Nothing came through that time.';

  if (record.completion.isComplete) {
    return asked == 1
        ? 'You played the whole $noun, at your own pace.'
        : 'You played the whole $noun ${_timesName(asked)}, at your own pace.';
  }

  // Every position accounted for and some of them something else, which is a
  // fact about the notes rather than about where the attempt ended.
  if (record.firstAbsentPosition == null) {
    return 'Some of the notes were not the ones in the $noun.';
  }
  return record.termination == AttemptTermination.learnerStopped
      ? 'You stopped before completing the $noun.'
      : 'The $noun was not completed.';
}

/// The note the material is named after, spelled the way it is written.
String tonicName(TechnicalMaterial material) => prettyTonic(material.tonic);

/// Which hand or hands play, as a learner would say it.
String handsName(HandConfiguration hands) => switch (hands) {
  HandConfiguration.right => 'Right hand',
  HandConfiguration.left => 'Left hand',
  HandConfiguration.together => 'Hands together',
};

/// How far the traversal goes.
String octavesName(int octaves) =>
    octaves == 1 ? '1 octave' : '$octaves octaves';

/// Which way it runs, and for two hands, how they run against each other.
String traversalName(ExecutionConditions conditions) =>
    switch ((conditions.handMotion, conditions.direction)) {
      (HandMotion.contrary, ExerciseDirection.up) => 'Contrary motion, apart',
      (HandMotion.contrary, ExerciseDirection.upDown) =>
        'Contrary motion, apart and back',
      (_, ExerciseDirection.up) => 'Up',
      (_, ExerciseDirection.upDown) => 'Up and down',
    };

/// What the way out of an attempt says, before anything has been played.
///
/// At the previewed rung the notes were studied a moment ago and are hidden
/// once it starts, so the button answers that condition. Unguided, it is about
/// memory, and only then can it be about forgetting: a material this learner
/// has never been shown cannot have been forgotten, and saying so on a first
/// meeting asks somebody to accept a failure that is not theirs, at the moment
/// KeyRecall is deliberately probing past what it has seen them do.
String declineLabel(GuidanceContext guidance, {required bool metBefore}) =>
    switch ((guidance.independence, metBefore)) {
      (1, _) => "I can't play it without the notes",
      (_, true) => "I don't remember",
      (_, false) => "I don't know this yet",
    };

/// The learner-facing name of a guidance rung.
String guidanceName(GuidanceContext guidance) =>
    switch (guidance.independence) {
      0 => 'cues throughout',
      1 => 'previewed, then hidden',
      _ => 'unguided',
    };

/// A key written the way a learner reads it, with real accidental signs.
String prettyTonic(String tonic) =>
    tonic.replaceAll('#', '♯').replaceAll('b', '♭');

String _formName(ScaleForm form) => switch (form) {
  ScaleForm.major => 'major',
  ScaleForm.naturalMinor => 'natural minor',
  ScaleForm.harmonicMinor => 'harmonic minor',
  ScaleForm.melodicMinor => 'melodic minor',
};

String _arpeggioQualityName(ArpeggioQuality quality) => switch (quality) {
  ArpeggioQuality.major => 'major',
  ArpeggioQuality.minor => 'minor',
};

String _inversionName(ArpeggioInversion inversion) => switch (inversion) {
  ArpeggioInversion.root => '',
  ArpeggioInversion.first => 'first-inversion ',
  ArpeggioInversion.second => 'second-inversion ',
};

/// The keys a diagram marks, and the keys it keeps in view.
///
/// Derived from the exercise's realization rather than from a second interval
/// table here: what an exercise asks for has one definition, in the domain.
/// The marks are a set, so a diagram cannot say where in the scale the learner
/// is; a surface that shows progress needs the ordered moments instead.
class KeyboardDiagram {
  /// Every note the exercise asks for.
  final Set<int> memberNotes;

  /// The notes the exercise begins on, one per hand.
  final Set<int> startingNotes;

  /// Pitch class of the tonic, marked distinctly from the other members.
  final int tonicPitchClass;

  const KeyboardDiagram({
    required this.memberNotes,
    required this.startingNotes,
    required this.tonicPitchClass,
  });

  factory KeyboardDiagram.forExercise(Exercise exercise) {
    final realization = realize(exercise);
    return KeyboardDiagram(
      memberNotes: realization.pitches,
      startingNotes: {
        for (final note in realization.moments.first.notes) note.midiNote,
      },
      tonicPitchClass: pitchClassOf(exercise.material.tonic),
    );
  }
}

/// How large a keyboard is drawn, from the space it is given and what the
/// learner asked for.
///
/// Never from the exercise, so the keys stay the same shape from one exercise
/// to the next and only what is in view changes. By default a white key is
/// `keyAspect` times as tall as it is wide, until the whole piano fits, and
/// wider only on a window too wide for even that. Zooming widens them from there, and resizing
/// grows the keyboard's height without touching their width.
class KeyboardScale {
  /// How many white keys fit across the keyboard at once.
  final int visibleWhiteKeyCount;

  /// How wide each white key is drawn.
  final double whiteKeyWidth;

  /// How tall the keyboard is drawn.
  final double height;

  const KeyboardScale({
    required this.visibleWhiteKeyCount,
    required this.whiteKeyWidth,
    required this.height,
  });

  /// How many times taller than wide a white key is by default, unless the
  /// caller asks for a denser keyboard.
  static const double defaultKeyAspect = 4;

  /// The fewest white keys zooming in leaves on screen.
  static const int minZoomedWhiteKeyCount = 8;

  /// The narrowest white key a finger number fits on.
  static const double minFingeringKeyWidth = 28;

  factory KeyboardScale.forSize({
    required double width,
    required double baseHeight,
    double? maxHeight,
    double keyAspect = defaultKeyAspect,
    PianoViewSettings settings = const PianoViewSettings.defaults(),
  }) {
    final base = (width * keyAspect / baseHeight).ceil().clamp(
      1,
      PianoGeometry.fullKeyboardWhiteKeyCount,
    );
    final int count = (base / settings.widthScale).round().clamp(
      math.min(minZoomedWhiteKeyCount, base),
      base,
    );
    final ceiling = math.max(baseHeight, maxHeight ?? baseHeight);
    return KeyboardScale(
      visibleWhiteKeyCount: count,
      whiteKeyWidth: width / count,
      height: (baseHeight * settings.heightScale).clamp(baseHeight, ceiling),
    );
  }

  /// Whether a finger number fits on a key at this width.
  bool get holdsFingering => whiteKeyWidth >= minFingeringKeyWidth;
}
