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

  AllocationHistory._({
    required this.counters,
    required this.basis,
    required this.observed,
    required Map<AllocationGap, int> gaps,
    required this.staleDecisions,
    required this.instrumentedFrom,
  }) : gaps = Map.unmodifiable(gaps);

  /// Throws [JournalFormatException] for an acquisition attempt placed after
  /// more ordinary attempts than [attempts] holds.
  factory AllocationHistory.of(
    AttemptJournal attempts,
    AcquisitionJournal acquisition,
  ) {
    var counters = const WaitCounters.empty();
    var observed = 0, stale = 0, position = 0;
    int? instrumentedFrom;
    final gaps = <AllocationGap, int>{};
    var attemptsBefore = 0, acquisitionAttemptsBefore = 0;

    void fold(AllocationRecord allocation) {
      switch (allocation) {
        case AllocationObserved(:final basis, :final evidence):
          counters = counters.advance(evidence);
          observed++;
          instrumentedFrom ??= position;
          if (basis.attempts != attemptsBefore ||
              basis.acquisitionAttempts != acquisitionAttemptsBefore) {
            stale++;
          }
        case AllocationUnobserved(:final gap):
          gaps.update(gap, (n) => n + 1, ifAbsent: () => 1);
      }
      position++;
    }

    final placed = <(int, AcquisitionAttemptRecord)>[];
    var last = 0;
    for (final record in acquisition.attempts) {
      final at = record.attemptsBefore ?? last;
      if (at > attempts.length) {
        throw JournalFormatException(
          'acquisition attempt ${record.identity.attemptId} is placed after '
          '$at ordinary attempts, but history holds ${attempts.length}',
        );
      }
      placed.add((at, record));
      last = at;
    }

    final records = attempts.records;
    var next = 0;
    for (var n = 0; n <= records.length; n++) {
      while (next < placed.length && placed[next].$1 == n) {
        fold(placed[next].$2.allocation);
        acquisitionAttemptsBefore++;
        next++;
      }
      if (n == records.length) break;
      fold(records[n].allocation);
      attemptsBefore++;
    }

    return AllocationHistory._(
      counters: counters,
      basis: AllocationBasis(
        attempts: attemptsBefore,
        acquisitionAttempts: acquisitionAttemptsBefore,
      ),
      observed: observed,
      gaps: gaps,
      staleDecisions: stale,
      instrumentedFrom: instrumentedFrom,
    );
  }
}
