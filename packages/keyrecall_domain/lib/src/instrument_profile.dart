import 'package:meta/meta.dart';

/// What the connected instrument can physically play.
///
/// Consulted during candidate generation, before any learner state, so an
/// impossible exercise never becomes a candidate.
@immutable
class InstrumentProfile {
  /// How many keys the instrument has.
  final int keyCount;

  const InstrumentProfile({this.keyCount = 88});

  /// Whether a traversal of [octaves] octaves fits on this instrument.
  ///
  /// A deliberately simple proxy for real register and capability checking,
  /// which needs domain data that does not exist yet.
  bool supportsOctaveSpan(int octaves) => octaves * 12 <= keyCount;

  @override
  bool operator ==(Object other) =>
      other is InstrumentProfile && other.keyCount == keyCount;

  @override
  int get hashCode => keyCount.hashCode;

  @override
  String toString() => 'InstrumentProfile($keyCount keys)';
}
