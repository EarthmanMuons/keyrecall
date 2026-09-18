import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:meta/meta.dart';

/// Version of the fluency history wire format.
///
/// A projection is rebuilt rather than upgraded, so exactly one version is
/// readable.
const int fluencyHistorySchemaVersion = 1;

/// A civil calendar date, the unit fluency history groups practice by.
@immutable
class CalendarDay implements Comparable<CalendarDay> {
  final int year;
  final int month;
  final int day;

  /// Throws [ArgumentError] for a date the calendar does not have.
  CalendarDay(this.year, this.month, this.day) {
    final normalized = DateTime.utc(year, month, day);
    if (normalized.year != year ||
        normalized.month != month ||
        normalized.day != day) {
      throw ArgumentError('$year-$month-$day is not a calendar date');
    }
  }

  /// The date [at] falls on in the device's time zone.
  factory CalendarDay.localOf(DateTime at) {
    final local = at.toLocal();
    return CalendarDay(local.year, local.month, local.day);
  }

  /// Reads a `YYYY-MM-DD` date.
  ///
  /// Throws [FormatException] for anything else.
  factory CalendarDay.parse(String text) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (match == null) throw FormatException('not a calendar date', text);
    return CalendarDay(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
    );
  }

  /// The day [days] after this one.
  CalendarDay plusDays(int days) {
    final shifted = DateTime.utc(year, month, day + days);
    return CalendarDay(shifted.year, shifted.month, shifted.day);
  }

  /// The Monday of the week this day falls in.
  CalendarDay get weekStart =>
      plusDays(1 - DateTime.utc(year, month, day).weekday);

  @override
  int compareTo(CalendarDay other) => _ordinal.compareTo(other._ordinal);

  int get _ordinal => year * 10000 + month * 100 + day;

  @override
  bool operator ==(Object other) =>
      other is CalendarDay && other._ordinal == _ordinal;

  @override
  int get hashCode => _ordinal;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

/// How attempts are assigned to days, and a descriptive name for that policy.
///
/// The journal records instants, not the civil day they fell on, so the day is
/// a build parameter. Its [id] is persisted with a projection, so one built
/// under a different policy is rebuilt. Matching names still require checking
/// every covered record's day assignment before reuse.
@immutable
class DayPartition {
  final String id;
  final CalendarDay Function(DateTime at) dayOf;

  const DayPartition(this.id, this.dayOf);

  /// Days as UTC reckons them.
  static final DayPartition utc = DayPartition(
    'UTC',
    (at) => CalendarDay(at.toUtc().year, at.toUtc().month, at.toUtc().day),
  );

  /// Days in the device's time zone.
  ///
  /// The platform does not expose a stable identity for its time zone rules.
  /// Cached day assignments are checked against the journal before reuse.
  factory DayPartition.local() => DayPartition('LOCAL', CalendarDay.localOf);

  @override
  String toString() => 'DayPartition($id)';
}

/// How independently a material was produced.
///
/// Ordered from most support to least, so a later value is a stronger
/// demonstration.
enum DemonstrationLevel {
  /// Completed while continuous cues supplied the material. Retrieval was never
  /// tested.
  cued('CUED'),

  /// Retrieved after the notes were previewed and hidden.
  notesPreviewed('NOTES_PREVIEWED'),

  /// Retrieved without any pitch guidance.
  fromMemory('FROM_MEMORY');

  const DemonstrationLevel(this.id);

  /// Stable identifier used in persisted projections.
  final String id;

  /// The level with the given [id].
  ///
  /// Throws [ArgumentError] when no level matches.
  static DemonstrationLevel fromId(String id) => values.firstWhere(
    (level) => level.id == id,
    orElse: () =>
        throw ArgumentError.value(id, 'id', 'unknown demonstration level'),
  );

  /// What [record] demonstrated, or null when it demonstrated nothing.
  static DemonstrationLevel? of(AttemptRecord record) {
    if (record.closure.measurement case Measured(:final outcome)) {
      return switch (outcome.retrieval) {
        FactualRetrieval.succeeded => switch (record.exercise.guidance) {
          GuidanceContext.unguided => fromMemory,
          GuidanceContext.notesPreviewedOnly => notesPreviewed,
          _ => null,
        },
        FactualRetrieval.notTested
            when outcome.completed &&
                record.exercise.guidance == GuidanceContext.continuouslyCued =>
          cued,
        _ => null,
      };
    }
    return null;
  }
}

