import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'attempt_trace.dart';

/// Schema tag for [discreteTraceDigest].
///
/// Hashed as the first line, so the digest is a statement about a named record
/// shape rather than about whatever the simulation happens to record. Bump it
/// deliberately when [discreteDigestFields] changes, and update
/// `tool/reference_digest.py` in the same step.
const String discreteDigestSchema = 'reference-digest-v1';

/// Schema tag for [fullTraceDigest]. See [discreteDigestSchema].
const String fullDigestSchema = 'full-trace-digest-v1';

/// Exactly what [discreteTraceDigest] hashes, in order.
///
/// Deliberately narrow, and deliberately declared rather than derived: adding
/// a diagnostic field to `AttemptTrace` must not silently look like a
/// behavioral change six months from now. A test holds the builder to this
/// list.
const List<String> discreteDigestFields = [
  'attempt_index',
  'material_id',
  'hands',
  'octaves',
  'direction',
  'tempo_bpm',
  'guidance_independence',
  'opportunities',
  'started',
  'completed',
  'retrieval',
];

/// The categorical decisions and outcomes of one run, hashed.
///
/// Every field is a choice or a branch: which exercise was presented, how it
/// was to be played, how much support it offered, and what categorically
/// happened. No floating-point value appears, deliberately. Those are the
/// quantities two implementations can legitimately disagree about in the last
/// few digits, and rounding them to force hash equality would make the check
/// less principled than the tolerance comparison it sits beside.
///
/// Exact across implementations, so it answers one question precisely: did the
/// two runs make the same decisions and sample the same categorical outcomes?
/// A mismatch means the trajectories diverged, not that arithmetic drifted.
///
/// The reference implementation hashes the same schema; see
/// `tool/reference_digest.py`.
String discreteTraceDigest(Iterable<AttemptTrace> traces) => _digest(
  discreteDigestSchema,
  traces.map((trace) => _encodeRecord(_discreteFields(trace))),
);

/// A full-precision digest of everything one run computed.
///
/// Covers the state each decision was made from, all four predicted channels,
/// the observed outcome, every evidence weight, the memory attribution, and
/// the state that resulted. Any change to a prediction, a random draw, a
/// transition, or an intermediate state changes it.
///
/// A regression sentinel for this implementation rather than a cross-language
/// check: it hashes doubles at full precision, so it is exact by construction
/// here and would be fragile anywhere else. When it changes, the diagnosable
/// failures are the pinned reference scalars and the tolerance comparison,
/// which say what changed rather than only that something did.
///
/// The field set is fixed below rather than serialized from a trace object, so
/// it stays sensitive to model state and insensitive to trace metadata. Every
/// collection it walks is ordered explicitly, never by map iteration.
String fullTraceDigest(
  Iterable<AttemptTrace> traces, {
  required DateTime epoch,
}) => _digest(
  fullDigestSchema,
  traces.map((trace) => _encodeRecord(_fullFields(trace, epoch))),
);

String _digest(String schema, Iterable<String> records) =>
    sha256.convert(utf8.encode([schema, ...records].join('\n'))).toString();

/// Joins one record's already-encoded fields.
///
/// Records are flat: no field contains the separator, so two different records
/// can never encode to the same line.
String _encodeRecord(List<String> fields) => fields.join('|');

/// Encodings, spelled out rather than left to `toString`, since the Python
/// producer has to reproduce them exactly.
String _encodeBool(bool value) => value ? 'true' : 'false';

String _encodeInt(int value) => value.toString();

String _encodeOptional(String? value) => value ?? 'null';

/// A double drawn from a discrete set, so both implementations agree without
/// rounding: integral values print as integers, anything else as its shortest
/// exact form.
String _encodeDiscreteNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// A double at full precision.
///
/// `toString` on a Dart double is the shortest string that round-trips, which
/// is specified behavior and therefore stable. Only the full digest uses this;
/// the discrete digest hashes no doubles at all.
String _encodeNumber(double value) => value.toString();

