import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'execution_conditions.dart';
import 'exercise.dart';
import 'hand_path.dart';
import 'pitch_spelling.dart';
import 'spelled_pitch.dart';
import 'technical_material.dart';

const _handSetEquality = SetEquality<Hand>();

/// One note the exercise asks for, and which hands play it.
///
/// Usually one hand. Both, where two lines meet on one key: a piano sends one
/// note-on however many thumbs are on it, so two notes there would ask for an
/// observation the instrument cannot produce.
@immutable
class RealizedNote {
  /// Which hands play it.
  final Set<Hand> hands;

  /// The note as it is written, which is what a staff needs.
  final SpelledPitch pitch;

  RealizedNote({required Hand hand, required SpelledPitch pitch})
    : this.shared(hands: {hand}, pitch: pitch);

  /// A note two hands meet on.
  ///
  /// Throws [ArgumentError] when no hand plays it.
  RealizedNote.shared({required Set<Hand> hands, required this.pitch})
    : hands = Set.unmodifiable(hands) {
    if (hands.isEmpty) {
      throw ArgumentError.value(hands, 'hands', 'a note needs a hand');
    }
  }

  /// The same note [octaves] higher, or lower for a negative count.
  RealizedNote shiftedByOctaves(int octaves) => octaves == 0
      ? this
      : RealizedNote.shared(
          hands: hands,
          pitch: pitch.shiftedByOctaves(octaves),
        );

  /// Which key it is played on, which is what a keyboard and MIDI need.
  int get midiNote => pitch.midiNote;

  /// Whether [hand] plays this note.
  bool isPlayedBy(Hand hand) => hands.contains(hand);

  @override
  bool operator ==(Object other) =>
      other is RealizedNote &&
      _handSetEquality.equals(other.hands, hands) &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(_handSetEquality.hash(hands), pitch);

  @override
  String toString() {
    final playing = [
      for (final hand in Hand.values)
        if (hands.contains(hand)) hand.id,
    ];
    return 'RealizedNote(${playing.join('+')}, $pitch)';
  }
}

const _noteListEquality = ListEquality<RealizedNote>();
const _momentListEquality = ListEquality<RealizationMoment>();

/// Everything that happens at one point in an exercise.
///
/// A moment rather than a note, because hands play together. [position] counts
/// moments and [metricOffset] says where the moment falls in beats. V1 puts one
/// moment on each beat, so the two agree.
@immutable
class RealizationMoment {
  /// Index of this moment in the exercise, from zero.
  final int position;

  /// Where the moment falls, in beats from the start.
  final double metricOffset;

  /// The notes sounding at this moment, at most one per hand in V1. A note two
  /// hands meet on appears once, carrying both.
  final List<RealizedNote> notes;

  /// The same moment [octaves] higher, or lower for a negative count.
  RealizationMoment shiftedByOctaves(int octaves) => octaves == 0
      ? this
      : RealizationMoment(
          position: position,
          metricOffset: metricOffset,
          notes: [for (final note in notes) note.shiftedByOctaves(octaves)],
        );

  /// Throws [ArgumentError] when nothing sounds, when a hand is asked to play
  /// twice at once, or when two notes ask for the same key.
  ///
  /// A moment is something that happens; silence is the absence of one. V1 has
  /// no chords, and a second note for one hand would make [noteFor] answer
  /// arbitrarily. Two notes on one key would ask for two observations the
  /// instrument reports as one note-on, which no performance can satisfy;
  /// hands that meet belong in a single [RealizedNote.shared].
  RealizationMoment({
    required this.position,
    required this.metricOffset,
    required List<RealizedNote> notes,
  }) : notes = List.unmodifiable(notes) {
    if (this.notes.isEmpty) {
      throw ArgumentError.value(notes, 'notes', 'must not be empty');
    }
    final playing = <Hand>{};
    final sounding = <int>{};
    for (final note in this.notes) {
      for (final hand in note.hands) {
        if (!playing.add(hand)) {
          throw ArgumentError.value(
            notes,
            'notes',
            'a hand plays at most one note per moment',
          );
        }
      }
      if (!sounding.add(note.midiNote)) {
        throw ArgumentError.value(
          notes,
          'notes',
          'notes on one key share a RealizedNote',
        );
      }
    }
  }

