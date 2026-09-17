import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

import 'support/fixtures.dart';

final _material = fixtureMaterials.first;
final _other = fixtureMaterials[1];

/// 2026-01-05 is a Monday.
final _monday = CalendarDay(2026, 1, 5);

void main() {
  group('calendar weeks', () {
    test('a week starts on its Monday', () {
      expect(CalendarDay(2026, 9, 17).weekStart, CalendarDay(2026, 9, 14));
      expect(CalendarDay(2026, 9, 14).weekStart, CalendarDay(2026, 9, 14));
      expect(CalendarDay(2026, 1, 3).weekStart, CalendarDay(2025, 12, 29));
    });
  });

  group('best demonstrations', () {
    test('a later weaker day neither lowers the level nor its date', () {
      final days = _days([
        (day: 0, record: _attempt(guidance: GuidanceContext.unguided)),
        (
          day: 1,
          record: _attempt(guidance: GuidanceContext.notesPreviewedOnly),
        ),
        (
          day: 2,
          record: _attempt(
            guidance: GuidanceContext.unguided,
            retrieval: FactualRetrieval.failed,
          ),
        ),
      ]);

      final best = bestDemonstrations(days)[_material.materialId]!;
      expect(best.level, DemonstrationLevel.fromMemory);
      expect(best.lastAt, days.first.demonstrations.values.single.lastAt);
    });

    test('never weaken over any prefix of a practiced history', () async {
      final store = InMemoryPracticeStore();
      final session = await openSession(store);
      await practise(session, attempts: 16);
      final failing = await openSession(
        store,
        sessionId: 'session-2',
        ids: countingIds('second'),
      );
      await practise(failing, attempts: 8, startDay: 10, succeed: false);
      final days = FluencyHistory.rebuild(
        await store.loadJournal(alice.id),
        partition: DayPartition.utc,
      ).days;

      var previous = <String, Demonstration>{};
      for (var count = 1; count <= days.length; count++) {
        final current = bestDemonstrations(days.take(count));
        for (final MapEntry(:key, :value) in previous.entries) {
          expect(
            current[key]!.level.index,
            greaterThanOrEqualTo(value.level.index),
          );
          expect(current[key]!.lastAt.isBefore(value.lastAt), isFalse);
        }
        previous = current;
      }
      expect(previous, isNotEmpty);
    });
  });

  group('tempo qualification', () {
    test('counts what was played, capped at what was asked for', () {
      const qualification = TempoQualification.v1;

      expect(qualification.tempoOf(_observation(tempo: 100, ratio: 0.8)), 80);
      expect(qualification.tempoOf(_observation(tempo: 100, ratio: 1.3)), 100);
    });

    test('an observation below the motor bar demonstrates nothing', () {
      final days = _days([(day: 0, record: _attempt(quality: 0.4))]);

      expect(days.single.tempos, hasLength(1));
      expect(demonstratedTempos(days), isEmpty);
    });

    test('demonstrated tempos keep guidance rungs apart', () {
      final days = _days([
        (
          day: 0,
          record: _attempt(
            guidance: GuidanceContext.continuouslyCued,
            tempoBpm: 120,
          ),
        ),
        (day: 0, record: _attempt(tempoBpm: 80)),
      ]);

      final tempos = demonstratedTempos(days);
      expect(tempos.values.toSet(), {120, 80});
      expect(
        {for (final context in tempos.keys) context.guidanceIndependence},
        {0, 2},
      );
    });
  });

  group('weekly tempo', () {
    test('is the median of the week, not of its days', () {
      final days = _days([
        for (var i = 0; i < 3; i++) (day: 0, record: _attempt(tempoBpm: 60)),
        (day: 1, record: _attempt(tempoBpm: 100)),
      ]);

      final week = weeklyTempos(
        days,
        hands: HandConfiguration.right,
        policy: const SingleRung(2),
      ).single;
      expect(week.medianTempoBpm, 60);
      expect(week.observations, 4);
    });

    test('keeps a week without practice as a gap', () {
      final days = _days([
        (day: 0, record: _attempt()),
        (day: 14, record: _attempt()),
      ]);

      final series = weeklyTempos(
        days,
        hands: HandConfiguration.right,
        policy: const SingleRung(2),
      );
      expect(
        [for (final week in series) week.week],
        [_monday, _monday.plusDays(7), _monday.plusDays(14)],
      );
      expect(series[1].medianTempoBpm, isNull);
      expect(series[1].observations, 0);
    });

    test('reads only the hands, span, and parallel motion asked for', () {
      final days = _days([
        (day: 0, record: _attempt(hands: HandConfiguration.left)),
        (day: 0, record: _attempt(octaves: 2)),
        (day: 0, record: _attempt(tempoBpm: 72)),
      ]);

      final week = weeklyTempos(
        days,
        hands: HandConfiguration.right,
        policy: const PooledRungs(),
      ).single;
      expect(week.medianTempoBpm, 72);
      expect(week.observations, 1);
    });

    test('the most independent rung with enough evidence is read alone', () {
      final days = _days([
        for (var i = 0; i < 10; i++)
          (
            day: 0,
            record: _attempt(
              guidance: GuidanceContext.continuouslyCued,
              tempoBpm: 100,
            ),
          ),
        (day: 0, record: _attempt(tempoBpm: 60)),
      ]);

      WeeklyTempo read(TempoRungPolicy policy) => weeklyTempos(
        days,
        hands: HandConfiguration.right,
        policy: policy,
      ).single;

      final supported = read(const MostIndependentRung(minimumObservations: 3));
      expect(supported.guidanceIndependence, 0);
      expect(supported.medianTempoBpm, 100);
      expect(supported.observations, 10);

      final lenient = read(const MostIndependentRung(minimumObservations: 1));
      expect(lenient.guidanceIndependence, 2);
      expect(lenient.medianTempoBpm, 60);

      final unguided = read(const SingleRung(2));
      expect(unguided.observations, 1);
    });

    test('a week with no rung meeting the minimum has no value', () {
      final days = _days([(day: 0, record: _attempt())]);

      final week = weeklyTempos(
        days,
        hands: HandConfiguration.right,
        policy: const MostIndependentRung(minimumObservations: 2),
      ).single;
      expect(week.guidanceIndependence, isNull);
      expect(week.medianTempoBpm, isNull);
      expect(week.observations, 0);
    });
  });
}