/// The strongest demonstration of one material on one day.
@immutable
class Demonstration {
  final String materialId;
  final DemonstrationLevel level;

  /// When [level] was last demonstrated that day, in UTC.
  final DateTime lastAt;

  Demonstration({
    required this.materialId,
    required this.level,
    required DateTime lastAt,
  }) : lastAt = lastAt.toUtc() {
    if (materialId.isEmpty) {
      throw ArgumentError.value(materialId, 'materialId', 'must not be empty');
    }
  }

  /// This demonstration combined with a later one of the same material.
  Demonstration mergedWith(Demonstration later) {
    if (later.level.index > level.index) return later;
    if (later.level.index < level.index) return this;
    return later.lastAt.isBefore(lastAt) ? this : later;
  }

  Map<String, Object?> toJson() => {
    'material_id': materialId,
    'level': level.id,
    'last_at': encodeTime(lastAt),
  };

  factory Demonstration.fromJson(Map<String, Object?> json) => Demonstration(
    materialId: requireString(json, 'material_id'),
    level: DemonstrationLevel.fromId(requireString(json, 'level')),
    lastAt: requireTime(json, 'last_at'),
  );

  @override
  bool operator ==(Object other) =>
      other is Demonstration &&
      other.materialId == materialId &&
      other.level == level &&
      other.lastAt == lastAt;

  @override
  int get hashCode => Object.hash(materialId, level, lastAt);

  @override
  String toString() => 'Demonstration($materialId, ${level.id})';
}

/// One completed attempt that established both a pace and a motor score.
///
/// The raw ingredients rather than a verdict: whether it was managed, and what
/// tempo it counts at, are report policy applied when the series is read.
@immutable
class TempoObservation {
  final String materialId;
  final HandConfiguration hands;
  final HandMotion handMotion;
  final int octaves;

  /// How independent the guidance rung was, from 0 (cued) to 2 (unguided).
  final int guidanceIndependence;

  /// The tempo the exercise asked for.
  final double requestedTempoBpm;

  /// The measured pace as a fraction of [requestedTempoBpm].
  final double tempoRatio;

  final double motorScore;

  /// When the attempt happened, in UTC.
  final DateTime occurredAt;

  /// Throws [ArgumentError] for a value no measured attempt could carry.
  TempoObservation({
    required this.materialId,
    required this.hands,
    required this.handMotion,
    required this.octaves,
    required this.guidanceIndependence,
    required this.requestedTempoBpm,
    required this.tempoRatio,
    required this.motorScore,
    required DateTime occurredAt,
  }) : occurredAt = occurredAt.toUtc() {
    if (materialId.isEmpty) {
      throw ArgumentError.value(materialId, 'materialId', 'must not be empty');
    }
    if (octaves < 1) {
      throw ArgumentError.value(octaves, 'octaves', 'must be positive');
    }
    if (guidanceIndependence < 0 || guidanceIndependence > 2) {
      throw ArgumentError.value(
        guidanceIndependence,
        'guidanceIndependence',
        'must be 0, 1, or 2',
      );
    }
    if (!requestedTempoBpm.isFinite || requestedTempoBpm <= 0) {
      throw ArgumentError.value(
        requestedTempoBpm,
        'requestedTempoBpm',
        'must be finite and positive',
      );
    }
    if (!tempoRatio.isFinite || tempoRatio <= 0) {
      throw ArgumentError.value(
        tempoRatio,
        'tempoRatio',
        'must be finite and positive',
      );
    }
    if (!motorScore.isFinite || motorScore < 0 || motorScore > 1) {
      throw ArgumentError.value(
        motorScore,
        'motorScore',
        'must be in the range 0 to 1',
      );
    }
  }

  /// The pace actually played.
  double get playedTempoBpm => requestedTempoBpm * tempoRatio;

