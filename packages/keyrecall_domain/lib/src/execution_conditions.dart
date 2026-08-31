import 'package:meta/meta.dart';

import 'competency.dart';

/// Which hand or hands play the exercise.
///
/// The hands are distinct motor systems with their own competencies, and
/// playing them together is a third coordination problem rather than the sum
/// of the two.
enum HandConfiguration {
  right('RIGHT'),
  left('LEFT'),
  together('TOGETHER');

  const HandConfiguration(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The hand configuration with the given [id].
  ///
  /// Throws [ArgumentError] when no configuration matches.
  static HandConfiguration fromId(String id) => values.firstWhere(
    (hands) => hands.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'unknown hand configuration'),
  );

  /// Whether this configuration involves the right hand.
  bool get usesRightHand => this != HandConfiguration.left;

  /// Whether this configuration involves the left hand.
  bool get usesLeftHand => this != HandConfiguration.right;

  /// The broad execution competencies this configuration exercises.
  Set<Competency> get executionCompetencies => {
    if (usesRightHand) Competency.rhScaleExecution,
    if (usesLeftHand) Competency.lhScaleExecution,
    if (this == HandConfiguration.together)
      Competency.handsTogetherCoordination,
  };
}

/// Which way the exercise traverses the scale.
enum ScaleDirection {
  /// Ascending only.
  up('UP'),

  /// Ascending, then descending, so the attempt contains a reversal.
  upDown('UP_DOWN');

  const ScaleDirection(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The direction with the given [id].
  ///
  /// Throws [ArgumentError] when no direction matches.
  static ScaleDirection fromId(String id) => values.firstWhere(
    (direction) => direction.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown direction'),
  );
}

/// How the two hands move relative to each other.
///
/// Orthogonal to [ScaleDirection], which is the traversal of one line in time:
/// both hands traverse the same `upDown` exercise whether they move together or
/// apart.
enum HandMotion {
  /// Both hands play the same scale degree at each position, an octave or more
  /// apart. The only motion a single hand can be said to have.
  parallel('PARALLEL'),

  /// The hands mirror each other, the right ascending as the left descends.
  contrary('CONTRARY');

  const HandMotion(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The motion with the given [id].
  ///
  /// Throws [ArgumentError] when no motion matches.
  static HandMotion fromId(String id) => values.firstWhere(
    (motion) => motion.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown hand motion'),
  );
}

/// How an exercise is performed: hand, direction, octave span, and tempo.
///
/// These are parameters of one performance, not part of material identity.
/// Two exercises over the same material under different conditions share a
/// memory state but carry separate execution residuals.
@immutable
class ExecutionConditions {
  /// Which hand or hands play.
  final HandConfiguration hands;

  /// How many octaves the traversal spans.
  final int octaves;

  /// Which way the traversal runs.
  final ScaleDirection direction;

  /// How the hands move relative to each other.
  ///
  /// Meaningful only when [hands] is [HandConfiguration.together]. A single
  /// hand carries [HandMotion.parallel] as the canonical value, which keeps
  /// this off the nullable path that identity, hashing and the frontier key
  /// would otherwise have to carry.
  final HandMotion handMotion;

  /// The requested tempo in beats per minute.
  final double tempoBpm;

  /// Throws [ArgumentError] for a span or tempo that cannot be played, or for
  /// [HandMotion.contrary] with anything but two hands.
  ///
  /// The motor-difficulty score takes the log of the tempo ratio, so a
  /// nonpositive or non-finite tempo would silently produce a meaningless
  /// difficulty rather than failing where the bad value entered.
  /// One octave, because that is the least-assumptive scale there is: it is
  /// foundation behaviour on every axis, and two octaves carries a
  /// prerequisite of its own. A default that asks a harder question than the
  /// caller meant is invisible policy.
  ExecutionConditions({
    required this.hands,
    this.octaves = 1,
    this.direction = ScaleDirection.upDown,
    this.handMotion = HandMotion.parallel,
    this.tempoBpm = 80,
  }) {
    if (octaves < 1) {
      throw ArgumentError.value(octaves, 'octaves', 'must be at least 1');
    }
    if (handMotion == HandMotion.contrary &&
        hands != HandConfiguration.together) {
      throw ArgumentError.value(
        handMotion.id,
        'handMotion',
        'contrary motion needs both hands, not ${hands.id}',
      );
    }
    if (!tempoBpm.isFinite || tempoBpm <= 0) {
      throw ArgumentError.value(
        tempoBpm,
        'tempoBpm',
        'must be finite and greater than zero',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ExecutionConditions &&
      other.hands == hands &&
      other.octaves == octaves &&
      other.direction == direction &&
      other.handMotion == handMotion &&
      other.tempoBpm == tempoBpm;

  @override
  int get hashCode =>
      Object.hash(hands, octaves, direction, handMotion, tempoBpm);

  @override
  String toString() =>
      'ExecutionConditions(${hands.id}, ${octaves}oct, '
      '${direction.id}, ${handMotion.id}, '
      '${tempoBpm.toStringAsFixed(0)}bpm)';
}
