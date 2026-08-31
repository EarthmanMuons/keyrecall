import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'alignment_policy.dart';
import 'edit_operation.dart';
import 'observation_grouping.dart';

const _operationEquality = ListEquality<MomentOperation>();

/// How a performance relates to what the exercise asked for.
///
/// The edit script and nothing else, moment by moment. Whether the attempt was
/// any good, whether it counts as retrieval, and what it says about a
/// competency are all readings of this, made elsewhere.
@immutable
class Alignment {
  /// The relationships, in the order both sequences run.
  final List<MomentOperation> operations;

  /// What this explanation cost under the policy that produced it.
  final int cost;

  /// The policy that produced it.
  final AlignmentPolicy policy;

  Alignment({
    required List<MomentOperation> operations,
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

  /// Every note edit, in script order, carrying the moment it belongs to.
  List<PositionedNoteEdit> get noteEdits => [
    for (final operation in operations)
      for (final edit in operation.noteEdits)
        (realizationPosition: operation.realizationPosition, edit: edit),
  ];

  @override
  String toString() => 'Alignment(${operations.length} operations, $cost)';
}

/// Relates [transcript] to what [realization] asked for.
///
/// Returns the minimum-cost complete edit script under [policy]: every expected
/// note and every played note appears exactly once, in one note edit, under the
/// moment it belongs to.
///
/// Global rather than greedy, and that is the point. A single extra note early
/// in a scale has one cheap explanation, an insertion, and one expensive one,
/// a substitution at every remaining position; walking the sequences and
/// deciding locally picks the expensive one and never recovers. Resynchronizing
/// after a skip, an extra, or a correction falls out of choosing the whole
/// explanation at once.
///
/// The same search chooses how the observations were grouped. A correspondence
/// consumes one moment and a contiguous run of one to K observations, K being
/// the largest note count of any moment asked for, so which arrivals belong to
/// one performed moment is decided against the realization rather than before
/// it. Timing enters only as [groupObservations] priced it, bounded by
/// [AlignmentPolicy.maxGroupingPreference]: a run pays
/// [ObservationBoundary.sameMomentSurcharge] for each boundary inside it, and
/// splitting anywhere is always affordable.
///
/// Pitch and grouping only. Nothing here reads a timestamp except through that
/// surcharge, because relating arrival times to expected times needs a tempo
/// model that does not exist, and inventing one inside an aligner would hide
/// it.
///
/// Register is relative. The realization anchors the scale somewhere so a
/// staff can draw it, but which C somebody starts on is a property of that
/// anchor and not of the task: the same fingering, the same intervals, the
/// same shape. So the performance is explained against the realization and
/// against the realization shifted by whole octaves, whichever costs less.
///
/// Whole octaves, and the whole realization at once. A single note in the
/// wrong octave still reads as a register substitution, because no shift of
/// everything explains it. Hands together move together, so playing the pair
/// an octave up is right and playing the hands two octaves apart is not: the
/// distance between them is the task, their position on the keyboard is not.
Alignment align({
  required ExerciseRealization realization,
  required PerformanceTranscript transcript,
  AlignmentPolicy policy = AlignmentPolicy.standard,
  ObservationGroupingPolicy groupingPolicy = ObservationGroupingPolicy.standard,
}) {
  final asWritten = _alignExactly(
    realization: realization,
    transcript: transcript,
    policy: policy,
    groupingPolicy: groupingPolicy,
  );
  final shift = _registerShiftFor(realization, transcript);
  if (shift == 0) return asWritten;

  final transposed = _alignExactly(
    realization: realization.shiftedByOctaves(shift),
    transcript: transcript,
    policy: policy,
    groupingPolicy: groupingPolicy,
  );
  return transposed.cost < asWritten.cost ? transposed : asWritten;
}

/// The whole-octave shift that best explains where the performance sat, or
/// zero when the realization's own register explains it.
///
/// The median of what was played against the median of what was asked for,
/// rounded to octaves. The median rather than the first note, because the
/// first note is exactly the one a learner is most likely to have fumbled and
/// reading the whole performance off it would move a scale on one bad start.
///
/// One candidate rather than a search over the keyboard: alignment is
/// quadratic and runs on every arriving note, so this pays for at most one
/// extra pass, and the answer it proposes is the only one the evidence
/// actually suggests.
int _registerShiftFor(
  ExerciseRealization realization,
  PerformanceTranscript transcript,
) {
  if (transcript.notes.isEmpty) return 0;
  final expected = [
    for (final moment in realization.moments)
      for (final note in moment.notes) note.midiNote,
  ]..sort();
  final played = [for (final note in transcript.notes) note.pitch.midiNote]
    ..sort();
  final difference =
      played[played.length ~/ 2] - expected[expected.length ~/ 2];
  return (difference / 12).round();
}

Alignment _alignExactly({
  required ExerciseRealization realization,
  required PerformanceTranscript transcript,
  required AlignmentPolicy policy,
  required ObservationGroupingPolicy groupingPolicy,
}) {
  final moments = realization.moments;
  final observed = transcript.notes;
  final longestRun = moments.fold(
    1,
    (k, moment) => math.max(k, moment.notes.length),
  );

  // Indexed by the later observation of the boundary, so a run starting there
  // pays nothing and a run continuing through it pays the surcharge.
  final surcharge = List<int>.filled(observed.length, 0);
  for (final boundary in groupObservations(
    transcript: transcript,
    policy: groupingPolicy,
    alignmentPolicy: policy,
  ).boundaries) {
    surcharge[boundary.afterSequence] = boundary.sameMomentSurcharge;
  }

  int runSurcharge(int start, int end) {
    var total = 0;
    for (var t = start + 1; t < end; t++) {
      total += surcharge[t];
    }
    return total;
  }

  final correspondence = _MomentMatcher(moments, observed, policy);

  // cost[i][j] is the cheapest way to explain the first i moments with the
  // first j observations.
  final cost = List.generate(
    moments.length + 1,
    (_) => List<int>.filled(observed.length + 1, 0),
  );
  for (var i = 1; i <= moments.length; i++) {
    cost[i][0] =
        cost[i - 1][0] + policy.deletionCost * moments[i - 1].notes.length;
  }
  for (var j = 1; j <= observed.length; j++) {
    cost[0][j] = j * policy.insertionCost;
  }

  for (var i = 1; i <= moments.length; i++) {
    for (var j = 1; j <= observed.length; j++) {
      var best =
          cost[i - 1][j] + policy.deletionCost * moments[i - 1].notes.length;
      for (var run = 1; run <= longestRun && run <= j; run++) {
        final candidate =
            cost[i - 1][j - run] +
            correspondence.costOf(i - 1, j - run, j) +
            runSurcharge(j - run, j);
        if (candidate < best) best = candidate;
      }
      final insertion = cost[i][j - 1] + policy.insertionCost;
      cost[i][j] = insertion < best ? insertion : best;
    }
  }

  return Alignment(
    operations: _traceBack(
      cost,
      moments,
      observed,
      correspondence,
      runSurcharge,
      longestRun,
      policy,
    ),
    cost: cost[moments.length][observed.length],
    policy: policy,
  );
}

/// Walks the table back to the script that produced the cheapest cost.
///
/// Ties are broken in a fixed order so one performance always aligns the same
/// way. Replay depends on that: an aligner that could return either of two
/// equal-cost readings would make the evidence derived from it irreproducible.
///
/// The order puts a missing moment before a correspondence, which places a
/// performance as early in the traversal as its cost allows. That matters
/// whenever a pitch appears more than once: a scale played up and back down
/// begins and ends on the tonic, so a single played tonic explains equally well
/// as the first note or the last, and reading it as the last would say a
/// learner who has played one note has reached the end.
///
/// A moment takes one observation before an extra note is allowed to stand,
/// and an extra stands before a moment takes a second observation. Absorbing
/// another arrival into a moment is the last reading tried, because a longer
/// run hides an extra where nothing shows it arrived.
List<MomentOperation> _traceBack(
  List<List<int>> cost,
  List<RealizationMoment> moments,
  List<PlayedNote> observed,
  _MomentMatcher correspondence,
  int Function(int start, int end) runSurcharge,
  int longestRun,
  AlignmentPolicy policy,
) {
  final operations = <MomentOperation>[];
  var i = moments.length;
  var j = observed.length;

  /// Takes a correspondence of [run] observations, if that is what it cost.
  bool takeRun(int run) {
    if (i == 0 || run > j) return false;
    final candidate =
        cost[i - 1][j - run] +
        correspondence.costOf(i - 1, j - run, j) +
        runSurcharge(j - run, j);
    if (cost[i][j] != candidate) return false;
    operations.add(correspondence.momentFor(i - 1, j - run, j));
    i--;
    j -= run;
    return true;
  }

  while (i > 0 || j > 0) {
    if (i > 0) {
      final missing =
          cost[i - 1][j] + policy.deletionCost * moments[i - 1].notes.length;
      if (cost[i][j] == missing) {
        operations.add(
          MomentDeletion(
            realizationPosition: i - 1,
            noteEdits: [
              for (final note in moments[i - 1].notes)
                Deletion(hands: note.hands, expected: note.pitch),
            ],
          ),
        );
        i--;
        continue;
      }
    }
    if (takeRun(1)) continue;
    if (j > 0 && cost[i][j] == cost[i][j - 1] + policy.insertionCost) {
      operations.add(
        MomentInsertion(
          noteEdits: [
            Insertion(
              observedSequence: observed[j - 1].sequence,
              observed: observed[j - 1].pitch,
            ),
          ],
        ),
      );
      j--;
      continue;
    }
    for (var run = 2; run <= longestRun; run++) {
      if (takeRun(run)) break;
    }
  }

  return operations.reversed.toList();
}

double _medianOf(List<int> values) {
  final ordered = [...values]..sort();
  final middle = ordered.length ~/ 2;
  return ordered.length.isOdd
      ? ordered[middle].toDouble()
      : (ordered[middle - 1] + ordered[middle]) / 2;
}

/// The cheapest reading of one moment against one run of observations.
///
/// Every assignment of the moment's notes to the run is enumerated, since a
/// moment holds at most one note per hand and a run is at most that long. The
/// hand a played note belongs to falls out of the assignment that wins, which
/// is the only place hand identity is decided.
///
/// Assignments are enumerated with the moment's notes in order, each trying the
/// observations in arrival order and then going unplayed, and the first
/// cheapest is kept. Two equally cheap readings therefore always resolve the
/// same way.
class _MomentMatcher {
  final List<RealizationMoment> moments;
  final List<PlayedNote> observed;
  final AlignmentPolicy policy;
  final Map<(int, int, int), ({int cost, List<NoteEdit> edits})> _cache = {};

  _MomentMatcher(this.moments, this.observed, this.policy);

  int costOf(int moment, int start, int end) => _read(moment, start, end).cost;

  /// The operation for [moment] against the run in `[start, end)`.
  MomentCorrespondence momentFor(int moment, int start, int end) {
    final edits = _read(moment, start, end).edits;
    final arrival = {
      for (final note in observed.sublist(start, end))
        note.sequence: note.timestampMs,
    };
    final acted = <Hand, int>{
      for (final edit in edits)
        if (edit
            case Match(:final hands, :final observedSequence) ||
                Substitution(:final hands, :final observedSequence))
          for (final hand in hands) hand: arrival[observedSequence]!,
    };
    final left = acted[Hand.left];
    final right = acted[Hand.right];

    // A note both hands meet on has one onset, so its asynchrony is zero by
    // construction rather than by measurement: there is one key and the
    // instrument reports pressing it once. Reading that as evidence of
    // coordination would credit the learner for what the representation
    // guarantees.
    return MomentCorrespondence(
      realizationPosition: moment,
      noteEdits: edits,
      onsetMs: _medianOf(arrival.values.toList()),
      handAsynchronyMs: left == null || right == null ? null : right - left,
    );
  }

  ({int cost, List<NoteEdit> edits}) _read(int moment, int start, int end) =>
      _cache.putIfAbsent((moment, start, end), () {
        final notes = moments[moment].notes;
        final run = observed.sublist(start, end);
        final assignment = List<int?>.filled(notes.length, null);
        final played = <int>{};
        List<int?>? best;
        int? bestCost;

        void walk(int index, int spent) {
          if (bestCost != null && spent >= bestCost!) return;
          if (index == notes.length) {
            final total =
                spent + policy.insertionCost * (run.length - played.length);
            if (bestCost == null || total < bestCost!) {
              bestCost = total;
              best = [...assignment];
            }
            return;
          }
          for (var candidate = 0; candidate < run.length; candidate++) {
            if (!played.add(candidate)) continue;
            assignment[index] = candidate;
            walk(
              index + 1,
              spent +
                  (notes[index].midiNote == run[candidate].midiNote
                      ? AlignmentPolicy.matchCost
                      : policy.substitutionCost),
            );
            played.remove(candidate);
          }
          assignment[index] = null;
          walk(index + 1, spent + policy.deletionCost);
        }

        walk(0, 0);
        return (cost: bestCost!, edits: _editsFor(notes, run, best!));
      });

  List<NoteEdit> _editsFor(
    List<RealizedNote> notes,
    List<PlayedNote> run,
    List<int?> assignment,
  ) {
    final consumed = <(int, NoteEdit)>[];
    final missing = <NoteEdit>[];
    final played = <int>{};

    for (final (index, note) in notes.indexed) {
      final candidate = assignment[index];
      if (candidate == null) {
        missing.add(Deletion(hands: note.hands, expected: note.pitch));
        continue;
      }
      played.add(candidate);
      final arrival = run[candidate];
      consumed.add((
        candidate,
        note.midiNote == arrival.midiNote
            ? Match(hands: note.hands, observedSequence: arrival.sequence)
            : Substitution(
                hands: note.hands,
                observedSequence: arrival.sequence,
                expected: note.pitch,
                observed: arrival.pitch,
              ),
      ));
    }

    for (final (index, arrival) in run.indexed) {
      if (played.contains(index)) continue;
      consumed.add((
        index,
        Insertion(observedSequence: arrival.sequence, observed: arrival.pitch),
      ));
    }

    consumed.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, edit) in consumed) edit, ...missing];
  }
}
