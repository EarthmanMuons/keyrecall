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
  final String sentence;

  const ProgressEvent(this.type, this.sentence);
}

ProgressEvent? progressEventFor(
  AttemptRecord current, {
  required Iterable<AttemptRecord> history,
}) {
  final outcome = switch (current.closure.measurement) {
    Measured(:final outcome) => outcome,
    MeasurementUnavailable() => null,
  };
  if (outcome == null || !outcome.started || !outcome.completed) return null;

  final earlier = history.where(
    (record) =>
        record.identity.attemptId != current.identity.attemptId &&
        record.journalSequence < current.journalSequence &&
        record.exercise.hasSameRealizationAs(current.exercise),
  );

  if (_isClean(outcome) && !earlier.any(_recordIsClean)) {
    final tempo = _formatTempo(
      current.exercise.conditions.tempoBpm * outcome.achievedTempoRatio,
    );
    final hands = switch (current.exercise.conditions.hands) {
      HandConfiguration.right => 'right-hand',
      HandConfiguration.left => 'left-hand',
      HandConfiguration.together => 'hands-together',
    };
    return ProgressEvent(
      ProgressEventKind.firstCleanCompletion,
      'First clean $hands pass at $tempo BPM.',
    );
  }

  final comparable = [...earlier, current]
    ..sort((a, b) => a.journalSequence.compareTo(b.journalSequence));
  if (comparable.length >= 3 &&
      comparable.skip(comparable.length - 3).every(_recordIsClean) &&
      (comparable.length == 3 ||
          !_recordIsClean(comparable[comparable.length - 4]))) {
    return const ProgressEvent(
      ProgressEventKind.repeatedReliability,
      'Clean on your last three attempts here.',
    );
  }

  if (outcome.retrieval == FactualRetrieval.succeeded &&
      !earlier.any(_recordWasRetrieved)) {
    return ProgressEvent(
      ProgressEventKind.firstIndependentCompletion,
      'First time through from memory at '
      '${_formatTempo(current.exercise.conditions.tempoBpm * outcome.achievedTempoRatio)} BPM.',
    );
  }

  return null;
}

bool _recordIsClean(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) => outcome.completed && _isClean(outcome),
      MeasurementUnavailable() => false,
    };

bool _recordWasRetrieved(AttemptRecord record) =>
    switch (record.closure.measurement) {
      Measured(:final outcome) =>
        outcome.completed && outcome.retrieval == FactualRetrieval.succeeded,
      MeasurementUnavailable() => false,
    };

bool _isClean(Outcome outcome) =>
    outcome.pitchIntegrity == 1 &&
    outcome.continuity == 1 &&
    outcome.temporalStability == 1 &&
    (outcome.coordination ?? 1) == 1;

String _formatTempo(double bpm) => bpm == bpm.roundToDouble()
    ? bpm.round().toString()
    : bpm.toStringAsFixed(1);
