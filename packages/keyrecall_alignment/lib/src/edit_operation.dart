import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// How an observed note differs from the one that was expected there.
///
/// Descriptive, not a severity ranking. An octave error is plausibly a fact
/// about where the hand was placed rather than about remembering the scale, and
/// keeping the two apart is what lets a later layer treat them differently. It
/// costs the same either way; see [AlignmentPolicy].
enum SubstitutionKind {
  /// A different pitch class entirely.
  pitch('PITCH'),

  /// The right pitch class in the wrong octave.
  register('REGISTER');

  const SubstitutionKind(this.id);

  /// Stable identifier used in traces.
  final String id;
}

/// One relationship between what was asked for and what was played.
///
/// The alphabet of an edit script. Every operation names the realization
/// position it concerns, the transcript note it concerns, or both, so a reader
/// can walk either sequence and know what happened at each point.
@immutable
sealed class EditOperation {
  const EditOperation();
}

/// The expected note was played.
@immutable
final class Match extends EditOperation {
  /// Which moment of the realization.
  final int realizationPosition;

  /// Which note of the transcript.
  final int transcriptSequence;

  const Match({
    required this.realizationPosition,
    required this.transcriptSequence,
  });

  @override
  bool operator ==(Object other) =>
      other is Match &&
      other.realizationPosition == realizationPosition &&
      other.transcriptSequence == transcriptSequence;

  @override
  int get hashCode => Object.hash(realizationPosition, transcriptSequence);

  @override
  String toString() => 'Match($realizationPosition <- $transcriptSequence)';
}

/// Something was played where the expected note should have been.
@immutable
final class Substitution extends EditOperation {
  /// Which moment of the realization.
  final int realizationPosition;

  /// Which note of the transcript.
  final int transcriptSequence;

  /// What was asked for there.
  final SpelledPitch expected;

  /// What arrived instead.
  final SpelledPitch observed;

  const Substitution({
    required this.realizationPosition,
    required this.transcriptSequence,
    required this.expected,
    required this.observed,
  });

  /// Whether the pitch class was right and only the octave wrong.
  SubstitutionKind get kind => expected.pitchClass == observed.pitchClass
      ? SubstitutionKind.register
      : SubstitutionKind.pitch;

  @override
  bool operator ==(Object other) =>
      other is Substitution &&
      other.realizationPosition == realizationPosition &&
      other.transcriptSequence == transcriptSequence &&
      other.expected == expected &&
      other.observed == observed;

  @override
  int get hashCode =>
      Object.hash(realizationPosition, transcriptSequence, expected, observed);

  @override
  String toString() =>
      'Substitution($realizationPosition <- $transcriptSequence, '
      '${expected.label} vs ${observed.label}, ${kind.id})';
}

/// A note nobody asked for.
@immutable
final class Insertion extends EditOperation {
  /// Which note of the transcript.
  final int transcriptSequence;

  /// What was played.
  final SpelledPitch observed;

  const Insertion({required this.transcriptSequence, required this.observed});

  @override
  bool operator ==(Object other) =>
      other is Insertion &&
      other.transcriptSequence == transcriptSequence &&
      other.observed == observed;

  @override
  int get hashCode => Object.hash(transcriptSequence, observed);

  @override
  String toString() => 'Insertion($transcriptSequence, ${observed.label})';
}

/// An expected note that never arrived.
@immutable
final class Deletion extends EditOperation {
  /// Which moment of the realization.
  final int realizationPosition;

  /// What was asked for there.
  final SpelledPitch expected;

  const Deletion({required this.realizationPosition, required this.expected});

  @override
  bool operator ==(Object other) =>
      other is Deletion &&
      other.realizationPosition == realizationPosition &&
      other.expected == expected;

  @override
  int get hashCode => Object.hash(realizationPosition, expected);

  @override
  String toString() => 'Deletion($realizationPosition, ${expected.label})';
}
