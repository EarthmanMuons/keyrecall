import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_measurement/keyrecall_measurement.dart';
import 'package:meta/meta.dart';

/// Version of the coordination log's wire format.
///
/// Its own version, independent of the attempt journal, because this is
/// instrumentation rather than history: it may change shape while the question
/// it answers is open, and nothing replays it.
const int coordinationLogSchemaVersion = 1;

/// What one two-hand attempt observed about how far apart the hands arrived.
///
/// A diagnostic record and not evidence. Nothing replays it, no learner state
/// is computed from it, a failed write must not fail the attempt it came from,
/// and erasing a profile takes it along.
///
/// It exists because the attempt record keeps coordination as one score
/// blended from a median and a tail, which cannot be read back as the
/// milliseconds it came from. Whether the synchronized bound is the right
/// bound for learner-facing feedback is a question about that distribution, so
/// the whole series survives the attempt rather than a summary of it: which
/// hand led, whether the spread grew on the way down, and whether it differs
/// by tempo or family are all questions a median cannot answer.
///
/// The policy bound and the fault travel with the moments so a later reading
/// can say what the learner was actually told, under the numbers that were in
/// force when they were told it.
@immutable
class CoordinationSample {
  final String profileId;
  final String attemptId;

  /// When the attempt this came from was observed, in UTC.
  final DateTime observedAt;

  final String materialId;
  final String familyId;

  /// How the exercise was realized.
  final String hands;
  final String handMotion;
  final String direction;
  final int octaves;

  /// The tempo the exercise asked for.
  final double tempoBpm;

  /// Achieved tempo as a fraction of the requested tempo.
  final double achievedTempoRatio;

  /// How independent the guidance rung was.
  final int guidanceIndependence;

  /// The score the policy read off this series.
  final double coordinationScore;

  /// The bound that was in force when this was recorded, in milliseconds.
  final double synchronizedAsynchronyMs;

  /// Whether the learner was told the hands came apart.
  final bool reportedAsFault;

  /// Every moment both hands were measurable at, as right minus left.
  ///
  /// Signed, and per moment, so which hand led and where the spread sat in the
  /// traversal remain answerable.
  final List<HandAsynchrony> moments;

  CoordinationSample({
    required this.profileId,
    required this.attemptId,
    required DateTime observedAt,
    required this.materialId,
    required this.familyId,
    required this.hands,
    required this.handMotion,
    required this.direction,
    required this.octaves,
    required this.tempoBpm,
    required this.achievedTempoRatio,
    required this.guidanceIndependence,
    required this.coordinationScore,
    required this.synchronizedAsynchronyMs,
    required this.reportedAsFault,
    required Iterable<HandAsynchrony> moments,
  }) : observedAt = observedAt.toUtc(),
       moments = List.unmodifiable(moments);

  /// How far apart the hands usually were, in milliseconds.
  double get medianAbsoluteMs =>
      _median([for (final moment in moments) moment.asynchronyMs.abs()]);

  /// How far apart they got, as the ninetieth percentile by nearest rank.
  double get p90AbsoluteMs =>
      _nearestRank([for (final moment in moments) moment.asynchronyMs.abs()]);

  /// How many moments sat outside the bound that was in force.
  int get looseMoments => [
    for (final moment in moments)
      if (moment.asynchronyMs.abs() > synchronizedAsynchronyMs) moment,
  ].length;

  Map<String, Object?> toJson() => {
    'schema_version': coordinationLogSchemaVersion,
    'profile_id': profileId,
    'attempt_id': attemptId,
    'observed_at': encodeTime(observedAt),
    'material_id': materialId,
    'family_id': familyId,
    'hands': hands,
    'hand_motion': handMotion,
    'direction': direction,
    'octaves': octaves,
    'tempo_bpm': tempoBpm,
    'achieved_tempo_ratio': achievedTempoRatio,
    'guidance_independence': guidanceIndependence,
    'coordination_score': coordinationScore,
    'synchronized_asynchrony_ms': synchronizedAsynchronyMs,
    'reported_as_fault': reportedAsFault,
    'moments': [
      for (final moment in moments)
        {'position': moment.position, 'asynchrony_ms': moment.asynchronyMs},
    ],
  };

  /// Reads a sample back.
  ///
  /// A version this build does not know is refused rather than guessed at, the
  /// same as anywhere else, but refusing costs a diagnostic line rather than a
  /// history: the caller is free to drop the log and keep practicing.
  factory CoordinationSample.fromJson(Map<String, Object?> json) {
    final version = requireInt(json, 'schema_version');
    if (version != coordinationLogSchemaVersion) {
      throw JournalFormatException(
        'coordination log schema version $version is not readable by this '
        'build, which writes version $coordinationLogSchemaVersion',
      );
    }
    final moments = json['moments'];
    if (moments is! List) {
      throw const JournalFormatException(
        'a coordination sample must hold its moments',
      );
    }
    return CoordinationSample(
      profileId: requireString(json, 'profile_id', location: 'coordination'),
      attemptId: requireString(json, 'attempt_id', location: 'coordination'),
      observedAt: requireTime(json, 'observed_at', location: 'coordination'),
      materialId: requireString(json, 'material_id', location: 'coordination'),
      familyId: requireString(json, 'family_id', location: 'coordination'),
      hands: requireString(json, 'hands', location: 'coordination'),
      handMotion: requireString(json, 'hand_motion', location: 'coordination'),
      direction: requireString(json, 'direction', location: 'coordination'),
      octaves: requireInt(json, 'octaves'),
      tempoBpm: requireDouble(json, 'tempo_bpm'),
      achievedTempoRatio: requireDouble(json, 'achieved_tempo_ratio'),
      guidanceIndependence: requireInt(json, 'guidance_independence'),
      coordinationScore: requireDouble(json, 'coordination_score'),
      synchronizedAsynchronyMs: requireDouble(
        json,
        'synchronized_asynchrony_ms',
      ),
      reportedAsFault: json['reported_as_fault'] == true,
      moments: [
        for (final moment in moments)
          _momentFrom(asMap(moment, 'moment', location: 'coordination')),
      ],
    );
  }
}

HandAsynchrony _momentFrom(Map<String, Object?> json) => (
  position: requireInt(json, 'position'),
  asynchronyMs: requireInt(json, 'asynchrony_ms'),
);

double _median(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle].toDouble()
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

double _nearestRank(List<int> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final rank = (0.9 * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1].toDouble();
}