typedef _Scripted = ({int day, AttemptRecord Function(int sequence) record});

/// The days a history of [attempts] projects to, each on the day it names
/// counted from [_monday].
List<FluencyDay> _days(List<_Scripted> attempts) {
  final dayByInstant = <DateTime, CalendarDay>{};
  final records = [
    for (final (index, attempt) in attempts.indexed) attempt.record(index),
  ];
  for (final (index, record) in records.indexed) {
    dayByInstant[record.identity.occurredAt] = _monday.plusDays(
      attempts[index].day,
    );
  }
  final history = FluencyHistory.empty(
    alice.id,
    partition: DayPartition('SCRIPTED', (at) => dayByInstant[at]!),
  );
  records.forEach(history.apply);
  return history.days;
}

AttemptRecord Function(int sequence) _attempt({
  GuidanceContext guidance = GuidanceContext.unguided,
  FactualRetrieval? retrieval,
  HandConfiguration hands = HandConfiguration.right,
  int octaves = 1,
  double tempoBpm = 80,
  double quality = 0.9,
}) =>
    (sequence) => recordOf(
      Exercise.linear(
        material: _material,
        hands: hands,
        octaves: octaves,
        tempoBpm: tempoBpm,
        guidance: guidance,
      ),
      sequence: sequence,
      outcome: Outcome(
        started: true,
        retrieval:
            retrieval ??
            (guidance.isRetrievalObserved
                ? FactualRetrieval.succeeded
                : FactualRetrieval.notTested),
        completed: true,
        materialRetrieval: quality,
        pitchIntegrity: quality,
        continuity: quality,
        temporalStability: quality,
        achievedTempoRatio: 1,
        topologyAccuracy: quality,
      ),
    );

TempoObservation _observation({required double tempo, required double ratio}) =>
    TempoObservation(
      materialId: _other.materialId,
      hands: HandConfiguration.right,
      handMotion: HandMotion.parallel,
      octaves: 1,
      guidanceIndependence: 2,
      requestedTempoBpm: tempo,
      tempoRatio: ratio,
      motorScore: 0.9,
      occurredAt: DateTime.utc(2026),
    );
