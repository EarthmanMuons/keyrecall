import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:path_provider/path_provider.dart';

import 'practice_providers.dart';

/// What the model knew about pace when an attempt was decided.
///
/// The journal records the tempo that was asked for and not the reason it was
/// the tempo asked for, and the difference between those two is most of what a
/// sitting that feels slow is about. Replaying the history exposes the three
/// numbers the request is chosen against:
///
/// ```text
/// frontier   the fastest rung this realization has been asked for and managed
/// paced      the fastest this learner plays it unprompted, whatever was asked
/// together   where hands-together work would enter, from the slower hand
/// ```
///
/// A frontier well under a paced tempo is the shape of a learner who keeps
/// playing faster than the request: pace is earned by being asked, so the
/// frontier only moves when a probe asks.
@immutable
class TempoProvenance {
  final double frontierBpm;
  final double pacedBpm;
  final double handsTogetherEntryBpm;

  const TempoProvenance({
    required this.frontierBpm,
    required this.pacedBpm,
    required this.handsTogetherEntryBpm,
  });

  static const TempoProvenance unknown = TempoProvenance(
    frontierBpm: 0,
    pacedBpm: 0,
    handsTogetherEntryBpm: 0,
  );

  /// What [state] held about [exercise] before it was attempted.
  factory TempoProvenance.of(LearnerState state, Exercise exercise) {
    final conditions = exercise.conditions;
    final record =
        state.materialExecution[(
          exercise.material.materialId,
          conditions.hands,
          conditions.handMotion,
        )];
    return TempoProvenance(
      frontierBpm: record?.demonstratedTempoByOctaves[conditions.octaves] ?? 0,
      pacedBpm: record?.pacedTempoBpm ?? 0,
      handsTogetherEntryBpm: handsTogetherEntryTempo(
        state,
        exercise.material.materialId,
        conditions.octaves,
      ),
    );
  }
}

/// A tempo as the tables write it, or a dash where there is none.
String _bpm(double tempoBpm) => tempoBpm <= 0 ? '-' : '${tempoBpm.round()}bpm';

/// One attempt, as a line of the trajectory table.
///
/// Everything needed to read a sequence and say why it went the way it did:
/// what was asked for, whether it was appropriate, and what admitted it. The
/// journal holds all of it already; this only arranges it, apart from the pace
/// columns, which come from replaying the state each decision was made against.
String trajectoryRow(
  int index,
  AttemptRecord record, {
  TempoProvenance pace = TempoProvenance.unknown,
}) {
  final exercise = record.exercise;
  final conditions = exercise.conditions;
  final decision = record.decision;
  final measurement = record.closure.measurement;

  return [
    index.toString().padLeft(3),
    exercise.material.materialId.padRight(18),
    admissionBandOf(exercise.material).id.padRight(22),
    conditions.hands.id.padRight(8),
    // Motion is what separates two hands moving together from two hands
    // mirroring each other, which is a different exercise and was invisible
    // in this table while every column above it read the same.
    conditions.handMotion.id.padRight(8),
    '${conditions.octaves}oct',
    conditions.direction.id.padRight(7),
    '${conditions.tempoBpm.round()}bpm'.padLeft(7),
    _bpm(pace.frontierBpm).padLeft(7),
    _bpm(pace.pacedBpm).padLeft(7),
    _bpm(pace.handsTogetherEntryBpm).padLeft(7),
    'g=${exercise.guidance.independence}',
    (decision?.eligibilityTier.id ?? 'unscheduled').padRight(24),
    (decision?.eligibilityReason?.id ?? '').padRight(38),
    (decision?.challengeBypass?.id ?? 'in-band').padRight(18),
    'p=${decision?.prediction.overallP.toStringAsFixed(2) ?? '?'}',
    switch (measurement) {
      Measured(:final outcome) =>
        'done=${outcome.completed} pitch='
            '${outcome.pitchIntegrity.toStringAsFixed(2)} '
            'motor=${outcome.motorScore.toStringAsFixed(2)} '
            // What the tempo probe reads and the frontier is attributed at.
            // A ratio far from what somebody believes they played is a
            // question about the transcript rather than about the playing,
            // and it cannot be asked from a table that leaves it out.
            'played=${(conditions.tempoBpm * outcome.achievedTempoRatio).round()}bpm'
            '(x${outcome.achievedTempoRatio.toStringAsFixed(2)})',
      MeasurementUnavailable(:final reason) => 'unmeasured ${reason.id}',
    },
  ].join(' ');
}

