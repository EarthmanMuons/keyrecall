import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/fixtures.dart';

/// A version 1 record: the outcome and its derived evidence sat directly on the
/// record, because the learner ending the attempt and saying what happened was
/// the only way one could be written.
Map<String, Object?> version1(Map<String, Object?> current) {
  final old = version2(current);
  final measurement = measurementJsonOf(old);
  return Map<String, Object?>.of(old)
    ..['schema_version'] = 1
    ..remove('closure')
    ..['outcome'] = measurement['outcome']
    ..['evidence_weights'] = measurement['evidence_weights']
    ..['memory_update'] = measurement['memory_update'];
}

Map<String, Object?> version2(Map<String, Object?> current) {
  final old = version3(current)..['schema_version'] = 2;
  final decision = old['decision'];
  if (decision is! Map<String, Object?>) return old;
  final prediction = decision['prediction'];
  if (prediction is! Map<String, Object?>) return old;
  old['decision'] = Map<String, Object?>.of(decision)
    ..['prediction'] = (Map<String, Object?>.of(prediction)
      ..remove('coordination_p'));
  return old;
}

Map<String, Object?> version3(Map<String, Object?> current) {
  final old = version4(current)..['schema_version'] = 3;
  final exercise = old['exercise'];
  if (exercise is Map<String, Object?>) {
    old['exercise'] = Map<String, Object?>.of(exercise)
      ..remove('opportunity_sites');
  }
  return old;
}

Map<String, Object?> version4(Map<String, Object?> current) =>
    Map<String, Object?>.of(version5(current))
      ..['schema_version'] = 4
      ..remove('presentation');

Map<String, Object?> version5(Map<String, Object?> current) =>
    Map<String, Object?>.of(version6(current))
      ..['schema_version'] = 5
      ..remove('scope')
      ..remove('timing')
      ..remove('input');

/// A version 6 record: every beat a pulse asked for was counted in one total,
/// and no outcome said whether it tested the learner keeping the pulse.
/// A version 7 record: nothing said how many continuing beats were shown.
Map<String, Object?> version7(Map<String, Object?> current) {
  final old = Map<String, Object?>.of(current)..['schema_version'] = 7;
  if (old['presentation'] case final Map<String, Object?> presentation) {
    old['presentation'] = {
      ...presentation,
      'delivery': Map<String, Object?>.of(
        presentation['delivery']! as Map<String, Object?>,
      )..remove('shown_continuing_beats'),
    };
  }
  return old;
}

Map<String, Object?> version6(Map<String, Object?> current) {
  final old = Map<String, Object?>.of(version7(current))
    ..['schema_version'] = 6;
  if (old['presentation'] case final Map<String, Object?> presentation) {
    final delivery = presentation['delivery']! as Map<String, Object?>;
    final tempo = delivery['tempo']! as Map<String, Object?>;
    final countIn = tempo['count_in']! as Map<String, Object?>;
    old['presentation'] = {
      ...presentation,
      'delivery': {
        ...delivery,
        'tempo': {
          'delivery': tempo['delivery'],
          'requested_beats': countIn['requested'],
          'delivered_beats': countIn['delivered'],
          'failure_reason': tempo['failure_reason'],
        },
      },
    };
  }
  final closure = old['closure']! as Map<String, Object?>;
  final measurement = closure['measurement']! as Map<String, Object?>;
  if (measurement['outcome'] case final Map<String, Object?> outcome) {
    old['closure'] = {
      ...closure,
      'measurement': {
        ...measurement,
        'outcome': Map<String, Object?>.of(outcome)
          ..remove('pulse_maintenance_tested'),
      },
    };
  }
  return old;
}

