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
    required Iterable<double> extraNotePositions,
    required this.extraNotes,
    this.flowGap,
  }) : pulse = List.unmodifiable(pulse),
       coordination = List.unmodifiable(coordination),
       notes = List.unmodifiable(notes),
       extraNotePositions = List.unmodifiable(extraNotePositions);

  final int momentCount;
  final List<AttemptTracePoint> pulse;
  final List<AttemptTracePoint> coordination;
  final List<NoteMomentStatus> notes;
  final List<double> extraNotePositions;
  final int extraNotes;
  final FlowGap? flowGap;
}

AttemptDetailTrace attemptDetailTraceFor(PerformanceReading reading) {
  final measurement = reading.measurement;
  final correspondences = [
    for (final operation in measurement.alignment.operations)
      if (operation case MomentCorrespondence()) operation,
  ];
  final timedMoments = [
    for (final operation in correspondences)
      if (operation.noteEdits.any(
        (edit) => edit is Match || edit is Substitution,
      ))
        operation,
  ];
  final medianInterval = measurement.medianIntervalMs;
  final pulse = <AttemptTracePoint>[];
  if (medianInterval != null) {
    for (var index = 1; index < timedMoments.length; index++) {
      final interval =
          timedMoments[index].onsetMs - timedMoments[index - 1].onsetMs;
      pulse.add(
        AttemptTracePoint(
          position: timedMoments[index].realizationPosition,
          value: medianInterval - interval,
        ),
      );
    }
  }

  final notes = List<NoteMomentStatus>.filled(
    measurement.expectedMoments,
    NoteMomentStatus.missing,
  );
  final extraNotePositions = <double>[];
  var extraNotes = 0;
  final operations = measurement.alignment.operations;
  for (final (index, operation) in operations.indexed) {
    final inserted = operation.noteEdits.whereType<Insertion>().length;
    extraNotes += inserted;
    final insertionPosition = switch (operation) {
      MomentCorrespondence(:final realizationPosition) =>
        realizationPosition.toDouble(),
      MomentInsertion() => _insertionPosition(operations, index),
      MomentDeletion() => null,
    };
    if (insertionPosition != null) {
      extraNotePositions.addAll(List.filled(inserted, insertionPosition));
    }
    switch (operation) {
      case MomentCorrespondence(:final realizationPosition, :final noteEdits):
        notes[realizationPosition] = noteEdits.every((edit) => edit is Match)
            ? NoteMomentStatus.matched
            : NoteMomentStatus.departed;
      case MomentDeletion():
      case MomentInsertion():
        break;
    }
  }

  FlowGap? flowGap;
  final gapPosition = measurement.longestGapBeforePosition;
  if (gapPosition != null && reading.outcome.continuity < 1) {
    for (var index = 1; index < timedMoments.length; index++) {
      if (timedMoments[index].realizationPosition == gapPosition) {
        flowGap = FlowGap(
          beforePosition: gapPosition,
          durationMs:
              timedMoments[index].onsetMs - timedMoments[index - 1].onsetMs,
        );
        break;
      }
    }
  }

  return AttemptDetailTrace(
    momentCount: measurement.expectedMoments,
    pulse: pulse,
    coordination: [
      for (final operation in correspondences)
        if (operation.handAsynchronyMs case final asynchrony?)
          AttemptTracePoint(
            position: operation.realizationPosition,
            value: -asynchrony.toDouble(),
          ),
    ],
    notes: notes,
    extraNotePositions: extraNotePositions,
    extraNotes: extraNotes,
    flowGap: flowGap,
  );
}

double _insertionPosition(List<MomentOperation> operations, int index) {
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
  if (before == null) return (after ?? 0).toDouble();
  if (after == null) return before.toDouble();
  return (before + after) / 2;
}
