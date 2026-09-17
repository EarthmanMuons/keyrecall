import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

final _material = fixtureMaterials.first;

final _utcDay = DayPartition.utc;

final _oneDay = DayPartition('ONE_DAY', (_) => CalendarDay(2026, 1, 1));

void main() {
  group('projection contract', () {
    test('rebuilding equals applying the same records one at a time', () async {
      final journal = await _practisedJournal();
      final incremental = FluencyHistory.empty(alice.id, partition: _utcDay);
      for (final record in journal.records) {
        incremental.apply(record);
      }

      expect(journal.length, greaterThan(20));
      expect(incremental, FluencyHistory.rebuild(journal, partition: _utcDay));
      expect(incremental.days.length, greaterThan(1));
      expect({
        for (final day in incremental.days)
          for (final demonstration in day.demonstrations.values)
            demonstration.level,
      }, DemonstrationLevel.values.toSet());
      expect(incremental.days.expand((day) => day.tempos), isNotEmpty);
    });

    test(
      'a history read back mid-journal continues to the rebuilt one',
      () async {
        final journal = await _practisedJournal();
        final rebuilt = FluencyHistory.rebuild(journal, partition: _utcDay);

        for (var split = 0; split <= journal.length; split++) {
          final prefix = FluencyHistory.empty(alice.id, partition: _utcDay);
          journal.records.take(split).forEach(prefix.apply);
          final restored = FluencyHistory.fromJson(
            _roundTrip(prefix.toJson()),
            partition: _utcDay,
          );
          journal.records.skip(split).forEach(restored.apply);

          expect(restored, rebuilt, reason: 'restored after $split records');
        }
      },
    );

    test('a later record never rewrites an earlier observation', () async {
      final journal = await _practisedJournal();
      final history = FluencyHistory.empty(alice.id, partition: _utcDay);

      for (final record in journal.records) {
        final before = history.days;
        history.apply(record);
        final after = history.days;

        final settled = after.last.day == before.lastOrNull?.day
            ? before.length - 1
            : before.length;
        expect(after.take(settled), before.take(settled));
        if (settled < before.length) {
          _expectExtends(after.last, before.last);
        }
      }
    });

    test('projecting a journal leaves the journal untouched', () async {
      final journal = await _practisedJournal();
      final before = [for (final record in journal.records) record.toJson()];

      FluencyHistory.rebuild(journal, partition: _utcDay);

      expect([for (final record in journal.records) record.toJson()], before);
    });
  });

  group('demonstrations', () {
    test('a retrieval success is filed at the rung it succeeded under', () {
      expect(
        _level(guidance: GuidanceContext.unguided),
        DemonstrationLevel.fromMemory,
      );
      expect(
        _level(guidance: GuidanceContext.notesPreviewedOnly),
        DemonstrationLevel.notesPreviewed,
      );
    });

    test('a cued attempt demonstrates only when it was played through', () {
      expect(
        _level(guidance: GuidanceContext.continuouslyCued),
        DemonstrationLevel.cued,
      );
      expect(
        _level(guidance: GuidanceContext.continuouslyCued, completed: false),
        isNull,
      );
    });

    test('an untested retrieval is not cued unless cues were showing', () {
      expect(
        _level(
          guidance: GuidanceContext.notesPreviewedOnly,
          retrieval: FactualRetrieval.notTested,
        ),
        isNull,
      );
    });

    test('a failed retrieval demonstrates nothing, even when completed', () {
      expect(
        _level(
          guidance: GuidanceContext.unguided,
          retrieval: FactualRetrieval.failed,
        ),
        isNull,
      );
    });

    test('a later failure or weaker rung keeps the day\'s best', () {
      final history = FluencyHistory.empty(alice.id, partition: _oneDay)
        ..apply(_record(0, guidance: GuidanceContext.unguided))
        ..apply(
          _record(
            1,
            guidance: GuidanceContext.unguided,
            retrieval: FactualRetrieval.failed,
          ),
        )
        ..apply(_record(2, guidance: GuidanceContext.notesPreviewedOnly));

      final day = history.days.single;
      expect(day.attempts, 3);
      expect(
        day.demonstrations[_material.materialId],
        Demonstration(
          materialId: _material.materialId,
          level: DemonstrationLevel.fromMemory,
          lastAt: _record(0).identity.occurredAt,
        ),
      );
    });

    test('a repeat at the best rung moves its date forward', () {
      final history = FluencyHistory.empty(alice.id, partition: _oneDay)
        ..apply(_record(0))
        ..apply(_record(1));

      expect(
        history.days.single.demonstrations[_material.materialId]!.lastAt,
        _record(1).identity.occurredAt,
      );
    });

    test('an unmeasured attempt counts as practice and nothing else', () {
      final history = FluencyHistory.empty(alice.id, partition: _oneDay)
        ..apply(
          recordOf(
            _exercise(),
            unmeasured: MeasurementUnavailableReason.notAvailable,
          ),
        );

      final day = history.days.single;
      expect(day.attempts, 1);
      expect(day.demonstrations, isEmpty);
      expect(day.tempos, isEmpty);
    });
  });

  group('tempo observations', () {
    test('keep the guidance rung and the pace beside the request', () {
      final record = _record(
        0,
        guidance: GuidanceContext.notesPreviewedOnly,
        hands: HandConfiguration.left,
        tempoBpm: 100,
        tempoRatio: 0.8,
      );

      expect(
        TempoObservation.of(record),
        TempoObservation(
          materialId: _material.materialId,
          hands: HandConfiguration.left,
          handMotion: HandMotion.parallel,
          octaves: 1,
          guidanceIndependence: 1,
          requestedTempoBpm: 100,
          tempoRatio: 0.8,
          motorScore: 0.9,
          occurredAt: record.identity.occurredAt,
        ),
      );
    });

    test('are absent without timing, a pace, or a completed traversal', () {
      expect(TempoObservation.of(_record(0, timed: false)), isNull);
      expect(TempoObservation.of(_record(0, tempoRatio: 0)), isNull);
      expect(TempoObservation.of(_record(0, completed: false)), isNull);
    });

    test('an unmanaged attempt is still observed', () {
      final observation = TempoObservation.of(_record(0, quality: 0.2));

      expect(observation?.motorScore, 0.2);
    });
  });

  group('refusals', () {
    test('a record out of sequence is refused', () {
      final history = FluencyHistory.empty(alice.id, partition: _oneDay);

      expect(() => history.apply(_record(1)), throwsArgumentError);
      history.apply(_record(0));
      expect(() => history.apply(_record(0)), throwsArgumentError);
      expect(history.coveredRecords, 1);
    });

    test('a record from another profile is refused', () {
      final history = FluencyHistory.empty('someone-else', partition: _oneDay);

      expect(() => history.apply(_record(0)), throwsArgumentError);
    });

    test('a record assigned to an earlier day is refused', () {
      var day = 2;
      final history = FluencyHistory.empty(
        alice.id,
        partition: DayPartition('BACKWARD', (_) => CalendarDay(2026, 1, day--)),
      )..apply(_record(0));

      expect(() => history.apply(_record(1)), throwsArgumentError);
      expect(history.coveredRecords, 1);
    });

    test('another schema version is not read', () {
      final json = _history()..['schema_version'] = 2;

      expect(
        () => FluencyHistory.fromJson(json, partition: _oneDay),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a history built under another day partition is not read', () {
      final json = _history(partition: _utcDay);

      expect(
        () => FluencyHistory.fromJson(json, partition: _oneDay),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an attempt total that disagrees with its coverage is not read', () {
      final json = _history()..['covered_records'] = 5;

      expect(
        () => FluencyHistory.fromJson(json, partition: _oneDay),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('days out of order are not read', () {
      final json = _history(partition: _utcDay);
      json['days'] = (json['days']! as List).reversed.toList();

      expect(
        () => FluencyHistory.fromJson(json, partition: _utcDay),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('a material demonstrated twice in one day is not read', () {
      final json = _history();
      final day = (json['days']! as List).single as Map<String, Object?>;
      final demonstrations = day['demonstrations']! as List;
      day['demonstrations'] = [...demonstrations, ...demonstrations];

      expect(
        () => FluencyHistory.fromJson(json, partition: _oneDay),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an impossible calendar date is not read', () {
      final json = _history();
      ((json['days']! as List).single as Map<String, Object?>)['day'] =
          '2026-02-31';

      expect(
        () => FluencyHistory.fromJson(json, partition: _oneDay),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });
}

/// Two sittings on different days, one succeeding and one failing, so the
/// history holds every demonstration level and several days.
Future<AttemptJournal> _practisedJournal() async {
  final store = InMemoryPracticeStore();
  final first = await openSession(store, ids: countingIds('first'));
  await practise(first, attempts: 14);
  final second = await openSession(
    store,
    sessionId: 'session-2',
    ids: countingIds('second'),
  );
  await practise(second, attempts: 10, startDay: 12, succeed: false);
  return store.loadJournal(alice.id);
}

void _expectExtends(FluencyDay after, FluencyDay before) {
  expect(after.attempts, before.attempts + 1);
  expect(after.tempos.take(before.tempos.length), before.tempos);
  for (final MapEntry(:key, :value) in before.demonstrations.entries) {
    expect(
      after.demonstrations[key]!.level.index,
      greaterThanOrEqualTo(value.level.index),
    );
  }
}

Map<String, Object?> _roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

Map<String, Object?> _history({DayPartition? partition}) {
  final history =
      FluencyHistory.empty(alice.id, partition: partition ?? _oneDay)
        ..apply(_record(0))
        ..apply(_record(1, guidance: GuidanceContext.notesPreviewedOnly));
  return _roundTrip(history.toJson());
}

DemonstrationLevel? _level({
  required GuidanceContext guidance,
  FactualRetrieval? retrieval,
  bool completed = true,
}) => DemonstrationLevel.of(
  _record(0, guidance: guidance, retrieval: retrieval, completed: completed),
);

AttemptRecord _record(
  int sequence, {
  GuidanceContext guidance = GuidanceContext.unguided,
  FactualRetrieval? retrieval,
  HandConfiguration hands = HandConfiguration.right,
  double tempoBpm = 80,
  double tempoRatio = 1,
  double quality = 0.9,
  bool completed = true,
  bool timed = true,
}) => recordOf(
  _exercise(guidance: guidance, hands: hands, tempoBpm: tempoBpm),
  sequence: sequence,
  outcome: Outcome(
    started: true,
    retrieval:
        retrieval ??
        (guidance.isRetrievalObserved
            ? FactualRetrieval.succeeded
            : FactualRetrieval.notTested),
    completed: completed,
    materialRetrieval: quality,
    pitchIntegrity: quality,
    continuity: timed ? quality : null,
    temporalStability: timed ? quality : null,
    achievedTempoRatio: tempoRatio,
    topologyAccuracy: quality,
  ),
);

Exercise _exercise({
  GuidanceContext guidance = GuidanceContext.unguided,
  HandConfiguration hands = HandConfiguration.right,
  double tempoBpm = 80,
}) => Exercise.linear(
  material: _material,
  hands: hands,
  tempoBpm: tempoBpm,
  guidance: guidance,
);