void main() {
  final recorded = recordSession();
  final journal = recorded.journal;

  group('version 1 to current', () {
    test('reads every historical outcome as a learner-stopped measurement', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version1(original.toJson()));

        expect(upgraded.closure.termination, AttemptTermination.learnerStopped);
        expect(measuredOf(upgraded).outcome, measuredOf(original).outcome);
        expect(measuredOf(upgraded).weights, measuredOf(original).weights);
        // Diagnostics have no value equality, so compare what they say.
        expect(
          '${measuredOf(upgraded).memoryUpdate}',
          '${measuredOf(original).memoryUpdate}',
        );
      }
    });

    test('carries every retrieval value through, including untested', () {
      final original = journal.records.first;

      for (final retrieval in FactualRetrieval.values) {
        final json = version1(original.toJson());
        (json['outcome']! as Map<String, Object?>)['retrieval_succeeded'] =
            switch (retrieval) {
              FactualRetrieval.succeeded => true,
              FactualRetrieval.failed => false,
              FactualRetrieval.notTested => null,
            };

        expect(
          measuredOf(AttemptRecord.fromJson(json)).outcome.retrieval,
          retrieval,
          reason:
              'untested serializes as null, which is the value most '
              'likely to be lost in a migration',
        );
      }
    });

    test('does not reinterpret a broken-down outcome as a termination', () {
      // What ReportedResult.brokeDown produced: an attempt that started, did
      // not complete, and failed retrieval. That is a characterization of the
      // performance, and the upgrade must leave it there rather than reading a
      // lifecycle event out of it.
      final brokeDown = outcomeOf(
        started: true,
        completed: false,
        retrieval: FactualRetrieval.failed,
      );
      final record = journal.records.first;
      final json = version1(record.toJson());
      json['outcome'] =
          {
            for (final entry
                in (json['outcome']! as Map<String, Object?>).entries)
              entry.key: entry.value,
          }..addAll({
            'started': brokeDown.started,
            'completed': brokeDown.completed,
            'retrieval_succeeded': false,
          });

      final upgraded = AttemptRecord.fromJson(json);

      expect(upgraded.closure.termination, AttemptTermination.learnerStopped);
      expect(measuredOf(upgraded).outcome, brokeDown);
      expect(measuredOf(upgraded).outcome.completed, isFalse);
    });

    test('an upgraded journal replays to the same learner state', () {
      final upgraded = AttemptJournal(journal.header);
      for (final record in journal.records) {
        upgraded.append(AttemptRecord.fromJson(version1(record.toJson())));
      }

      final before = replayJournal(
        journal,
        model: model,
        initial: recorded.initial.copy(),
      );
      final after = replayJournal(
        upgraded,
        model: model,
        initial: recorded.initial.copy(),
      );

      expect(after.stateHash, before.stateHash);
      expect(after.attemptsApplied, before.attemptsApplied);
      expect(after.divergences, isEmpty);
    });
  });

  group('version 2 to current', () {
    test('preserves the former challenge prediction', () {
      for (final original in journal.records) {
        final decision = original.decision;
        if (decision == null) continue;

        final upgraded = AttemptRecord.fromJson(version2(original.toJson()));

        expect(upgraded.decision!.prediction.coordinationP, 1.0);
        expect(
          upgraded.decision!.prediction.overallP,
          closeTo(
            decision.prediction.materialAvailableP *
                decision.prediction.executionP,
            1e-12,
          ),
        );
      }
    });
  });

  group('version 3 to current', () {
    test('preserves opportunity kinds without inventing event locations', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version3(original.toJson()));

        expect(
          upgraded.exercise.opportunities,
          original.exercise.opportunities,
        );
        expect(upgraded.exercise.opportunitySites, isEmpty);
      }
    });
  });

  group('version 4 to current', () {
    test('leaves the presentation unsaid rather than deriving one', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version4(original.toJson()));

        expect(upgraded.presentation, isNull);
        expect(upgraded.exercise.guidance, original.exercise.guidance);
      }
    });
  });

  group('version 5 to current', () {
    test('leaves the scope unsaid rather than assuming today\'s goal', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version5(original.toJson()));

        expect(upgraded.scope, isNull);
        expect(upgraded.timing, isNull);
        expect(upgraded.input, isNull);
        expect(upgraded.decision?.rankKey, original.decision?.rankKey);
      }
    });
  });

  group('version 7 to current', () {
    test('reads a presentation as having shown no continuing beat', () {
      final json = journal.records.first.toJson()
        ..['presentation'] = encodePresentation(
          PresentationRecord(
            policyVersion: 'v1-presentation-0',
            conditions: PresentationConditions(
              pitchCue: PitchCue.none,
              motorCue: MotorCue.none,
              performanceFeedback: PerformanceFeedback.neutralEcho,
              tempoSupport: TempoSupport.countInOnly,
            ),
            delivery: PresentationDelivery(tempo: TempoDelivery.complete(4)),
          ),
        );
      final upgraded = AttemptRecord.fromJson(version7(json));

      expect(upgraded.presentation!.delivery.shownContinuingBeats, 0);
      expect(
        upgraded.presentation!.delivery.suppliedPulseDuringAttempt,
        isFalse,
      );
    });
  });

  group('version 6 to current', () {
    Map<String, Object?> withPresentation(
      Map<String, Object?> json,
      TempoSupport tempoSupport,
    ) => json
      ..['presentation'] = encodePresentation(
        PresentationRecord(
          policyVersion: 'v1-presentation-0',
          conditions: PresentationConditions(
            pitchCue: PitchCue.none,
            motorCue: MotorCue.none,
            performanceFeedback: PerformanceFeedback.neutralEcho,
            tempoSupport: tempoSupport,
          ),
          delivery: PresentationDelivery(
            tempo: TempoDelivery(
              countInBeats: 4,
              continuingBeats: 0,
              deliveredCountInBeats: 3,
              deliveredContinuingBeats: 0,
            ),
          ),
        ),
      );

    test('reads every outcome as having tested the pulse', () {
      for (final original in journal.records) {
        final upgraded = AttemptRecord.fromJson(version6(original.toJson()));

        expect(
          measuredOf(upgraded).outcome.pulseMaintenance,
          PulseMaintenance.tested,
        );
        expect(measuredOf(upgraded).outcome, measuredOf(original).outcome);
      }
    });

    test('reads every beat of a pulse as counting in', () {
      final json = withPresentation(
        journal.records.first.toJson(),
        TempoSupport.countInOnly,
      );
      final upgraded = AttemptRecord.fromJson(version6(json));
      final tempo = upgraded.presentation!.delivery.tempo;

      expect(tempo.deliveredCountInBeats, 3);
      expect(tempo.countInBeats, 4);
      expect(tempo.continuingBeats, 0);
      expect(tempo.suppliedDuringAttempt, isFalse);
    });

    test('refuses a metronome whose beats it cannot split', () {
      final json = withPresentation(
        journal.records.first.toJson(),
        TempoSupport.metronomeThroughout,
      );

      expect(
        () => AttemptRecord.fromJson(version6(json)),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('an upgraded journal replays to the same learner state', () {
      final upgraded = AttemptJournal(journal.header);
      for (final record in journal.records) {
        upgraded.append(AttemptRecord.fromJson(version6(record.toJson())));
      }

      final before = replayJournal(
        journal,
        model: model,
        initial: recorded.initial.copy(),
      );
      final after = replayJournal(
        upgraded,
        model: model,
        initial: recorded.initial.copy(),
      );

      expect(after.stateHash, before.stateHash);
      expect(after.divergences, isEmpty);
    });
  });

  test('a version this build cannot read fails loudly', () {
    final json = journal.records.first.toJson()..['schema_version'] = 99;

    expect(
      () => AttemptRecord.fromJson(json),
      throwsA(isA<JournalFormatException>()),
    );
  });
}
