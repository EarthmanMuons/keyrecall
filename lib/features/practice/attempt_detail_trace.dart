import 'package:flutter/foundation.dart';

import 'package:keyrecall_alignment/keyrecall_alignment.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

@immutable
class AttemptTracePoint {
  const AttemptTracePoint({required this.position, required this.value});

  final int position;
  final double value;
}

enum NoteMomentStatus { matched, departed, missing }

enum NoteDepartureKind { changed, missing, extra }

@immutable
class NoteDeparture {
  const NoteDeparture({
    required this.kind,
    required this.noteLabel,
    required this.position,
    this.beforePosition,
    this.afterPosition,
  });

  final NoteDepartureKind kind;
  final String noteLabel;
  final double position;
  final int? beforePosition;
  final int? afterPosition;
}

@immutable
class FlowGap {
  const FlowGap({required this.beforePosition, required this.durationMs});

  final int beforePosition;
  final double durationMs;
}

@immutable
class AttemptDetailTrace {
  AttemptDetailTrace({
    required this.momentCount,
    required Iterable<AttemptTracePoint> pulse,
    required Iterable<AttemptTracePoint> coordination,
    required Iterable<NoteMomentStatus> notes,
    required Iterable<NoteDeparture> noteDepartures,
    this.flowGap,
  }) : pulse = List.unmodifiable(pulse),
       coordination = List.unmodifiable(coordination),
       notes = List.unmodifiable(notes),
       noteDepartures = List.unmodifiable(noteDepartures);

  final int momentCount;

  /// Interval deviations, minus whichever interval [flowGap] already accounts
  /// for. A pronounced break is a flow event; charting it here would show the
  /// same pause twice and swamp the scale the rest is read against.
  final List<AttemptTracePoint> pulse;
  final List<AttemptTracePoint> coordination;
  final List<NoteMomentStatus> notes;
  final List<NoteDeparture> noteDepartures;
  final FlowGap? flowGap;

  int get extraNotes => noteDepartures
      .where((departure) => departure.kind == NoteDepartureKind.extra)
      .length;
}

/// What review shows about [reading], read from the evidence measurement read.
///
/// Every timing point comes from the performance clock through the same gaps
/// and hand spreads the scores were computed from, so a hole the clock could
/// not place stays a hole here and an attempt with no timing charts none.
AttemptDetailTrace attemptDetailTraceFor(PerformanceReading reading) {
  final measurement = reading.measurement;
  final timing = measurement.timing;

  FlowGap? flowGap;
  final gapPosition = timing.longestGapBeforePosition;
  if (gapPosition != null && (reading.outcome.continuity ?? 1) < 1) {
    for (final gap in timing.gaps) {
      if (gap.toPosition == gapPosition) {
        flowGap = FlowGap(
          beforePosition: gapPosition,
          durationMs: gap.gapMs.toDouble(),
        );
        break;
      }
    }
  }

  final pace = timing.paceMs;
  final pulse = <AttemptTracePoint>[
    // Charted only where the pulse score was read, so the chart never
    // explains a score nobody measured.
    if (pace != null && timing.dispersion != null)
      for (final gap in timing.gaps)
        if (gap.toPosition == gap.fromPosition + 1 &&
            gap.toPosition != flowGap?.beforePosition)
          AttemptTracePoint(position: gap.toPosition, value: pace - gap.gapMs),
  ];

  final notes = List<NoteMomentStatus>.filled(
    measurement.expectedMoments,
    NoteMomentStatus.missing,
  );
  final noteDepartures = <NoteDeparture>[];
  final operations = measurement.alignment.operations;
  for (final (index, operation) in operations.indexed) {
    final insertionLocation = switch (operation) {
      MomentCorrespondence(:final realizationPosition) => (
        position: realizationPosition.toDouble(),
        before: realizationPosition,
        after: realizationPosition,
      ),
      MomentInsertion() => _insertionLocation(operations, index),
      MomentDeletion() => null,
    };
    for (final edit in operation.noteEdits) {
      switch (edit) {
        case Match():
          break;
        case Substitution(:final expected):
          noteDepartures.add(
            NoteDeparture(
              kind: NoteDepartureKind.changed,
              noteLabel: expected.prettyLabel,
              position: operation.realizationPosition!.toDouble(),
            ),
          );
        case Deletion(:final expected):
          noteDepartures.add(
            NoteDeparture(
              kind: NoteDepartureKind.missing,
              noteLabel: expected.prettyLabel,
              position: operation.realizationPosition!.toDouble(),
            ),
          );
        case Insertion(:final observed):
          final location = insertionLocation!;
          noteDepartures.add(
            NoteDeparture(
              kind: NoteDepartureKind.extra,
              noteLabel: observed.prettyLabel,
              position: location.position,
              beforePosition: location.before,
              afterPosition: location.after,
            ),
          );
      }
    }
    switch (operation) {
      case MomentCorrespondence(:final realizationPosition, :final noteEdits):
        notes[realizationPosition] =
            noteEdits
                .where((edit) => edit is! Insertion)
                .every((edit) => edit is Match)
            ? NoteMomentStatus.matched
            : NoteMomentStatus.departed;
      case MomentDeletion():
      case MomentInsertion():
        break;
    }
  }

  return AttemptDetailTrace(
    momentCount: measurement.expectedMoments,
    pulse: pulse,
    coordination: [
      for (final moment in measurement.handAsynchronies)
        AttemptTracePoint(
          position: moment.position,
          value: -moment.asynchronyMs.toDouble(),
        ),
    ],
    notes: notes,
    noteDepartures: noteDepartures,
    flowGap: flowGap,
  );
}

({double position, int? before, int? after}) _insertionLocation(
  List<MomentOperation> operations,
  int index,
) {
  int? before;
  for (var cursor = index - 1; cursor >= 0; cursor--) {
    if (operations[cursor].realizationPosition case final position?) {
      before = position;
      break;
    }
  }
  int? after;
  for (var cursor = index + 1; cursor < operations.length; cursor++) {
    if (operations[cursor].realizationPosition case final position?) {
      after = position;
      break;
    }
  }
  if (before == null) {
    return (position: (after ?? 0).toDouble(), before: null, after: after);
  }
  if (after == null) {
    return (position: before.toDouble(), before: before, after: null);
  }
  return (position: (before + after) / 2, before: before, after: after);
}
