import 'package:meta/meta.dart';

import 'align.dart';
import 'edit_operation.dart';

/// What an edit script says about how the attempt went.
///
/// Interpretation, kept out of the alignment itself. The script states
/// correspondence: this played note is that expected one, this one was extra,
/// that one never came. What counts as complete, as clean, or as a repair is a
/// reading of those facts, and readings change without the correspondence
/// changing.
///
/// Still not evidence. Turning any of this into an outcome the learner model
/// consumes is a further step, and a separate set of judgments.
@immutable
class AlignmentReading {
  /// The script this reads.
  final Alignment alignment;

  const AlignmentReading(this.alignment);

  /// Every expected note was played, right or wrong.
  ///
  /// A wrong note in the right place still reached that point in the scale;
  /// what is missing here is notes that never arrived at all.
  bool get isComplete => deleted == 0;

  /// Whether the traversal reached its final expected position.
  ///
  /// Progress, not correctness: a substitution covers a position just as a
  /// match does, so playing the wrong note still gets you to the end. What it
  /// does not do is treat extra notes as progress, which is the difference
  /// between "you have played the whole exercise" and "you have played as many
  /// notes as it contains".
  bool get reachedFinalPosition {
    for (final operation in alignment.operations.reversed) {
      switch (operation) {
        case MomentInsertion():
          continue;
        case MomentCorrespondence():
          return true;
        case MomentDeletion():
          return false;
      }
    }
    return false;
  }

  /// Nothing but matches: the performance was right the first time.
  ///
  /// The strict reading, and the one that must not be reachable by repairing
  /// mistakes as you go. An attempt that arrived at the end after three
  /// corrections is complete and not first-pass clean.
  bool get isFirstPassClean =>
      alignment.noteEdits.every((positioned) => positioned.edit is Match);

  /// Extra notes immediately followed by the expected one.
  ///
  /// The shape a repair leaves behind, and only that. Alignment sees an extra
  /// note and then the right one; whether that was hearing a mistake and
  /// fixing it, a hesitation, a repeated key, or a bounced finger is an
  /// internal state nothing here observed. Calling it a self-correction is a
  /// reading for a layer that has grounds for one.
  int get immediateRepairs {
    final edits = alignment.noteEdits;
    var corrections = 0;
    for (var i = 0; i < edits.length - 1; i++) {
      if (edits[i].edit is Insertion && edits[i + 1].edit is Match) {
        corrections++;
      }
    }
    return corrections;
  }

  /// Expected notes that were played as written.
  int get matched => _count<Match>();

  /// Expected notes that something else was played for.
  int get substituted => _count<Substitution>();

  /// Notes played that nothing asked for.
  int get inserted => _count<Insertion>();

  /// Expected notes that never arrived.
  int get deleted => _count<Deletion>();

  int _count<T extends NoteEdit>() =>
      alignment.noteEdits.where((positioned) => positioned.edit is T).length;

  /// The first moment of the realization nothing arrived for, or null when
  /// everything did.
  ///
  /// Where an attempt that did not finish stopped, in the ordinary case. Not
  /// the same question as [firstDeparture], which reports whichever departure
  /// came first including a wrong or extra note: an attempt can play something
  /// wrong at the second moment and still run out at the twelfth.
  int? get firstAbsentPosition {
    for (final operation in alignment.operations) {
      if (operation case MomentDeletion(:final realizationPosition)) {
        return realizationPosition;
      }
    }
    return null;
  }

  /// Where the performance first departed from what was asked for, or null
  /// when it never did.
  ///
  /// Located rather than numbered, because not every departure sits *at* an
  /// expected note. An extra note falls between two of them, and saying it
  /// happened at the following note would put the blame on a note that was
  /// played correctly. A display that wants to say "an extra F before the E"
  /// needs the difference.
  DepartureLocation? get firstDeparture {
    final positions = matched + substituted + deleted;
    var consumed = 0;

    for (final (:realizationPosition, :edit) in alignment.noteEdits) {
      switch (edit) {
        case Match():
          consumed++;
        case Substitution():
        case Deletion():
          return AtExpectedPosition(realizationPosition!);
        case Insertion():
          return consumed == positions
              ? const AfterRealization()
              : BeforeExpectedPosition(consumed);
      }
    }
    return null;
  }

  @override
  String toString() =>
      'AlignmentReading(matched $matched, substituted $substituted, '
      'inserted $inserted, deleted $deleted)';
}

/// Where a performance departed from what was asked for.
///
/// A departure is not always at an expected note: an extra one happens between
/// two of them, and after the last one there is no following note to speak of.
@immutable
sealed class DepartureLocation {
  const DepartureLocation();
}

/// Something other than the expected note happened at this position, or the
/// expected note never arrived.
@immutable
final class AtExpectedPosition extends DepartureLocation {
  /// Which moment of the realization.
  final int position;

  const AtExpectedPosition(this.position);

  @override
  bool operator ==(Object other) =>
      other is AtExpectedPosition && other.position == position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'AtExpectedPosition($position)';
}

/// An extra note arrived before this expected one.
@immutable
final class BeforeExpectedPosition extends DepartureLocation {
  /// Which moment of the realization the extra note preceded.
  final int position;

  const BeforeExpectedPosition(this.position);

  @override
  bool operator ==(Object other) =>
      other is BeforeExpectedPosition && other.position == position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'BeforeExpectedPosition($position)';
}

/// Playing continued past the end of what was asked for.
@immutable
final class AfterRealization extends DepartureLocation {
  const AfterRealization();

  @override
  bool operator ==(Object other) => other is AfterRealization;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'AfterRealization()';
}