  /// The note [hand] plays here, or null when it plays nothing.
  RealizedNote? noteFor(Hand hand) =>
      notes.firstWhereOrNull((note) => note.isPlayedBy(hand));

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
/// The single answer to "which notes, in what order, in which hand", shared by
/// staff rendering, progress, fingering annotation, and alignment.
///
/// Not measurement: no wall-clock timing, no tolerance, no notion of a note
/// being early, late, or wrong. Relating a performance to the task is
/// `keyrecall_alignment`'s job.
///
/// Derived on demand from an [Exercise] and not part of its identity, so
/// nothing about it reaches candidate generation, ranking, or persisted
/// records.
@immutable
class ExerciseRealization {
  /// The moments, in the order they are played.
  final List<RealizationMoment> moments;

  /// Throws [ArgumentError] when there is nothing to play, or when a moment
  /// does not sit at the position it carries.
  ///
  /// An exercise that asks for no notes is not a task, and [lowestPitch] and
  /// [highestPitch] have no answer on one. Alignment indexes this list where
  /// staff rendering reads [RealizationMoment.position], so the two have to be
  /// the same number.
  ExerciseRealization(List<RealizationMoment> moments)
    : moments = List.unmodifiable(moments) {
    if (this.moments.isEmpty) {
      throw ArgumentError.value(moments, 'moments', 'must not be empty');
    }
    for (final (index, moment) in this.moments.indexed) {
      if (moment.position != index) {
        throw ArgumentError.value(
          moments,
          'moments',
          'moment $index carries position ${moment.position}',
        );
      }
    }
  }

  /// The whole exercise [octaves] higher, or lower for a negative count.
  ///
  /// Every note moves together, preserving the shape, the intervals, and the
  /// distance between the hands.
  ExerciseRealization shiftedByOctaves(int octaves) => octaves == 0
      ? this
      : ExerciseRealization([
          for (final moment in moments) moment.shiftedByOctaves(octaves),
        ]);

  /// Which hands play at all.
  Set<Hand> get hands => {
    for (final moment in moments)
      for (final note in moment.notes) ...note.hands,
  };

  /// How many notes are asked for. A note two hands meet on counts once,
  /// because one key press is all the instrument can report.
  int get noteCount =>
      moments.fold(0, (total, moment) => total + moment.notes.length);