/// The whole of a profile's history, as a table.
///
/// The reason column is named for what it is. Eligibility returns on the
/// first rule that refuses, so a two-octave harmonic minor reports the octave
/// span and never reaches the altered-form check: a row says which
/// prerequisite was binding, never that the others passed. That is enough to
/// group stalls, which is what the reasons are coded for, and not enough to
/// conclude anything about the rules it does not name.
String trajectoryOf(
  Profile profile,
  AttemptJournal journal, {
  Map<String, TempoProvenance> pace = const {},
}) => [
  'profile   ${profile.displayName} (${profile.id})',
  'placement ${profile.placement.id}',
  'created   ${profile.createdAt.toIso8601String()}',
  'attempts  ${journal.records.length}',
  '',
  'first_eligibility_reason is the rule that refused first, not the only one',
  '',
  [
    '  #',
    'material'.padRight(18),
    'band'.padRight(22),
    'hands'.padRight(8),
    'motion'.padRight(8),
    'span',
    'direction'.padRight(7),
    'tempo'.padLeft(7),
    'front'.padLeft(7),
    'paced'.padLeft(7),
    'htentry'.padLeft(7),
    'rung',
    'tier'.padRight(24),
    'first_eligibility_reason'.padRight(38),
    'admitted_by'.padRight(18),
    'predicted',
    'outcome (played = requested x achieved ratio)',
  ].join(' '),
  for (final (index, record) in journal.records.indexed)
    trajectoryRow(
      index,
      record,
      pace: pace[record.identity.attemptId] ?? TempoProvenance.unknown,
    ),
].join('\n');

/// What the model knew about pace before each attempt in [journal].
///
/// Replayed rather than recorded. Nothing persists it, and a diagnosis that
/// needs it is rare enough that recomputing beats widening what every attempt
/// carries forever.
Map<String, TempoProvenance> paceProvenanceOf(
  Profile profile,
  AttemptJournal journal, {
  LearnerModel model = const LearnerModel(),
}) {
  final provenance = <String, TempoProvenance>{};
  replayJournal(
    journal,
    model: model,
    initial: model.placementState(profile.placement, at: profile.createdAt),
    options: const ReplayOptions(mode: ReplayMode.counterfactual),
    observe: (record, before) {
      provenance[record.identity.attemptId] = TempoProvenance.of(
        before,
        record.exercise,
      );
    },
  );
  return provenance;
}

/// The bounds each coordination series is replayed against.
///
/// Fixed comparison bounds. Nothing here changes what a learner
/// was told; it says what a different definition of together would have made
/// of the same playing, which is the question a threshold can be argued from.
const List<double> counterfactualBoundsMs = [30, 40, 50, 60];

/// What one series would read at [boundMs]: loose moments, then the score.
String _underBound(CoordinationSample sample, double boundMs) {
  final policy = MeasurementPolicy(synchronizedAsynchronyMs: boundMs);
  final loose = sample.looseMomentsAt(boundMs);
  return '$loose/${sample.moments.length} '
      '${sample.scoreUnder(policy).toStringAsFixed(2)}';
}

/// The coordination log as a table, one line per measured two-hand attempt.
///
/// Instrumentation rather than history, so it is written beside the trajectory
/// rather than into it: what it answers is whether the synchronized bound is
/// the right bound, and that is a question about milliseconds the attempt
/// record does not keep. The per-moment series is on the line, since which
/// hand led and where the spread sat are the parts a median cannot answer.
String coordinationTableOf(
  Profile profile,
  List<CoordinationSample> samples,
) => [
  'profile   ${profile.displayName} (${profile.id})',
  'samples   ${samples.length}',
  '',
  'diagnostic instrumentation, not learner evidence',
  'asynchrony is right minus left, in milliseconds, at each measurable moment',
  'the bound columns are counterfactual: what each series would have read at '
      'that bound, leaving production policy alone',
  '',
  [
    'attempt'.padRight(36),
    'material'.padRight(24),
    'hands'.padRight(8),
    'motion'.padRight(9),
    'span',
    'tempo'.padLeft(7),
    'played'.padLeft(7),
    'rung',
    'median'.padLeft(7),
    'p90'.padLeft(6),
    'bound'.padLeft(6),
    'loose'.padLeft(6),
    'told'.padRight(5),
    for (final bound in counterfactualBoundsMs)
      '@${bound.round()}ms'.padLeft(11),
    'moments',
  ].join(' '),
  for (final sample in samples)
    [
      sample.attemptId.padRight(36),
      sample.materialId.padRight(24),
      sample.hands.padRight(8),
      sample.handMotion.padRight(9),
      '${sample.octaves}oct',
      '${sample.tempoBpm.round()}bpm'.padLeft(7),
      '${(sample.tempoBpm * sample.achievedTempoRatio).round()}bpm'.padLeft(7),
      'g=${sample.guidanceIndependence}',
      '${sample.medianAbsoluteMs.round()}ms'.padLeft(7),
      '${sample.p90AbsoluteMs.round()}ms'.padLeft(6),
      '${sample.synchronizedAsynchronyMs.round()}ms'.padLeft(6),
      '${sample.looseMoments}/${sample.moments.length}'.padLeft(6),
      (sample.reportedAsFault ? 'yes' : 'no').padRight(5),
      for (final bound in counterfactualBoundsMs)
        _underBound(sample, bound).padLeft(11),
      [
        for (final moment in sample.moments)
          '${moment.position}:${moment.asynchronyMs}',
      ].join(','),
    ].join(' '),
].join('\n');

