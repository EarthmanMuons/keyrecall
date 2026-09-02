import 'package:flutter/foundation.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';

/// The learner-facing measurements from one performance.
@immutable
class AttemptSummary {
  final double notes;
  final double flow;
  final double pulse;
  final double? coordination;
  final double achievedTempoBpm;
  final double targetTempoBpm;

  const AttemptSummary({
    required this.notes,
    required this.flow,
    required this.pulse,
    required this.achievedTempoBpm,
    required this.targetTempoBpm,
    this.coordination,
  });
}

AttemptSummary? summarizeAttempt(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) when outcome.started => AttemptSummary(
        notes: outcome.pitchIntegrity,
        flow: outcome.continuity,
        pulse: outcome.temporalStability,
        coordination: outcome.coordination,
        achievedTempoBpm:
            record.exercise.conditions.tempoBpm * outcome.achievedTempoRatio,
        targetTempoBpm: record.exercise.conditions.tempoBpm,
      ),
      _ => null,
    };

/// A longitudinal fact established by the current attempt.
@immutable
class ProgressEvent {
  final ProgressEventKind type;

  const ProgressEvent(this.type);
}

List<ProgressEvent> progressEventsFor(
  AttemptRecord current, {
  required Iterable<AttemptRecord> history,
}) {
  final outcome = switch (current.closure.measurement) {
    Measured(:final outcome) => outcome,
    MeasurementUnavailable() => null,
  };
  if (outcome == null || !outcome.started || !outcome.completed) {
    return const [];
  }

  final earlier = history.where(
    (record) =>
        record.identity.attemptId != current.identity.attemptId &&
        record.journalSequence < current.journalSequence &&
        record.exercise.hasSameRealizationAs(current.exercise),
  );

  final events = <ProgressEvent>[];
  if (_isClean(outcome) && !earlier.any(_recordIsClean)) {
    events.add(const ProgressEvent(ProgressEventKind.firstCleanCompletion));
  }

  final comparable = [...earlier, current]
    ..sort((a, b) => a.journalSequence.compareTo(b.journalSequence));
  if (comparable.length >= 3 &&
      comparable.skip(comparable.length - 3).every(_recordIsClean) &&
      (comparable.length == 3 ||
          !_recordIsClean(comparable[comparable.length - 4]))) {
    events.add(const ProgressEvent(ProgressEventKind.repeatedReliability));
  }

  if (_recordWasCompletedIndependently(current) &&
      !earlier.any(_recordWasCompletedIndependently)) {
    events.add(
      const ProgressEvent(ProgressEventKind.firstIndependentCompletion),
    );
  }

  return List.unmodifiable(events);
}

String? progressStatementFor(
  AttemptRecord current,
  List<ProgressEvent> events,
) {
  if (events.isEmpty) return null;
  final kinds = events.map((event) => event.type).toSet();
  final firstClean = kinds.contains(ProgressEventKind.firstCleanCompletion);
  final firstIndependent = kinds.contains(
    ProgressEventKind.firstIndependentCompletion,
  );
  if (firstClean && firstIndependent) {
    return 'First clean ${_handsPhrase(current)} pass from memory at '
        '${_achievedTempo(current)} BPM.';
  }
  if (kinds.contains(ProgressEventKind.repeatedReliability) &&
      firstIndependent) {
    return 'First time through from memory, and clean on your last three '
        'attempts here.';
  }
  return switch (events.single.type) {
    ProgressEventKind.firstCleanCompletion =>
      'First clean ${_handsPhrase(current)} pass at '
          '${_achievedTempo(current)} BPM.',
    ProgressEventKind.firstIndependentCompletion =>
      'First time through from memory at ${_achievedTempo(current)} BPM.',
    ProgressEventKind.repeatedReliability =>
      'Clean on your last three attempts here.',
  };
}

bool _recordIsClean(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) => outcome.completed && _isClean(outcome),
      MeasurementUnavailable() => false,
    };

bool _recordWasCompletedIndependently(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) =>
        record.exercise.guidance == GuidanceContext.unguided &&
            outcome.completed &&
            outcome.retrieval == FactualRetrieval.succeeded,
      MeasurementUnavailable() => false,
    };

bool _isClean(Outcome outcome) =>
    outcome.pitchIntegrity == 1 &&
    outcome.continuity == 1 &&
    outcome.temporalStability == 1 &&
    (outcome.coordination ?? 1) == 1;

String _handsPhrase(AttemptRecord record) =>
    switch (record.exercise.conditions.hands) {
      HandConfiguration.right => 'right-hand',
      HandConfiguration.left => 'left-hand',
      HandConfiguration.together => 'hands-together',
    };

String _achievedTempo(AttemptRecord record) {
  final outcome = (record.closure.measurement as Measured).outcome;
  return _formatTempo(
    record.exercise.conditions.tempoBpm * outcome.achievedTempoRatio,
  );
}

String _formatTempo(double bpm) => bpm.round().toString();
