import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:path_provider/path_provider.dart';

import 'practice_providers.dart';

/// One attempt, as a line of the trajectory table.
///
/// Everything needed to read a sequence and say why it went the way it did:
/// what was asked for, whether it was appropriate, and what admitted it. The
/// journal holds all of it already; this only arranges it.
String trajectoryRow(int index, AttemptRecord record) {
  final exercise = record.exercise;
  final conditions = exercise.conditions;
  final decision = record.decision;
  final measurement = record.closure.measurement;

  return [
    index.toString().padLeft(3),
    exercise.material.materialId.padRight(18),
    admissionBandOf(exercise.material).id.padRight(22),
    conditions.hands.id.padRight(8),
    '${conditions.octaves}oct',
    conditions.direction.id.padRight(7),
    '${conditions.tempoBpm.round()}bpm'.padLeft(7),
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
String trajectoryOf(Profile profile, AttemptJournal journal) => [
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
    'span',
    'direction'.padRight(7),
    'tempo'.padLeft(7),
    'rung',
    'tier'.padRight(24),
    'first_eligibility_reason'.padRight(38),
    'admitted_by'.padRight(18),
    'predicted',
    'outcome (played = requested x achieved ratio)',
  ].join(' '),
  for (final (index, record) in journal.records.indexed)
    trajectoryRow(index, record),
].join('\n');

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
    ..writeAsStringSync(trajectoryOf(profile, journal));

  // Beside it rather than in it, and only when a two-hand attempt has been
  // measured: an empty table is a file somebody has to open to learn nothing.
  final samples = await store.loadCoordinationSamples(profile.id);
  if (samples.isNotEmpty) {
    File('${directory.path}/$stamp-${profile.displayName}-coordination.txt')
        .writeAsStringSync(coordinationTableOf(profile, samples));
  }
  return file.path;
}
