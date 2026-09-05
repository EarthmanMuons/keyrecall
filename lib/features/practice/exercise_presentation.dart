import 'package:keyrecall_domain/keyrecall_domain.dart';

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
        '${_inversionName(inversion)} arpeggio',
};

/// What this kind of material is called inside a sentence.
///
/// The family's own word, because a learner playing an arpeggio is not playing
/// a scale and copy that says so is copy they have to translate.
String materialNoun(TechnicalMaterial material) => switch (material) {
  ScaleMaterial() => 'scale',
  ArpeggioMaterial() => 'arpeggio',
};

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
  ArpeggioInversion.root => 'root-position',
  ArpeggioInversion.first => 'first-inversion',
  ArpeggioInversion.second => 'second-inversion',
};

const Set<int> _whitePitchClasses = {0, 2, 4, 5, 7, 9, 11};

/// The keys a diagram marks, and the span it draws them in.
///
/// Derived from the exercise's realization rather than from a second interval
/// table here: what an exercise asks for has one definition, in the domain.
/// The marks are a set, so a diagram cannot say where in the scale the learner
/// is; a surface that shows progress needs the ordered moments instead.
class KeyboardDiagram {
  /// MIDI note of the leftmost *white* key drawn.
  final int firstWhiteMidi;

  /// How many white keys the diagram spans.
  final int whiteKeyCount;

  /// Every note the exercise asks for.
  final Set<int> memberNotes;

  /// Pitch class of the tonic, marked distinctly from the other members.
  final int tonicPitchClass;

  const KeyboardDiagram({
    required this.firstWhiteMidi,
    required this.whiteKeyCount,
    required this.memberNotes,
    required this.tonicPitchClass,
  });

  /// A diagram wide enough for what [exercise] asks for.
  factory KeyboardDiagram.forExercise(Exercise exercise) {
    final realization = realize(exercise);

    // A key on either side, so the outermost notes do not sit flush against
    // the edge of the diagram.
    final firstWhite = _whiteAtOrBelow(realization.lowestPitch - 1);
    final lastWhite = _whiteAtOrAbove(realization.highestPitch + 1);

    return KeyboardDiagram(
      firstWhiteMidi: firstWhite,
      whiteKeyCount: _whiteKeysThrough(firstWhite, lastWhite),
      memberNotes: realization.pitches,
      tonicPitchClass: pitchClassOf(exercise.material.tonic),
    );
  }
}

int _whiteAtOrBelow(int midi) {
  while (!_whitePitchClasses.contains(midi % 12)) {
    midi--;
  }
  return midi;
}

int _whiteAtOrAbove(int midi) {
  while (!_whitePitchClasses.contains(midi % 12)) {
    midi++;
  }
  return midi;
}

int _whiteKeysThrough(int firstWhite, int lastWhite) {
  var count = 0;
  for (var midi = firstWhite; midi <= lastWhite; midi++) {
    if (_whitePitchClasses.contains(midi % 12)) count++;
  }
  return count;
}
