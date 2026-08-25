import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'exercise.dart';
import 'execution_conditions.dart';
import 'technical_material.dart';

/// One hand, as a player rather than as a configuration.
///
/// [HandConfiguration] says which hands an exercise asks for; this says which
/// hand a particular note belongs to, so `together` is not a value here.
enum Hand {
  left('LEFT'),
  right('RIGHT');

  const Hand(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// One note a hand is asked to play.
@immutable
class RealizedNote {
  /// Which hand plays it.
  final Hand hand;

  /// Which key, as a MIDI note number.
  final int midiNote;

  const RealizedNote({required this.hand, required this.midiNote});

  @override
  bool operator ==(Object other) =>
      other is RealizedNote && other.hand == hand && other.midiNote == midiNote;

  @override
  int get hashCode => Object.hash(hand, midiNote);

  @override
  String toString() => 'RealizedNote(${hand.id}, $midiNote)';
}

const _noteListEquality = ListEquality<RealizedNote>();
const _momentListEquality = ListEquality<RealizationMoment>();

/// Everything that happens at one point in an exercise.
///
/// A moment rather than a note, because hands play together and later patterns
/// put several pitches in one place. [position] counts moments; [metricOffset]
/// says where the moment falls in beats. V1 puts one moment on each beat, so
/// the two agree, and they are kept apart because that will stop being true as
/// soon as an exercise has subdivisions or a held note.
@immutable
class RealizationMoment {
  /// Index of this moment in the exercise, from zero.
  final int position;

  /// Where the moment falls, in beats from the start.
  final double metricOffset;

  /// The notes sounding at this moment, at most one per hand in V1.
  final List<RealizedNote> notes;

  RealizationMoment({
    required this.position,
    required this.metricOffset,
    required List<RealizedNote> notes,
  }) : notes = List.unmodifiable(notes);

  /// The note [hand] plays here, or null when it plays nothing.
  RealizedNote? noteFor(Hand hand) =>
      notes.firstWhereOrNull((note) => note.hand == hand);

  @override
  bool operator ==(Object other) =>
      other is RealizationMoment &&
      other.position == position &&
      other.metricOffset == metricOffset &&
      _noteListEquality.equals(other.notes, notes);

  @override
  int get hashCode =>
      Object.hash(position, metricOffset, _noteListEquality.hash(notes));

  @override
  String toString() =>
      'RealizationMoment($position, $metricOffset, ${notes.length} notes)';
}

/// What an exercise asks for, as an ordered sequence of musical events.
///
/// The single answer to "which notes, in what order, in which hand". Staff
/// rendering, a progress indicator, fingering annotation, and eventually the
/// alignment of an observed performance all need that answer, and deriving it
/// twice is how two definitions of the same exercise start to disagree.
///
/// Deliberately not measurement. There is no wall-clock timing here, no
/// tolerance, no notion of a note being played early, late, wrongly, or not at
/// all. A realization says what the task is; relating a performance to it is a
/// separate layer that does not exist yet.
///
/// Derived on demand from an [Exercise] and not part of its identity, so
/// nothing about it reaches candidate generation, ranking, or persisted
/// records.
@immutable
class ExerciseRealization {
  /// The moments, in the order they are played.
  final List<RealizationMoment> moments;

  ExerciseRealization(List<RealizationMoment> moments)
    : moments = List.unmodifiable(moments);

  /// Which hands play at all.
  Set<Hand> get hands => {
    for (final moment in moments)
      for (final note in moment.notes) note.hand,
  };

  /// Every pitch the exercise asks for, without order or repetition.
  ///
  /// What a diagram that marks keys needs, as distinct from what a staff
  /// needs, which is [moments].
  Set<int> get pitches => {
    for (final moment in moments)
      for (final note in moment.notes) note.midiNote,
  };

  /// The lowest pitch asked for.
  int get lowestPitch => pitches.reduce((a, b) => a < b ? a : b);

  /// The highest pitch asked for.
  int get highestPitch => pitches.reduce((a, b) => a > b ? a : b);

  @override
  bool operator ==(Object other) =>
      other is ExerciseRealization &&
      _momentListEquality.equals(other.moments, moments);

  @override
  int get hashCode => _momentListEquality.hash(moments);

  @override
  String toString() => 'ExerciseRealization(${moments.length} moments)';
}

/// Semitones above the tonic in each scale form.
///
/// [ScaleForm.melodicMinor] is the fixed form, so a descent uses these too.
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

/// Lowest MIDI note each hand's tonic is placed at or above.
///
/// A V1 convention, not a fact about the material: the right hand practices
/// around middle C and the left an octave below it. Nothing yet lets a learner
/// ask for a different register.
const Map<Hand, int> _handFloors = {Hand.right: 60, Hand.left: 48};

/// The notes [exercise] asks for, in order.
///
/// Throws [ArgumentError] if the material's tonic is not canonical, which
/// [TechnicalMaterial] would already have rejected.
ExerciseRealization realize(Exercise exercise) {
  final tonicPitchClass = pitchClassOf(exercise.material.tonic);
  final intervals = _formIntervals[exercise.material.form]!;
  final conditions = exercise.conditions;

  final ascending = <int>[
    for (var octave = 0; octave < conditions.octaves; octave++)
      for (final interval in intervals) octave * 12 + interval,
    12 * conditions.octaves,
  ];
  final offsets = switch (conditions.direction) {
    ScaleDirection.up => ascending,
    // The apex is played once and the traversal turns around on it.
    ScaleDirection.upDown => [...ascending, ...ascending.reversed.skip(1)],
  };

  final hands = [
    if (conditions.hands.usesLeftHand) Hand.left,
    if (conditions.hands.usesRightHand) Hand.right,
  ];
  final tonics = {
    for (final hand in hands)
      hand: _tonicAtOrAbove(_handFloors[hand]!, tonicPitchClass),
  };

  return ExerciseRealization([
    for (final (position, offset) in offsets.indexed)
      RealizationMoment(
        position: position,
        // One note to a beat, which is all a scale asks for and all the
        // conditions can currently express.
        metricOffset: position.toDouble(),
        notes: [
          for (final hand in hands)
            RealizedNote(hand: hand, midiNote: tonics[hand]! + offset),
        ],
      ),
  ]);
}

/// The pitch class of a canonical tonic such as `C`, `F#`, or `Bb`.
///
/// Throws [ArgumentError] for anything [TechnicalMaterial] would reject.
int pitchClassOf(String tonic) {
  if (!TechnicalMaterial.isCanonicalTonic(tonic)) {
    throw ArgumentError.value(tonic, 'tonic', 'not a canonical tonic');
  }
  final natural = _letterPitchClasses[tonic[0]]!;
  if (tonic.length == 1) return natural;
  return tonic[1] == '#' ? (natural + 1) % 12 : (natural + 11) % 12;
}

int _tonicAtOrAbove(int floor, int pitchClass) =>
    floor + (pitchClass - floor % 12 + 12) % 12;
