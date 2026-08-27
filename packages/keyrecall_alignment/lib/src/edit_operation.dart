import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// How an observed note differs from the one that was expected there.
///
/// Descriptive, not a severity ranking. An octave error is plausibly a fact
/// about where the hand went rather than about remembering the scale, and
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

/// One relationship between a note that was asked for and one that was played.
///
/// The expected side names the [Hand] that was asked to play, because the
/// realization says so. The observed side names an arrival, because that is all
/// an observation carries: which hand pressed a key is a conclusion alignment
/// reaches by correspondence, never a property of the note.
@immutable
sealed class NoteEdit {
  const NoteEdit();

  /// The observation this consumed, or null when it consumed none.
  int? get observedSequence;
}

/// The expected note was played.
@immutable
final class Match extends NoteEdit {
  /// The hand that was asked to play it.
  final Hand hand;

  @override
  final int observedSequence;

  const Match({required this.hand, required this.observedSequence});

  @override
  bool operator ==(Object other) =>
      other is Match &&
      other.hand == hand &&
      other.observedSequence == observedSequence;

  @override
  int get hashCode => Object.hash(hand, observedSequence);

  @override
  String toString() => 'Match(${hand.id} <- $observedSequence)';
}

/// Something else was played for the expected note.
@immutable
final class Substitution extends NoteEdit {
  /// The hand that was asked to play it.
  final Hand hand;

  @override
  final int observedSequence;

  /// What was asked for.
  final SpelledPitch expected;

  /// What arrived instead.
  final SpelledPitch observed;

  const Substitution({
    required this.hand,
    required this.observedSequence,
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
      other.hand == hand &&
      other.observedSequence == observedSequence &&
      other.expected == expected &&
      other.observed == observed;

  @override
  int get hashCode => Object.hash(hand, observedSequence, expected, observed);

  @override
  String toString() =>
      'Substitution(${hand.id} <- $observedSequence, '
      '${expected.label} vs ${observed.label}, ${kind.id})';
}

/// A note nobody asked for.
@immutable
final class Insertion extends NoteEdit {
  @override
  final int observedSequence;

  /// What was played.
  final SpelledPitch observed;

  const Insertion({required this.observedSequence, required this.observed});

  @override
  bool operator ==(Object other) =>
      other is Insertion &&
      other.observedSequence == observedSequence &&
      other.observed == observed;

  @override
  int get hashCode => Object.hash(observedSequence, observed);

  @override
  String toString() => 'Insertion($observedSequence, ${observed.label})';
}

/// An expected note that never arrived.
@immutable
final class Deletion extends NoteEdit {
  /// The hand that was asked to play it.
  final Hand hand;

  /// What was asked for.
  final SpelledPitch expected;

  const Deletion({required this.hand, required this.expected});

  @override
  int? get observedSequence => null;

  @override
  bool operator ==(Object other) =>
      other is Deletion && other.hand == hand && other.expected == expected;

  @override
  int get hashCode => Object.hash(hand, expected);

  @override
  String toString() => 'Deletion(${hand.id}, ${expected.label})';
}

const _noteEditEquality = ListEquality<NoteEdit>();

/// One relationship between a moment of the realization and the observations
/// that account for it.
///
/// The alphabet of an edit script, one level above the notes. A moment that
/// asks for one note produces one note edit, so single-hand material is this
/// shape with everything inside it singular.
@immutable
sealed class MomentOperation {
  /// The note edits, ordered by the observation each consumed, with edits that
  /// consumed none last.
  final List<NoteEdit> noteEdits;

  MomentOperation({required List<NoteEdit> noteEdits})
    : noteEdits = List.unmodifiable(noteEdits);

  /// Which moment of the realization, or null when nothing was expected.
  int? get realizationPosition;

  /// The observations this consumed, in arrival order.
  List<int> get observedSequences => [
    for (final edit in noteEdits) ?edit.observedSequence,
  ];
}

/// A moment of the realization, and what was played for it.
///
/// Carries when the moment happened, taken from the observations the search
/// assigned to it. Reading that off the transcript again later would be a
/// second answer to a question correspondence has already settled.
@immutable
final class MomentCorrespondence extends MomentOperation {
  @override
  final int realizationPosition;

  /// When the moment happened: the median arrival of the observations it
  /// consumed.
  ///
  /// Median rather than earliest, so a spread attack does not drag the moment
  /// toward whichever finger led. Fractional for an even-sized run, since this
  /// is a derived quantity rather than an arrival.
  final double onsetMs;

  /// How far apart the hands were, as right minus left.
  ///
  /// Present only where both hands corresponded to an observation. A wrong
  /// pitch still says when that hand acted, so a substitution counts; a hand
  /// that played nothing leaves this absent rather than zero.
  final int? handAsynchronyMs;

  MomentCorrespondence({
    required this.realizationPosition,
    required super.noteEdits,
    required this.onsetMs,
    this.handAsynchronyMs,
  });

  @override
  bool operator ==(Object other) =>
      other is MomentCorrespondence &&
      other.realizationPosition == realizationPosition &&
      other.onsetMs == onsetMs &&
      other.handAsynchronyMs == handAsynchronyMs &&
      _noteEditEquality.equals(other.noteEdits, noteEdits);

  @override
  int get hashCode => Object.hash(
    realizationPosition,
    onsetMs,
    handAsynchronyMs,
    _noteEditEquality.hash(noteEdits),
  );

  @override
  String toString() =>
      'MomentCorrespondence($realizationPosition <- $observedSequences)';
}

/// A moment of the realization that nothing arrived for.
@immutable
final class MomentDeletion extends MomentOperation {
  @override
  final int realizationPosition;

  MomentDeletion({required this.realizationPosition, required super.noteEdits});

  @override
  bool operator ==(Object other) =>
      other is MomentDeletion &&
      other.realizationPosition == realizationPosition &&
      _noteEditEquality.equals(other.noteEdits, noteEdits);

  @override
  int get hashCode =>
      Object.hash(realizationPosition, _noteEditEquality.hash(noteEdits));

  @override
  String toString() => 'MomentDeletion($realizationPosition)';
}

/// Playing that no moment of the realization asked for.
@immutable
final class MomentInsertion extends MomentOperation {
  MomentInsertion({required super.noteEdits});

  @override
  int? get realizationPosition => null;

  @override
  bool operator ==(Object other) =>
      other is MomentInsertion &&
      _noteEditEquality.equals(other.noteEdits, noteEdits);

  @override
  int get hashCode => _noteEditEquality.hash(noteEdits);

  @override
  String toString() => 'MomentInsertion($observedSequences)';
}

/// A note edit and the realization position of the moment it belongs to.
typedef PositionedNoteEdit = ({int? realizationPosition, NoteEdit edit});
