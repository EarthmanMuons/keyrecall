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
/// Usually one hand. Both, where two lines meet on one key: contrary motion
/// conventionally starts and returns in unison, and a piano sends one note-on
/// however many thumbs are on the key. Modelling that as two notes would ask
/// for an observation the instrument cannot produce, so the attempt could never
/// read as complete.
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

  /// Throws [ArgumentError] when a hand is asked to play twice at once.
  ///
  /// V1 has no chords, and a moment that already held two notes for one hand
  /// would make [noteFor] answer arbitrarily. Relax this deliberately when a
  /// pattern needs it rather than discovering it was always allowed.
  RealizationMoment({
    required this.position,
    required this.metricOffset,
    required List<RealizedNote> notes,
  }) : notes = List.unmodifiable(notes) {
    final playing = <Hand>{};
    for (final note in notes) {
      for (final hand in note.hands) {
        if (!playing.add(hand)) {
          throw ArgumentError.value(
            notes,
            'notes',
            'a hand plays at most one note per moment',
          );
        }
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
/// The single answer to "which notes, in what order, in which hand". Staff
/// rendering, a progress indicator, fingering annotation, and the alignment of
/// an observed performance all need that answer, and deriving it twice is how
/// two definitions of the same exercise start to disagree.
///
/// Deliberately not measurement. There is no wall-clock timing here, no
/// tolerance, no notion of a note being played early, late, wrongly, or not at
/// all. A realization says what the task is; relating a performance to it is
/// `keyrecall_alignment`'s job.
///
/// Derived on demand from an [Exercise] and not part of its identity, so
/// nothing about it reaches candidate generation, ranking, or persisted
/// records.
@immutable
class ExerciseRealization {
  /// The moments, in the order they are played.
  final List<RealizationMoment> moments;

  /// Throws [ArgumentError] when there is nothing to play.
  ///
  /// An exercise that asks for no notes is not a task, and [lowestPitch] and
  /// [highestPitch] would fail on it anyway.
  ExerciseRealization(List<RealizationMoment> moments)
    : moments = List.unmodifiable(moments) {
    if (this.moments.isEmpty) {
      throw ArgumentError.value(moments, 'moments', 'must not be empty');
    }
  }

  /// The whole exercise [octaves] higher, or lower for a negative count.
  ///
  /// Every note moves together, so the shape, the intervals, and the distance
  /// between the hands are all preserved. Which C a scale starts on is a
  /// property of the realization, not of the scale.
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

/// The register boundary the two hands are placed against.
///
/// A V1 convention, not a fact about the material. Nothing yet lets a learner
/// ask for a different register.
const int _middleC = 60;

/// Where [hand]'s tonic sits for a traversal of [octaves] octaves.
///
/// Middle C is the boundary both hands are placed against, from opposite
/// sides: the right hand begins near it, and the left hand *finishes* near it.
///
/// The left hand is anchored by where it ends rather than where it begins
/// because a fixed floor climbs. Anchored at the bottom, two octaves put the
/// entire second octave above middle C, in the other hand's register and four
/// ledger lines above the bass staff, which is neither how the scale is
/// practiced nor how it is written.
///
/// Near, not at or beyond. Insisting the boundary is never crossed drops a
/// tonic a whole octave to avoid clearing it by a step: two octaves of D in
/// the left hand would run from D1 rather than D2, to end two semitones lower.
/// Rounding to the closer octave keeps every key within half an octave of the
/// hand's home instead.
///
/// One consequence for hands-together work: at one octave the two hands come
/// out the conventional octave apart, and at two they come out two octaves
/// apart rather than the octave a pianist would expect.
int _tonicFor(Hand hand, int pitchClass, int octaves) => switch (hand) {
  Hand.right => _nearestTonic(_middleC, pitchClass),
  Hand.left => _nearestTonic(_middleC - 12 * octaves, pitchClass),
};

/// Where each hand's line begins.
///
/// Parallel motion anchors each hand against its own register. Contrary motion
/// starts them on one shared tonic, so the hands begin in unison and move
/// apart, both thumbs on the same key.
///
/// **That placement is this realization's choice, not what contrary motion
/// means.** [HandMotion.contrary] says only that the two trajectories run in
/// opposite directions; hands that begin octaves apart and converge are
/// contrary too. A later pattern that wants a different geometry chooses it
/// here rather than by redefining the axis.
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
/// into the octave below it. For a degree at or above the tonic this is the
/// ordinary reading, which is what keeps parallel motion unchanged.
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
  final intervals = scaleFormIntervals[material.form]!;
  final conditions = exercise.conditions;

  final hands = [
    if (conditions.hands.usesLeftHand) Hand.left,
    if (conditions.hands.usesRightHand) Hand.right,
  ];
  final paths = handPathsFor(conditions, degreesPerOctave: intervals.length);
  final tonics = _tonicsFor(conditions, hands, pitchClassOf(material.tonic));

  // Every hand plays at every moment in V1, so the paths are read in lockstep.
  // Independent here means the degrees may differ, not the event structure; a
  // pattern where one hand rests or subdivides would need moments built from
  // the union of the paths rather than from a shared index.
  final positions = paths.values.first.length;
  assert(
    paths.values.every((path) => path.length == positions),
    'every hand path covers every moment',
  );

  return ExerciseRealization([
    for (var position = 0; position < positions; position++)
      RealizationMoment(
        position: position,
        // One note to a beat, which is all a scale asks for and all the
        // conditions can currently express.
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
/// Keyed by the key rather than by the spelling, because it is the key the
/// instrument reports: two hands on one note-on have to be one expected note or
/// the attempt can never be complete. Insertion order is [hands] order, so
/// hands that do not meet produce exactly what they did before.
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
