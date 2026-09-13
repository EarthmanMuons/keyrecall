import 'package:meta/meta.dart';

import 'realization.dart';

/// What the connected instrument can physically play.
///
/// Consulted during candidate generation, before any learner state, so an
/// impossible exercise never becomes a candidate.
@immutable
class InstrumentProfile {
  /// How many keys the instrument has.
  final int keyCount;

  /// Throws [ArgumentError] for an instrument with no keys.
  InstrumentProfile({this.keyCount = 88}) {
    if (keyCount < 1) {
      throw ArgumentError.value(keyCount, 'keyCount', 'must be at least 1');
    }
  }

  /// Whether [lowestPitch] through [highestPitch] fits within the keys.
  ///
  /// Both endpoints are played, so a one-octave traversal wants thirteen keys
  /// rather than twelve.
  ///
  /// Throws [ArgumentError] for a range that runs backwards, which would
  /// measure a negative width and fit anything.
  bool supportsPitchRange(int lowestPitch, int highestPitch) {
    if (highestPitch < lowestPitch) {
      throw ArgumentError.value(
        highestPitch,
        'highestPitch',
        'must not fall below $lowestPitch',
      );
    }
    return highestPitch - lowestPitch + 1 <= keyCount;
  }

  /// Whether [realization] is narrow enough to fit on this instrument.
  ///
  /// Width, not register: a profile carrying only a key count can say that
  /// some placement of the exercise fits, not that this one does. Answering
  /// the second needs the instrument's lowest and highest playable notes.
  bool supportsRealizationWidth(ExerciseRealization realization) =>
      supportsPitchRange(realization.lowestPitch, realization.highestPitch);

  @override
  bool operator ==(Object other) =>
      other is InstrumentProfile && other.keyCount == keyCount;

  @override
  int get hashCode => keyCount.hashCode;

  @override
  String toString() => 'InstrumentProfile($keyCount keys)';
}