  /// What [record] observed about pace, or null when it established none.
  static TempoObservation? of(AttemptRecord record) {
    if (record.closure.measurement case Measured(:final outcome)) {
      final ratio = outcome.measuredTempoRatio;
      final motorScore = outcome.motorScore;
      if (!outcome.completed || ratio == null || motorScore == null) {
        return null;
      }
      final exercise = record.exercise;
      return TempoObservation(
        materialId: exercise.material.materialId,
        hands: exercise.conditions.hands,
        handMotion: exercise.conditions.handMotion,
        octaves: exercise.conditions.octaves,
        guidanceIndependence: exercise.guidance.independence,
        requestedTempoBpm: exercise.conditions.tempoBpm,
        tempoRatio: ratio,
        motorScore: motorScore,
        occurredAt: record.identity.occurredAt,
      );
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'material_id': materialId,
    'hands': hands.id,
    'hand_motion': handMotion.id,
    'octaves': octaves,
    'guidance_independence': guidanceIndependence,
    'requested_tempo_bpm': requestedTempoBpm,
    'tempo_ratio': tempoRatio,
    'motor_score': motorScore,
    'occurred_at': encodeTime(occurredAt),
  };

  factory TempoObservation.fromJson(Map<String, Object?> json) =>
      TempoObservation(
        materialId: requireString(json, 'material_id'),
        hands: HandConfiguration.fromId(requireString(json, 'hands')),
        handMotion: HandMotion.fromId(requireString(json, 'hand_motion')),
        octaves: requireInt(json, 'octaves'),
        guidanceIndependence: requireInt(json, 'guidance_independence'),
        requestedTempoBpm: requireDouble(json, 'requested_tempo_bpm'),
        tempoRatio: requireDouble(json, 'tempo_ratio'),
        motorScore: requireDouble(json, 'motor_score'),
        occurredAt: requireTime(json, 'occurred_at'),
      );

  @override
  bool operator ==(Object other) =>
      other is TempoObservation &&
      other.materialId == materialId &&
      other.hands == hands &&
      other.handMotion == handMotion &&
      other.octaves == octaves &&
      other.guidanceIndependence == guidanceIndependence &&
      other.requestedTempoBpm == requestedTempoBpm &&
      other.tempoRatio == tempoRatio &&
      other.motorScore == motorScore &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode => Object.hash(
    materialId,
    hands,
    handMotion,
    octaves,
    guidanceIndependence,
    requestedTempoBpm,
    tempoRatio,
    motorScore,
    occurredAt,
  );

  @override
  String toString() =>
      'TempoObservation($materialId/${hands.id}, $requestedTempoBpm bpm '
      'x $tempoRatio)';
}

/// Everything fluency history keeps about one day of practice.
@immutable
class FluencyDay {
  final CalendarDay day;

  /// Committed attempts that day, measured or not.
  final int attempts;

  /// The strongest demonstration of each material, keyed by material id.
  final Map<String, Demonstration> demonstrations;

  /// Every pace observation that day, in journal order.
  final List<TempoObservation> tempos;

  /// Throws [ArgumentError] for a day with no attempts, or with more
  /// observations than attempts could have produced.
  FluencyDay({
    required this.day,
    required this.attempts,
    required Map<String, Demonstration> demonstrations,
    required Iterable<TempoObservation> tempos,
  }) : demonstrations = Map.unmodifiable(demonstrations),
       tempos = List.unmodifiable(tempos) {
    if (attempts < 1) {
      throw ArgumentError.value(attempts, 'attempts', 'must be positive');
    }
    if (this.demonstrations.length > attempts ||
        this.tempos.length > attempts) {
      throw ArgumentError('a day holds more observations than attempts');
    }
    for (final MapEntry(:key, :value) in this.demonstrations.entries) {
      if (key != value.materialId) {
        throw ArgumentError('demonstration $value is filed under $key');
      }
    }
  }

  /// This day with [record] folded in.
  FluencyDay including(AttemptRecord record) {
    final demonstration = _demonstrationOf(record);
    final tempo = TempoObservation.of(record);
    return FluencyDay(
      day: day,
      attempts: attempts + 1,
      demonstrations: demonstration == null
          ? demonstrations
          : {
              ...demonstrations,
              demonstration.materialId:
                  demonstrations[demonstration.materialId]?.mergedWith(
                    demonstration,
                  ) ??
                  demonstration,
            },
      tempos: tempo == null ? tempos : [...tempos, tempo],
    );
  }

  /// A day holding only [record].
  factory FluencyDay.of(CalendarDay day, AttemptRecord record) {
    final demonstration = _demonstrationOf(record);
    final tempo = TempoObservation.of(record);
    return FluencyDay(
      day: day,
      attempts: 1,
      demonstrations: {?demonstration?.materialId: ?demonstration},
      tempos: [?tempo],
    );
  }

  static Demonstration? _demonstrationOf(AttemptRecord record) {
    final level = DemonstrationLevel.of(record);
    if (level == null) return null;
    return Demonstration(
      materialId: record.exercise.material.materialId,
      level: level,
      lastAt: record.identity.occurredAt,
    );
  }

