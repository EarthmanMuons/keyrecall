import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:meta/meta.dart';

import 'requirement_allocation.dart';

/// Allocation's waiting as committed history leaves it, and how much of that
/// history it could observe.
///
/// Folded from both logs in one order: acquisition attempts placed after `n`
/// ordinary attempts come after attempt `n - 1` and before attempt `n`, in
/// acquisition log order. An acquisition attempt with no place carries no
/// evidence and is counted where the one before it was placed.
@immutable
class AllocationHistory {
  final WaitCounters counters;

  /// What the next decision's counters will have read.
  final AllocationBasis basis;

  /// Events whose evidence was applied.
  final int observed;

  /// Events that contributed nothing, by why.
  final Map<AllocationGap, int> gaps;

  /// Observed events whose decision read counters other than the history
  /// before it, applied as committed.
  final int staleDecisions;

  /// Where in the folded order the first observed event was, or null when
  /// none has been. Counters before it are unavailable rather than zero.
  final int? instrumentedFrom;

  /// Events folded, and the place the last acquisition attempt took.
  final int _position;
  final int _placedAfter;

  AllocationHistory._({
    required this.counters,
    required this.basis,
    required this.observed,
    required Map<AllocationGap, int> gaps,
    required this.staleDecisions,
    required this.instrumentedFrom,
    required int position,
    required int placedAfter,
  }) : gaps = Map.unmodifiable(gaps),
       _position = position,
       _placedAfter = placedAfter;

  static final _empty = AllocationHistory._(
    counters: const WaitCounters.empty(),
    basis: AllocationBasis(attempts: 0, acquisitionAttempts: 0),
    observed: 0,
    gaps: const {},
    staleDecisions: 0,
    instrumentedFrom: null,
    position: 0,
    placedAfter: 0,
  );

  /// Throws [JournalFormatException] for an acquisition attempt placed after
  /// more ordinary attempts than [attempts] holds.
  factory AllocationHistory.of(
    AttemptJournal attempts,
    AcquisitionJournal acquisition,
  ) => _empty._continued(attempts, acquisition)!;

  /// This history carried on through what [attempts] and [acquisition] hold
  /// beyond it, which is what folding them whole would give.
  ///
  /// Assumes the logs extend the ones this was folded from, as appending does.
  /// Folds them whole when what they add does not come after everything
  /// already folded, as an acquisition attempt placed behind it does.
  ///
  /// Throws [JournalFormatException] as [AllocationHistory.of] does.
  AllocationHistory continuedWith(
    AttemptJournal attempts,
    AcquisitionJournal acquisition,
  ) =>
      _continued(attempts, acquisition) ??
      AllocationHistory.of(attempts, acquisition);

  AllocationHistory? _continued(
    AttemptJournal attempts,
    AcquisitionJournal acquisition,
  ) {
    final total = attempts.length;
    if (total < basis.attempts ||
        acquisition.attemptCount < basis.acquisitionAttempts) {
      return null;
    }

    final placed = <(int, AcquisitionAttemptRecord)>[];
    var last = _placedAfter;
    for (final record in acquisition.attemptsFrom(basis.acquisitionAttempts)) {
      final at = record.attemptsBefore ?? last;
      if (at > total) {
        throw JournalFormatException(
          'acquisition attempt ${record.identity.attemptId} is placed after '
          '$at ordinary attempts, but history holds $total',
        );
      }
      if (at < basis.attempts) return null;
      placed.add((at, record));
      last = at;
    }

    var observed = this.observed, stale = staleDecisions, position = _position;
    var instrumentedFrom = this.instrumentedFrom;
    final gaps = Map.of(this.gaps);
    final evidence = <AllocationEvidence>[];
    var attemptsBefore = basis.attempts;
    var acquisitionAttemptsBefore = basis.acquisitionAttempts;

    void fold(AllocationRecord allocation) {
      switch (allocation) {
        case AllocationObserved(basis: final read, evidence: final applied):
          evidence.add(applied);
          observed++;
          instrumentedFrom ??= position;
          if (read.attempts != attemptsBefore ||
              read.acquisitionAttempts != acquisitionAttemptsBefore) {
            stale++;
          }
        case AllocationUnobserved(:final gap):
          gaps.update(gap, (n) => n + 1, ifAbsent: () => 1);
      }
      position++;
    }

    final added = attempts.recordsFrom(basis.attempts).toList();
    var next = 0;
    for (var n = basis.attempts; n <= total; n++) {
      while (next < placed.length && placed[next].$1 == n) {
        fold(placed[next].$2.allocation);
        acquisitionAttemptsBefore++;
        next++;
      }
      if (n == total) break;
      fold(added[n - basis.attempts].allocation);
      attemptsBefore++;
    }

    return AllocationHistory._(
      counters: counters.advanceAll(evidence),
      basis: AllocationBasis(
        attempts: attemptsBefore,
        acquisitionAttempts: acquisitionAttemptsBefore,
      ),
      observed: observed,
      gaps: gaps,
      staleDecisions: stale,
      instrumentedFrom: instrumentedFrom,
      position: position,
      placedAfter: last,
    );
  }
}
