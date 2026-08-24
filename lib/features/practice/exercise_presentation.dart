import 'package:keyrecall_domain/keyrecall_domain.dart';

/// How an exercise reads and looks to a learner.
///
/// Presentation only. The domain keeps tonics as canonical ASCII strings
/// because persisted records key on them, and it has no interval content at
/// all, so turning `F# HARMONIC_MINOR` into `F♯ harmonic minor` and into a set
/// of MIDI notes happens here. This is the shape of the hole a shared music
/// type would eventually fill; until then the theory lives at the edge that
/// needs it rather than in the model.

/// The learner-facing name of [material], such as `F♯ harmonic minor`.
String materialName(TechnicalMaterial material) =>
    '${_prettyTonic(material.tonic)} ${_formName(material.form)}';

/// [conditions] as one line, such as `Right hand · 2 octaves · up and down ·
/// 80 bpm`.
String conditionsLine(ExecutionConditions conditions) => [
  _handsName(conditions.hands),
  conditions.octaves == 1 ? '1 octave' : '${conditions.octaves} octaves',
  conditions.direction == ScaleDirection.up ? 'up' : 'up and down',
  '${conditions.tempoBpm.round()} bpm',
].join(' · ');

/// The learner-facing name of a guidance rung.
String guidanceName(GuidanceContext guidance) =>
    switch (guidance.independence) {
      0 => 'cues throughout',
      1 => 'previewed, then hidden',
      _ => 'unguided',
    };

String _prettyTonic(String tonic) =>
    tonic.replaceAll('#', '♯').replaceAll('b', '♭');

String _formName(ScaleForm form) => switch (form) {
  ScaleForm.major => 'major',
  ScaleForm.naturalMinor => 'natural minor',
  ScaleForm.harmonicMinor => 'harmonic minor',
  ScaleForm.melodicMinor => 'melodic minor',
};

String _handsName(HandConfiguration hands) => switch (hands) {
  HandConfiguration.right => 'Right hand',
  HandConfiguration.left => 'Left hand',
  HandConfiguration.together => 'Hands together',
};

/// Semitones above the tonic in each scale form.
///
/// Melodic minor is the fixed ascending form in both directions, as
/// [ScaleForm.melodicMinor] defines it.
const Map<ScaleForm, List<int>> _formIntervals = {
  ScaleForm.major: [0, 2, 4, 5, 7, 9, 11],
  ScaleForm.naturalMinor: [0, 2, 3, 5, 7, 8, 10],
  ScaleForm.harmonicMinor: [0, 2, 3, 5, 7, 8, 11],
  ScaleForm.melodicMinor: [0, 2, 3, 5, 7, 9, 11],
};

const Map<String, int> _letterPitchClasses = {
  'C': 0,
  'D': 2,
  'E': 4,
  'F': 5,
  'G': 7,
  'A': 9,
  'B': 11,
};

const Set<int> _whitePitchClasses = {0, 2, 4, 5, 7, 9, 11};

/// Where a hand's tonic sits, as a MIDI note at or above this floor.
///
/// A presentation choice, not a domain fact: nothing in the model says which
/// register a scale is practiced in yet. The right hand sits around middle C
/// and the left an octave below, which is where these exercises are usually
/// played and keeps a two-octave hands-together span on one readable diagram.
const int _rightHandFloor = 60;
const int _leftHandFloor = 48;

/// The pitch material of an exercise, ready for a keyboard diagram.
///
/// Deliberately a *set* of member notes and a window to draw them in, with no
/// order: a cue that knew the sequence would be one step from following the
/// performance, and following the performance is measurement wearing a
/// presentation costume. Nothing here can tell where in the scale a learner
/// is, because nothing here knows the scale has an order.
class PitchSurface {
  /// MIDI note of the leftmost *white* key drawn.
  final int firstWhiteMidi;

  /// How many white keys the diagram spans.
  final int whiteKeyCount;

  /// Every member note within the played range, marked on the diagram.
  final Set<int> memberNotes;

  /// Pitch class of the tonic, marked distinctly from the other members.
  final int tonicPitchClass;

  const PitchSurface({
    required this.firstWhiteMidi,
    required this.whiteKeyCount,
    required this.memberNotes,
    required this.tonicPitchClass,
  });

  /// The material [exercise] asks for, in the register its conditions imply.
  factory PitchSurface.forExercise(Exercise exercise) {
    final tonicPitchClass = pitchClassOf(exercise.material.tonic);
    final conditions = exercise.conditions;
    final span = 12 * conditions.octaves;

    final floors = [
      if (conditions.hands.usesLeftHand) _leftHandFloor,
      if (conditions.hands.usesRightHand) _rightHandFloor,
    ];
    final lowest = _tonicAtOrAbove(floors.first, tonicPitchClass);
    final highest = _tonicAtOrAbove(floors.last, tonicPitchClass) + span;

    final intervals = _formIntervals[exercise.material.form]!;
    final memberPitchClasses = {
      for (final interval in intervals) (tonicPitchClass + interval) % 12,
    };

    // A key on either side, so the outermost members do not sit flush against
    // the edge of the diagram.
    final firstWhite = _whiteAtOrBelow(lowest - 1);
    final lastWhite = _whiteAtOrAbove(highest + 1);

    return PitchSurface(
      firstWhiteMidi: firstWhite,
      whiteKeyCount: _whiteKeysThrough(firstWhite, lastWhite),
      memberNotes: {
        for (var midi = lowest; midi <= highest; midi++)
          if (memberPitchClasses.contains(midi % 12)) midi,
      },
      tonicPitchClass: tonicPitchClass,
    );
  }
}

/// The pitch class of a canonical tonic such as `C`, `F#`, or `Bb`.
///
/// Throws [ArgumentError] for anything [TechnicalMaterial] would have
/// rejected, since a tonic reaching here uncanonical means it was built
/// somewhere that skipped that check.
int pitchClassOf(String tonic) {
  final natural = _letterPitchClasses[tonic.isEmpty ? '' : tonic[0]];
  if (natural == null || tonic.length > 2) {
    throw ArgumentError.value(tonic, 'tonic', 'not a canonical tonic');
  }
  if (tonic.length == 1) return natural;
  return switch (tonic[1]) {
    '#' => (natural + 1) % 12,
    'b' => (natural + 11) % 12,
    _ => throw ArgumentError.value(tonic, 'tonic', 'not a canonical tonic'),
  };
}

int _tonicAtOrAbove(int floor, int pitchClass) =>
    floor + (pitchClass - floor % 12 + 12) % 12;

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