  Map<String, Object?> toJson() => {
    'day': day.toString(),
    'attempts': attempts,
    'demonstrations': [
      for (final id in demonstrations.keys.toList()..sort())
        demonstrations[id]!.toJson(),
    ],
    'tempos': [for (final tempo in tempos) tempo.toJson()],
  };

  factory FluencyDay.fromJson(Map<String, Object?> json) {
    final day = CalendarDay.parse(requireString(json, 'day'));
    return located(
      () {
        final demonstrations = <String, Demonstration>{};
        for (final entry in _list(json, 'demonstrations')) {
          final demonstration = Demonstration.fromJson(
            asMap(entry, 'demonstration'),
          );
          if (demonstrations.containsKey(demonstration.materialId)) {
            throw JournalFormatException(
              '${demonstration.materialId} is demonstrated twice',
            );
          }
          demonstrations[demonstration.materialId] = demonstration;
        }
        return FluencyDay(
          day: day,
          attempts: requireInt(json, 'attempts'),
          demonstrations: demonstrations,
          tempos: [
            for (final entry in _list(json, 'tempos'))
              TempoObservation.fromJson(asMap(entry, 'tempo observation')),
          ],
        );
      },
      'fluency day',
      location: 'day $day',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FluencyDay &&
      other.day == day &&
      other.attempts == attempts &&
      _sameMap(other.demonstrations, demonstrations) &&
      _sameList(other.tempos, tempos);

  @override
  int get hashCode => Object.hash(day, attempts, demonstrations.length);

  @override
  String toString() => 'FluencyDay($day, $attempts attempts)';
}

/// The factual fluency history of one profile, projected from its journal.
///
/// A disposable read model. It holds observations rather than report
/// statistics, so a weekly median or a best-ever level is computed when read
/// and never frozen into storage, and it carries no learner-model
/// interpretation, so a model change never invalidates it. Nothing reads it
/// back into learner state or scheduling, and deleting it loses nothing the
/// journal cannot rebuild.
///
/// Days are assigned by [partition], which is a build parameter rather than a
/// recorded fact: a projection built under one time zone is rebuilt, not
/// reinterpreted, under another.
class FluencyHistory {
  final String profileId;
  final DayPartition partition;

  final List<FluencyDay> _days;
  int _coveredRecords;
  String _coversHistoryHash;

  /// A history covering no attempts.
  FluencyHistory.empty(String profileId, {required this.partition})
    : profileId = requireProfileId(profileId),
      _days = [],
      _coveredRecords = 0,
      _coversHistoryHash = _genesisHash(profileId);

  FluencyHistory._(
    this.profileId,
    this.partition,
    this._days,
    this._coveredRecords,
    this._coversHistoryHash,
  );

  /// The history [journal] projects to.
  factory FluencyHistory.rebuild(
    AttemptJournal journal, {
    required DayPartition partition,
  }) {
    final history = FluencyHistory.empty(
      journal.header.profileId,
      partition: partition,
    );
    journal.records.forEach(history.apply);
    return history;
  }

  /// How many journal records this covers, which is also the sequence the next
  /// applied record must carry.
  int get coveredRecords => _coveredRecords;

  /// Digest of every record this covers, in order.
  ///
  /// A count alone cannot tell a stored projection of this journal from one of
  /// a history an erase replaced with as many attempts.
  String get coversHistoryHash => _coversHistoryHash;

  /// Whether this covers exactly the first [coveredRecords] records of
  /// [journal] under the current day assignments, so the rest can be applied
  /// rather than everything rebuilt.
  bool coversPrefixOf(AttemptJournal journal) {
    if (journal.header.profileId != profileId) return false;
    if (_coveredRecords > journal.length) return false;
    var digest = _genesisHash(profileId);
    var dayIndex = 0;
    var attemptsInDay = 0;
    for (final record in journal.records.take(_coveredRecords)) {
      final day = _days[dayIndex];
      if (partition.dayOf(record.identity.occurredAt) != day.day) return false;
      if (++attemptsInDay == day.attempts) {
        dayIndex++;
        attemptsInDay = 0;
      }
      digest = _chainHash(digest, record);
    }
    return digest == _coversHistoryHash;
  }

  /// Every day with practice, in calendar order.
  List<FluencyDay> get days => List.unmodifiable(_days);

  /// Folds in [record], the next attempt in this profile's journal.
  ///
  /// Throws [ArgumentError] for a record from another profile, one that is not
  /// the next in sequence, or one assigned to a day before the latest held.
  /// Any of those means the projection no longer follows the journal and has
  /// to be rebuilt rather than repaired.
  void apply(AttemptRecord record) {
    if (record.identity.profileId != profileId) {
      throw ArgumentError(
        'attempt ${record.identity.attemptId} belongs to '
        '${record.identity.profileId}, not $profileId',
      );
    }
    if (record.journalSequence != _coveredRecords) {
      throw ArgumentError(
        'attempt ${record.identity.attemptId} has sequence '
        '${record.journalSequence}, expected $_coveredRecords',
      );
    }
    final day = partition.dayOf(record.identity.occurredAt);
    final latest = _days.isEmpty ? null : _days.last;
    if (latest != null && day.compareTo(latest.day) < 0) {
      throw ArgumentError(
        'attempt ${record.identity.attemptId} falls on $day, before '
        '${latest.day}',
      );
    }
    if (latest?.day == day) {
      _days.last = latest!.including(record);
    } else {
      _days.add(FluencyDay.of(day, record));
    }
    _coveredRecords++;
    _coversHistoryHash = _chainHash(_coversHistoryHash, record);
  }

  Map<String, Object?> toJson() => {
    'schema_version': fluencyHistorySchemaVersion,
    'profile_id': profileId,
    'day_partition': partition.id,
    'covered_records': _coveredRecords,
    'covers_history_hash': _coversHistoryHash,
    'days': [for (final day in _days) day.toJson()],
  };

  /// Reads a history back.
  ///
  /// Throws [JournalFormatException] for another schema version, another day
  /// partition, or anything inconsistent, including days out of order or an
  /// attempt total that disagrees with the records it claims to cover. The caller rebuilds from
  /// the journal rather than trusting a partial reading.
  factory FluencyHistory.fromJson(
    Map<String, Object?> json, {
    required DayPartition partition,
  }) => located(
    () => FluencyHistory._fromJson(json, partition),
    'fluency history',
  );

  static FluencyHistory _fromJson(
    Map<String, Object?> json,
    DayPartition partition,
  ) {
    final version = requireInt(json, 'schema_version');
    if (version != fluencyHistorySchemaVersion) {
      throw JournalFormatException(
        'fluency history schema version $version is not readable by this '
        'build, which writes version $fluencyHistorySchemaVersion',
      );
    }
    final partitionId = requireString(json, 'day_partition');
    if (partitionId != partition.id) {
      throw JournalFormatException(
        'fluency history was built under day partition $partitionId, not '
        '${partition.id}',
      );
    }
    final covered = requireInt(json, 'covered_records');
    final days = [
      for (final entry in _list(json, 'days'))
        FluencyDay.fromJson(asMap(entry, 'fluency day')),
    ];
    for (var index = 1; index < days.length; index++) {
      if (days[index - 1].day.compareTo(days[index].day) >= 0) {
        throw JournalFormatException(
          'fluency days are out of order at ${days[index].day}',
        );
      }
    }
    final attempts = days.fold(0, (total, day) => total + day.attempts);
    if (attempts != covered) {
      throw JournalFormatException(
        'fluency days hold $attempts attempts but claim to cover $covered',
      );
    }
    return FluencyHistory._(
      requireProfileId(requireString(json, 'profile_id')),
      partition,
      days,
      covered,
      requireString(json, 'covers_history_hash'),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FluencyHistory &&
      other.profileId == profileId &&
      other.partition.id == partition.id &&
      other._coveredRecords == _coveredRecords &&
      other._coversHistoryHash == _coversHistoryHash &&
      _sameList(other._days, _days);

  @override
  int get hashCode => Object.hash(profileId, _coveredRecords, _days.length);

  @override
  String toString() =>
      'FluencyHistory($profileId, $_coveredRecords attempts, '
      '${_days.length} days)';
}

String _genesisHash(String profileId) =>
    contentHash({'fluency_history': profileId});

String _chainHash(String previous, AttemptRecord record) => contentHash({
  'previous': previous,
  'attempt': contentHash(record.toJson()),
});

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List) return value;
  throw JournalFormatException(
    'expected a list at "$key", got ${value.runtimeType}',
  );
}

bool _sameList<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameMap<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length &&
    a.entries.every((entry) => b[entry.key] == entry.value);
