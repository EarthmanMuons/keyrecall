import 'execution_conditions.dart';

/// One hand, as a player rather than as a configuration.
enum Hand {
  left('LEFT'),
  right('RIGHT');

  const Hand(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// Which signed scale degree each hand plays at each moment.
Map<Hand, List<int>> handPathsFor(
  ExecutionConditions conditions, {
  required int degreesPerOctave,
}) {
  final hands = [
    if (conditions.hands.usesLeftHand) Hand.left,
    if (conditions.hands.usesRightHand) Hand.right,
  ];
  final topDegree = degreesPerOctave * conditions.octaves;
  final ascending = [
    for (var degree = 0; degree <= topDegree; degree++) degree,
  ];
  final outward = switch (conditions.direction) {
    ScaleDirection.up => ascending,
    ScaleDirection.upDown => [...ascending, ...ascending.reversed.skip(1)],
  };

  return switch (conditions.handMotion) {
    HandMotion.parallel => {for (final hand in hands) hand: outward},
    HandMotion.contrary => {
      for (final hand in hands)
        hand: hand == Hand.right
            ? outward
            : [for (final degree in outward) -degree],
    },
  };
}