/// Writes the active profile's trajectory where the Files app and Finder can
/// reach it.
///
/// A journal lives in application support and stays there: it is the history,
/// not a document, and nothing routine should be copying it out. Reading a
/// sequence to work out why the scheduler chose what it chose is not routine,
/// and doing it by hand from a device is otherwise impossible.
///
/// The table rather than the journal itself, deliberately. What a diagnosis
/// needs is the decision beside the exercise, which the raw records hold but
/// do not put next to each other.
Future<String> exportTrajectory(WidgetRef ref) async {
  final repository = await ref.read(profileRepositoryProvider.future);
  final store = await ref.read(practiceStoreProvider.future);
  final profile = await repository.selectedOrOldest();
  if (profile == null) throw StateError('no profile to export');

  final journal = await store.loadJournal(
    profile.id,
    createdAt: profile.createdAt,
  );
  final directory = Directory(
    '${(await getApplicationDocumentsDirectory()).path}/trajectories',
  )..createSync(recursive: true);
  final stamp = DateTime.now().toIso8601String().replaceAll(
    RegExp('[:.]'),
    '-',
  );
  final file = File('${directory.path}/$stamp-${profile.displayName}.txt')
    ..writeAsStringSync(
      trajectoryOf(profile, journal, pace: paceProvenanceOf(profile, journal)),
    );

  // Beside it rather than in it, and only when a two-hand attempt has been
  // measured: an empty table is a file somebody has to open to learn nothing.
  final samples = await store.loadCoordinationSamples(profile.id);
  if (samples.isNotEmpty) {
    File('${directory.path}/$stamp-${profile.displayName}-coordination.txt')
        .writeAsStringSync(coordinationTableOf(profile, samples));
  }
  // Machine-readable, beside the readable one rather than instead of it: the
  // calibration harness reads this, a person reads the other, and neither has
  // to be a compromise for the other's sake.
  final sitting = sittingExportOf(profile, journal);
  if (sitting.attempts.isNotEmpty) {
    File('${directory.path}/$stamp-${profile.displayName}-attempts.json')
        .writeAsStringSync(encodeSittingExport(sitting));
  }

  final selections = await store.loadSelectionDiagnostics(profile.id);
  if (selections.isNotEmpty) {
    File('${directory.path}/$stamp-${profile.displayName}-selections.txt')
        .writeAsStringSync(selectionTableOf(profile, journal, selections));
  }
  return file.path;
}

/// The last sitting of [journal], as the facts a fit is entitled to read.
///
/// The exercise as presented and the outcome as measured, both in the
/// journal's own encodings rather than a calibration-specific interpretation
/// of them, plus what was known about the material beforehand.
///
/// Familiarity comes from the immutable history rather than from learner state
/// at export time, which later attempts have moved. A material with an earlier
/// record is [MaterialFamiliarity.familiar]; one without is
/// [MaterialFamiliarity.unknown] rather than unfamiliar, because the journal
/// begins when the profile does and says nothing about a lifetime of playing
/// before that. Nothing here emits [MaterialFamiliarity.unfamiliar]: no part
/// of the app records that a person had never met a scale.
///
/// Attempts that measured nothing are left out. A fit reads what was played,
/// and an attempt with no measurement was not.
SittingExport sittingExportOf(Profile profile, AttemptJournal journal) {
  final records = journal.records;
  final sessionId = records.isEmpty ? '' : records.last.identity.sessionId;
  final seen = <String>{};
  final attempts = <ExportedAttempt>[];

  for (final record in records) {
    final familiar = !seen.add(record.exercise.material.materialId);
    if (record.identity.sessionId != sessionId) continue;
    if (record.closure.measurement case Measured(:final outcome)) {
      attempts.add(
        ExportedAttempt(
          index: attempts.length,
          exercise: record.exercise,
          outcome: outcome,
          familiarity: familiar
              ? MaterialFamiliarity.familiar
              : MaterialFamiliarity.unknown,
        ),
      );
    }
  }

  return SittingExport(
    profileId: profile.id,
    sittingId: sessionId,
    startedAt: attempts.isEmpty
        ? profile.createdAt
        : records
              .firstWhere((record) => record.identity.sessionId == sessionId)
              .identity
              .occurredAt,
    attempts: attempts,
  );
}

/// Recorded competition only; older attempts cannot reconstruct these sets.
String selectionTableOf(
  Profile profile,
  AttemptJournal journal,
  Map<String, String> selections,
) => [
  'profile   ${profile.displayName} (${profile.id})',
  'diagnostic instrumentation, not learner evidence',
  for (final (index, record) in journal.records.indexed) ...[
    '',
    'slot=$index attempt=${record.identity.attemptId}',
    selections[record.identity.attemptId] ??
        'selection diagnostics unavailable (not recorded)',
  ],
].join('\n');