  /// Every pitch the exercise asks for, without order or repetition.
  ///
  /// What a diagram that marks keys needs; a staff needs [moments] instead.
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

/// The register boundary the two hands are placed against.
///
/// A V1 convention, not a fact about the material.
const int _middleC = 60;

/// Where [hand]'s tonic sits for a traversal of [octaves] octaves.
///
/// Middle C is the boundary both hands are placed against from opposite sides:
/// the right hand begins near it, and the left hand *finishes* near it. The
/// left hand is anchored by its end because a fixed floor climbs, putting the
/// upper octaves of a long traversal into the other hand's register.
///
/// Near, not at or beyond: rounding to the closer octave keeps every key within
/// half an octave of the hand's home rather than dropping a tonic a whole
/// octave to avoid clearing the boundary by a step.
///
/// Hands together therefore sit one octave apart at one octave and two apart at
/// two, rather than the octave a pianist would expect.
int _tonicFor(Hand hand, int pitchClass, int octaves) => switch (hand) {
  Hand.right => _nearestTonic(_middleC, pitchClass),
  Hand.left => _nearestTonic(_middleC - 12 * octaves, pitchClass),
};

/// Where each hand's line begins.
///
/// Parallel motion anchors each hand against its own register. Contrary motion
/// starts them on one shared tonic, so the hands begin in unison and move
/// apart, both thumbs on the same key. That placement is chosen here;
/// [HandMotion.contrary] says only that the trajectories run in opposite
/// directions.
Map<Hand, int> _tonicsFor(
  ExecutionConditions conditions,
  List<Hand> hands,
  int pitchClass,
) => switch (conditions.handMotion) {
  HandMotion.parallel => {
    for (final hand in hands)
      hand: _tonicFor(hand, pitchClass, conditions.octaves),
  },
  HandMotion.contrary => {
    for (final hand in hands) hand: _nearestTonic(_middleC, pitchClass),
  },
};

/// Which key [degree] lands on, counting from [tonic].
///
/// Floor division rather than truncation, so a degree below the tonic falls
/// into the octave below it.
int _midiNoteAt({
  required int tonic,
  required int degree,
  required List<int> intervals,
}) {
  final octave = (degree / intervals.length).floor();
  return tonic + octave * 12 + intervals[degree - octave * intervals.length];
}

/// The notes [exercise] asks for, in order.
///
/// Spelling follows the scale degree rather than the sounding pitch: the
/// seventh degree is written on the seventh letter above the tonic whatever it
/// sounds like, which is what makes G♯ harmonic minor's F𝄪 come out as a
/// raised seventh rather than as a G.
///
/// Throws [ArgumentError] if the tonic is not canonical, and [StateError] if
/// the material cannot be spelled within double accidentals.
ExerciseRealization realize(Exercise exercise) {
  final material = exercise.material;
  final intervals = material.topology.semitoneOffsets;
  final conditions = exercise.conditions;

  final hands = [
    if (conditions.hands.usesLeftHand) Hand.left,
    if (conditions.hands.usesRightHand) Hand.right,
  ];
  final paths = handPathsFor(conditions, degreesPerOctave: intervals.length);
  final tonics = _tonicsFor(
    conditions,
    hands,
    (pitchClassOf(material.tonic) + material.topology.originSemitoneOffset) %
        12,
  );

  // Every hand plays at every moment in V1, so the paths are read in lockstep:
  // the degrees may differ, the event structure may not.
  final positions = paths.values.first.length;
  assert(
    paths.values.every((path) => path.length == positions),
    'every hand path covers every moment',
  );

  return ExerciseRealization([
    for (var position = 0; position < positions; position++)
      RealizationMoment(
        position: position,
        // One note to a beat, which is all the conditions can express.
        metricOffset: position.toDouble(),
        notes: _notesAt(
          position: position,
          hands: hands,
          paths: paths,
          tonics: tonics,
          material: material,
          intervals: intervals,
        ),
      ),
  ]);
}

/// What sounds at one moment, with hands that meet on a key sharing its note.
///
/// Keyed by sounding key rather than by spelling, because the key is what the
/// instrument reports: two hands on one note-on have to be one expected note or
/// the attempt can never be complete.
List<RealizedNote> _notesAt({
  required int position,
  required List<Hand> hands,
  required Map<Hand, List<int>> paths,
  required Map<Hand, int> tonics,
  required TechnicalMaterial material,
  required List<int> intervals,
}) {
  final byKey = <int, (SpelledPitch, Set<Hand>)>{};
  for (final hand in hands) {
    final degree = paths[hand]![position];
    final midiNote = _midiNoteAt(
      tonic: tonics[hand]!,
      degree: degree,
      intervals: intervals,
    );
    if (byKey[midiNote] case (_, final sharing)?) {
      sharing.add(hand);
      continue;
    }
    byKey[midiNote] = (
      spellExpectedPitch(
        material: material,
        degree: degree,
        midiNote: midiNote,
      ),
      {hand},
    );
  }

  return [
    for (final (pitch, sharing) in byKey.values)
      RealizedNote.shared(hands: sharing, pitch: pitch),
  ];
}

/// The [pitchClass] octave closest to [target], preferring the lower one when
/// the two are equally far.
int _nearestTonic(int target, int pitchClass) {
  final below = target - (target % 12 - pitchClass + 12) % 12;
  final above = below + 12;
  return (target - below) <= (above - target) ? below : above;
}