List<String> _discreteFields(AttemptTrace trace) {
  final exercise = trace.exercise;
  final conditions = exercise.conditions;
  final opportunities =
      exercise.opportunities.map((opportunity) => opportunity.id).toList()
        ..sort();

  return [
    _encodeInt(trace.attemptIndex),
    exercise.material.materialId,
    conditions.hands.id,
    _encodeInt(conditions.octaves),
    conditions.direction.id,
    _encodeDiscreteNumber(conditions.tempoBpm),
    _encodeInt(exercise.guidance.independence),
    opportunities.join(','),
    _encodeBool(trace.outcome.started),
    _encodeBool(trace.outcome.completed),
    _encodeOptional(
      trace.outcome.retrieval.jsonValue == null
          ? null
          : _encodeBool(trace.outcome.retrieval.jsonValue!),
    ),
  ];
}

List<String> _fullFields(AttemptTrace trace, DateTime epoch) => [
  ..._discreteFields(trace),
  _encodeNumber(epoch.daysUntil(trace.at)),
  trace.profile.id,
  _encodeNumber(trace.prediction.independentRetrievalP),
  _encodeNumber(trace.prediction.materialAvailableP),
  _encodeNumber(trace.prediction.executionP),
  _encodeNumber(trace.prediction.topologyP),
  _encodeNumber(trace.outcome.materialRetrieval),
  _encodeNumber(trace.outcome.pitchIntegrity),
  _encodeNumber(trace.outcome.continuity),
  _encodeNumber(trace.outcome.temporalStability),
  _encodeNumber(trace.outcome.achievedTempoRatio),
  _encodeNumber(trace.outcome.topologyAccuracy),
  for (final competency in Competency.values)
    _encodeNumber(trace.weights[competency]),
  _encodeNumber(trace.weights.materialExecution),
  _encodeNumber(trace.weights.materialMemory),
  _encodeNumber(trace.memoryUpdate.consolidationDeltaFromRetrievalInference),
  _encodeNumber(trace.memoryUpdate.consolidationDeltaFromCausalFormation),
  ..._stateFields(trace.stateBefore, epoch),
  ..._stateFields(trace.stateAfter, epoch),
];

List<String> _stateFields(LearnerState state, DateTime epoch) {
  String? days(DateTime? at) =>
      at == null ? null : _encodeNumber(epoch.daysUntil(at));

  // Sorted explicitly: a digest that depended on map iteration order would
  // drift for reasons that have nothing to do with behavior.
  final materialIds = state.materialMemory.keys.toList()..sort();
  final contexts = state.materialExecution.keys.toList()
    ..sort((a, b) {
      final byMaterial = a.$1.compareTo(b.$1);
      return byMaterial != 0 ? byMaterial : a.$2.index.compareTo(b.$2.index);
    });

  return [
    for (final competency in Competency.values) ...[
      _encodeNumber(state.competency(competency).mean),
      _encodeNumber(state.competency(competency).variance),
    ],
    for (final materialId in materialIds) ...[
      materialId,
      _encodeNumber(state.materialMemory[materialId]!.logCurrentHalfLife),
      _encodeNumber(
        state.materialMemory[materialId]!.currentHalfLifeUncertainty,
      ),
      _encodeNumber(state.materialMemory[materialId]!.logConsolidatedHalfLife),
      _encodeNumber(
        state.materialMemory[materialId]!.consolidatedLogHalfLifeVariance,
      ),
      _encodeNumber(state.materialMemory[materialId]!.logitColdStart),
      _encodeNumber(state.materialMemory[materialId]!.coldStartUncertainty),
      _encodeOptional(days(state.materialMemory[materialId]!.memoryAnchorAt)),
      _encodeOptional(
        days(state.materialMemory[materialId]!.factualLastRetrievalAt),
      ),
      _encodeOptional(
        days(state.materialMemory[materialId]!.lastRetrievalAttemptAt),
      ),
    ],
    for (final context in contexts) ...[
      '${context.$1}/${context.$2.id}',
      _encodeNumber(state.materialExecution[context]!.residualMean),
      _encodeNumber(state.materialExecution[context]!.residualVariance),
    ],
  ];
}
