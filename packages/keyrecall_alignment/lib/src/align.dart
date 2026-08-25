import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'alignment_policy.dart';
import 'edit_operation.dart';

const _operationEquality = ListEquality<EditOperation>();

/// How a performance relates to what the exercise asked for.
///
/// The edit script and nothing else. Whether the attempt was any good, whether
/// it counts as retrieval, and what it says about a competency are all
/// readings of this, made elsewhere.
@immutable
class Alignment {
  /// The relationships, in the order both sequences run.
  final List<EditOperation> operations;

  /// What this explanation cost under the policy that produced it.
  final int cost;

  /// The policy that produced it.
  final AlignmentPolicy policy;

  Alignment({
    required List<EditOperation> operations,
    required this.cost,
    required this.policy,
  }) : operations = List.unmodifiable(operations);

  @override
  bool operator ==(Object other) =>
      other is Alignment &&
      other.cost == cost &&
      _operationEquality.equals(other.operations, operations);

  @override
  int get hashCode => Object.hash(cost, _operationEquality.hash(operations));

  @override
  String toString() => 'Alignment(${operations.length} operations, $cost)';
}

/// Relates [transcript] to what [realization] asked for.
///
/// Returns the minimum-cost complete edit script under [policy]: every expected
/// note and every played note appears exactly once, in one operation.
///
/// Global rather than greedy, and that is the point. A single extra note early
/// in a scale has one cheap explanation, an insertion, and one expensive one,
/// a substitution at every remaining position; walking the sequences and
/// deciding locally picks the expensive one and never recovers. Resynchronizing
/// after a skip, an extra, or a correction falls out of choosing the whole
/// explanation at once.
///
/// Pitch only. Nothing here reads a timestamp, because relating arrival times
/// to expected times needs a tempo model that does not exist, and inventing one
/// inside an aligner would hide it.
///
/// Single-hand only for now. Hands-together material needs observations grouped
/// into moments first, and grouping cannot be decided from timing alone; see
/// `docs/domain-model/alignment-contract.md`.
///
/// Throws [ArgumentError] when [realization] uses more than one hand.
Alignment align({
  required ExerciseRealization realization,
  required PerformanceTranscript transcript,
  AlignmentPolicy policy = AlignmentPolicy.standard,
}) {
  if (realization.hands.length > 1) {
    throw ArgumentError.value(
      realization,
      'realization',
      'alignment is single-hand only: hands-together material needs '
          'observations grouped into moments first',
    );
  }

  final hand = realization.hands.single;
  final expected = [
    for (final moment in realization.moments) moment.noteFor(hand)!.pitch,
  ];
  final observed = transcript.notes;

  // cost[i][j] is the cheapest way to explain the first i expected notes with
  // the first j played ones.
  final cost = List.generate(
    expected.length + 1,
    (_) => List<int>.filled(observed.length + 1, 0),
  );
  for (var i = 1; i <= expected.length; i++) {
    cost[i][0] = i * policy.deletionCost;
  }
  for (var j = 1; j <= observed.length; j++) {
    cost[0][j] = j * policy.insertionCost;
  }

  for (var i = 1; i <= expected.length; i++) {
    for (var j = 1; j <= observed.length; j++) {
      final same = expected[i - 1].midiNote == observed[j - 1].midiNote;
      final diagonal =
          cost[i - 1][j - 1] +
          (same ? AlignmentPolicy.matchCost : policy.substitutionCost);
      final deletion = cost[i - 1][j] + policy.deletionCost;
      final insertion = cost[i][j - 1] + policy.insertionCost;
      cost[i][j] = _smallest(diagonal, deletion, insertion);
    }
  }

  return Alignment(
    operations: _traceBack(cost, expected, observed, policy),
    cost: cost[expected.length][observed.length],
    policy: policy,
  );
}

int _smallest(int a, int b, int c) => a < b ? (a < c ? a : c) : (b < c ? b : c);

/// Walks the table back to the script that produced the cheapest cost.
///
/// Ties are broken in a fixed order so one performance always aligns the same
/// way. Replay depends on that: an aligner that could return either of two
/// equal-cost readings would make the evidence derived from it irreproducible.
///
/// The order puts deletion before the diagonal, which places a performance as
/// early in the traversal as its cost allows. That matters whenever a pitch
/// appears more than once: a scale played up and back down begins and ends on
/// the tonic, so a single played tonic explains equally well as the first note
/// or the last, and reading it as the last would say a learner who has played
/// one note has reached the end.
List<EditOperation> _traceBack(
  List<List<int>> cost,
  List<SpelledPitch> expected,
  List<PlayedNote> observed,
  AlignmentPolicy policy,
) {
  final operations = <EditOperation>[];
  var i = expected.length;
  var j = observed.length;

  while (i > 0 || j > 0) {
    if (i > 0 && cost[i][j] == cost[i - 1][j] + policy.deletionCost) {
      operations.add(
        Deletion(realizationPosition: i - 1, expected: expected[i - 1]),
      );
      i--;
      continue;
    }
    if (i > 0 && j > 0) {
      final same = expected[i - 1].midiNote == observed[j - 1].midiNote;
      final step = same ? AlignmentPolicy.matchCost : policy.substitutionCost;
      if (cost[i][j] == cost[i - 1][j - 1] + step) {
        operations.add(
          same
              ? Match(
                  realizationPosition: i - 1,
                  transcriptSequence: observed[j - 1].sequence,
                )
              : Substitution(
                  realizationPosition: i - 1,
                  transcriptSequence: observed[j - 1].sequence,
                  expected: expected[i - 1],
                  observed: observed[j - 1].pitch,
                ),
        );
        i--;
        j--;
        continue;
      }
    }
    operations.add(
      Insertion(
        transcriptSequence: observed[j - 1].sequence,
        observed: observed[j - 1].pitch,
      ),
    );
    j--;
  }

  return operations.reversed.toList();
}
