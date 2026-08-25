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
  bool get isComplete => alignment.operations.whereType<Deletion>().isEmpty;

  /// Nothing but matches: the performance was right the first time.
  ///
  /// The strict reading, and the one that must not be reachable by repairing
  /// mistakes as you go. An attempt that arrived at the end after three
  /// corrections is complete and not first-pass clean.
  bool get isFirstPassClean =>
      alignment.operations.every((operation) => operation is Match);

  /// Extra notes immediately followed by the expected one.
  ///
  /// What a learner does when they hear a wrong note and fix it. Counted
  /// because a repaired attempt is practice rather than recall, and the two
  /// must not read the same.
  int get selfCorrections {
    var corrections = 0;
    for (var i = 0; i < alignment.operations.length - 1; i++) {
      if (alignment.operations[i] is Insertion &&
          alignment.operations[i + 1] is Match) {
        corrections++;
      }
    }
    return corrections;
  }

  /// Expected notes that were played as written.
  int get matched => alignment.operations.whereType<Match>().length;

  /// Expected notes that something else was played for.
  int get substituted => alignment.operations.whereType<Substitution>().length;

  /// Notes played that nothing asked for.
  int get inserted => alignment.operations.whereType<Insertion>().length;

  /// Expected notes that never arrived.
  int get deleted => alignment.operations.whereType<Deletion>().length;

  /// Where the performance first departed from what was asked for, or null
  /// when it never did.
  ///
  /// The position a display would point at, and the thing a learner usually
  /// wants to know: not how many mistakes, but where it went wrong.
  int? get firstDeparturePosition {
    for (final operation in alignment.operations) {
      switch (operation) {
        case Match():
          continue;
        case Substitution(:final realizationPosition):
        case Deletion(:final realizationPosition):
          return realizationPosition;
        case Insertion():
          return null;
      }
    }
    return null;
  }

  @override
  String toString() =>
      'AlignmentReading(matched $matched, substituted $substituted, '
      'inserted $inserted, deleted $deleted)';
}
