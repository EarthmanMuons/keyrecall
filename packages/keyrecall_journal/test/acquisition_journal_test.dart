import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

void main() {
  final material = TechnicalMaterial('C', ScaleForm.major);
  final parent = Exercise.linear(
    material: material,
    hands: HandConfiguration.right,
    octaves: 1,
    direction: ExerciseDirection.up,
    tempoBpm: 60,
    guidance: GuidanceContext.continuouslyCued,
  );
  final task = AcquisitionTask.unmeteredTraversal(parent);
  final t0 = DateTime.utc(2026, 9, 9, 10);

  AcquisitionJournal emptyLog() => AcquisitionJournal(
    AcquisitionJournalHeader(profileId: 'abc12345', createdAt: t0),
  );

  AcquisitionAttemptRecord recordAt(
    int sequence, {
    AcquisitionCompletion completion = AcquisitionCompletion.completedCleanly,
    bool earnedProbe = true,
    Duration after = Duration.zero,
    String? attemptId,
    List<RecordedGap> gaps = const [],
  }) => AcquisitionAttemptRecord(
    journalSequence: sequence,
    identity: AttemptIdentity(
      profileId: 'abc12345',
      attemptId: attemptId ?? 'acq-$sequence',
      sessionId: 'sitting-1',
      indexInSession: sequence,
      occurredAt: t0.add(after),
    ),
    task: task,
    started: true,
    completion: completion,
    repairs: 1,
    repeats: 0,
    intrusions: 1,
    firstAbsentPosition: completion.isComplete ? null : 4,
    earnedProbe: earnedProbe,
    gaps: gaps,
  );

  test('replay uses append order when service and success share a time', () {
    final log = emptyLog()..append(recordAt(0));
    log.append(
      AcquisitionProbeServedRecord(
        journalSequence: 1,
        identity: AttemptIdentity(
          profileId: 'abc12345',
          attemptId: 'probe',
          sessionId: 'sitting-1',
          indexInSession: 1,
          occurredAt: t0,
        ),
        parent: parent,
      ),
    );
    log.append(recordAt(2));
    final restored = AcquisitionJournal.fromJsonLines(
      log.toJsonLines(),
    ).replay();
    expect(restored.probeOwed(parent), isTrue);
    expect(restored.recordFor(parent)!.criterionSuccessesServed, 1);
  });

  group('a round trip', () {
    test('preserves the facts and the verdict that was recorded', () {
      final log = emptyLog()
        ..append(
          recordAt(
            0,
            gaps: const [
              (fromPosition: 2, toPosition: 3, gapMs: 4000, ratio: 4.4),
              (fromPosition: 3, toPosition: 4, gapMs: 900, ratio: 1.0),
            ],
          ),
        );

      final read = AcquisitionJournal.fromJsonLines(log.toJsonLines());
      final record = read.attempts.single;

      expect(read.header.profileId, 'abc12345');
      expect(record.task, task);
      expect(record.completion, AcquisitionCompletion.completedCleanly);
      expect(record.repairs, 1);
      expect(record.intrusions, 1);
      expect(record.earnedProbe, isTrue);
      expect(record.gaps.first.gapMs, 4000);
      expect(record.gaps.first.ratio, closeTo(4.4, 1e-9));
    });

    test('keeps the gaps a later threshold would be asked of', () {
      // The ratio is measured, and what counts as a stall is a threshold over
      // it. Storing the ratio is what lets a threshold that moves be asked of
      // an attempt that happened before it did.
      final log = emptyLog()
        ..append(
          recordAt(
            0,
            gaps: const [
              (fromPosition: 1, toPosition: 2, gapMs: 2100, ratio: 2.3),
            ],
          ),
        );
      final record = AcquisitionJournal.fromJsonLines(
        log.toJsonLines(),
      ).attempts.single;

      expect(record.gaps.single.ratio, closeTo(2.3, 1e-9));
    });
  });

  group('a log written before termination was recorded', () {
    test('reads back without a cause being invented for it', () {
      final current = (emptyLog()..append(recordAt(0))).toJsonLines();
      final legacy = current
          .split('\n')
          .map((line) {
            final json = jsonDecode(line) as Map<String, Object?>;
            json['schema_version'] = 1;
            json.remove('termination');
            return jsonEncode(json);
          })
          .join('\n');

      final read = AcquisitionJournal.fromJsonLines(legacy);
      final record = read.attempts.single;

      // The older format did not distinguish the learner stopping from an
      // input disconnection, and this preserves that rather than choosing.
      expect(record.termination, isNull);
      expect(record.completion, AcquisitionCompletion.completedCleanly);
      expect(read.replay().probeOwed(parent), isTrue);
    });

    test('reads back saying nothing where two causes were written alike', () {
      // Version 2 wrote the learner stopping and the app ending a covered
      // traversal identically, so neither can be recovered from it.
      final current = (emptyLog()..append(recordAt(0))).toJsonLines();
      final version2 = current
          .split('\n')
          .map((line) {
            final json = jsonDecode(line) as Map<String, Object?>;
            json['schema_version'] = 2;
            if (json.containsKey('termination')) {
              json['termination'] = 'LEARNER_STOPPED';
            }
            return jsonEncode(json);
          })
          .join('\n');

      expect(
        AcquisitionJournal.fromJsonLines(version2).attempts.single.termination,
        isNull,
      );
    });

    test('keeps a version 2 cause that was never ambiguous', () {
      final current = (emptyLog()..append(recordAt(0))).toJsonLines();
      final version2 = current
          .split('\n')
          .map((line) {
            final json = jsonDecode(line) as Map<String, Object?>;
            json['schema_version'] = 2;
            if (json.containsKey('termination')) {
              json['termination'] = 'INPUT_INTERRUPTED';
            }
            return jsonEncode(json);
          })
          .join('\n');

      expect(
        AcquisitionJournal.fromJsonLines(version2).attempts.single.termination,
        AttemptTermination.inputInterrupted,
      );
    });

    test('is still refused at a version this build cannot read', () {
      final ahead = (emptyLog()..append(recordAt(0))).toJsonLines().replaceAll(
        '"schema_version":$acquisitionSchemaVersion',
        '"schema_version":99',
      );

      expect(
        () => AcquisitionJournal.fromJsonLines(ahead),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('appending', () {
    test('is idempotent for the same attempt', () {
      final log = emptyLog();

      expect(log.append(recordAt(0)), isTrue);
      expect(log.append(recordAt(0)), isFalse);
      expect(log.length, 1);
    });

    test('refuses an id that returns with different content', () {
      final log = emptyLog()..append(recordAt(0));

      expect(
        () => log.append(
          recordAt(
            0,
            completion: AcquisitionCompletion.completedWithCorrections,
            earnedProbe: false,
          ),
        ),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('refuses a gap in the sequence', () {
      final log = emptyLog()..append(recordAt(0));

      expect(
        () => log.append(recordAt(2)),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('refuses a timeline that runs backward', () {
      final log = emptyLog()
        ..append(recordAt(0, after: const Duration(hours: 1)));

      expect(
        () => log.append(recordAt(1)),
        throwsA(isA<JournalFormatException>()),
      );
    });

    test('refuses another profile history', () {
      final log = AcquisitionJournal(
        AcquisitionJournalHeader(profileId: 'zzz99999', createdAt: t0),
      );

      expect(
        () => log.append(recordAt(0)),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('the two logs', () {
    test('refuse each other records', () {
      final acquisition = emptyLog()..append(recordAt(0));

      expect(
        () => AttemptJournal.fromJsonLines(acquisition.toJsonLines()),
        throwsA(isA<JournalFormatException>()),
      );
    });
  });

  group('a served probe', () {
    AcquisitionProbeServedRecord serviceAt(
      int sequence, {
      Duration after = Duration.zero,
    }) => AcquisitionProbeServedRecord(
      journalSequence: sequence,
      identity: AttemptIdentity(
        profileId: 'abc12345',
        attemptId: 'probe-$sequence',
        sessionId: 'sitting-1',
        indexInSession: sequence,
        occurredAt: t0.add(after),
      ),
      parent: parent,
    );

    test('discharges what a criterion success earned', () {
      final log = emptyLog()..append(recordAt(0));
      expect(log.replay().probeOwed(parent), isTrue);

      log.append(serviceAt(1, after: const Duration(minutes: 2)));
      final progress = log.replay();

      // Asked, and therefore no longer owed. The success that earned it is
      // still in the history.
      expect(progress.probeOwed(parent), isFalse);
      expect(progress.earnsParentProbe(parent), isTrue);
      expect(progress.recordFor(parent)!.probesServed, 1);
    });

    test('lets a parent that is still stuck earn another', () {
      // The cycle the whole design is for: stuck, acquire, earn, ask, still
      // stuck, acquire again. A first success must not latch acquisition off
      // forever.
      final log = emptyLog()
        ..append(recordAt(0))
        ..append(serviceAt(1, after: const Duration(minutes: 2)))
        ..append(recordAt(2, after: const Duration(minutes: 5)));

      expect(log.replay().probeOwed(parent), isTrue);
      expect(log.replay().recordFor(parent)!.criterionSuccesses, 2);
    });

    test('discharges every success asked before it, not one each', () {
      // The obligation is to ask the question, so asking it once answers
      // everything earned up to then.
      final log = emptyLog()
        ..append(recordAt(0))
        ..append(recordAt(1, after: const Duration(minutes: 1)))
        ..append(serviceAt(2, after: const Duration(minutes: 2)));

      expect(log.replay().recordFor(parent)!.criterionSuccesses, 2);
      expect(log.replay().probeOwed(parent), isFalse);
    });

    test('survives a round trip with the attempts beside it', () {
      final log = emptyLog()
        ..append(recordAt(0))
        ..append(serviceAt(1, after: const Duration(minutes: 2)));

      final read = AcquisitionJournal.fromJsonLines(log.toJsonLines());
      expect(read.records, hasLength(2));
      expect(read.attempts, hasLength(1));
      expect(read.replay().byParent, log.replay().byParent);
      expect(
        (read.records.last as AcquisitionProbeServedRecord).identity.attemptId,
        'probe-1',
      );
    });

    test('is refused for a parent with no acquisition history', () {
      // Service of an obligation that never existed.
      final log = emptyLog()..append(serviceAt(0));

      expect(log.replay, throwsArgumentError);
    });
  });

  group('replay', () {
    test('produces progress and nothing else', () {
      final log = emptyLog()
        ..append(
          recordAt(
            0,
            completion: AcquisitionCompletion.completedWithCorrections,
            earnedProbe: false,
          ),
        )
        ..append(recordAt(1, after: const Duration(minutes: 5)))
        ..append(
          recordAt(
            2,
            completion: AcquisitionCompletion.notCompleted,
            earnedProbe: false,
            after: const Duration(minutes: 9),
          ),
        );

      final progress = log.replay();
      final record = progress.recordFor(parent)!;

      expect(record.attempts, 3);
      expect(record.completions, 2);
      expect(record.criterionSuccesses, 1);
      expect(record.lastCriterionSuccessAt, t0.add(const Duration(minutes: 5)));
      expect(progress.earnsParentProbe(parent), isTrue);
    });

    test('is the same progress after a restart', () {
      // The property the whole log exists for. Progress is whatever replaying
      // history produces, so it cannot disappear across a restart or a sitting
      // boundary.
      final log = emptyLog()
        ..append(recordAt(0))
        ..append(recordAt(1, after: const Duration(days: 4)));

      expect(
        AcquisitionJournal.fromJsonLines(log.toJsonLines()).replay().byParent,
        log.replay().byParent,
      );
    });

    test('keeps a past verdict when the rule moves', () {
      // The verdict is stored beside the facts, so replaying an old attempt
      // reproduces what happened rather than what today's rule would say.
      final log = emptyLog()
        ..append(
          recordAt(
            0,
            gaps: const [
              (fromPosition: 1, toPosition: 2, gapMs: 9000, ratio: 9.0),
            ],
          ),
        );

      // A gap that any stall threshold would read as a break, on an attempt
      // recorded as a criterion success.
      expect(log.attempts.single.gaps.single.ratio, greaterThan(3.0));
      expect(log.replay().earnsParentProbe(parent), isTrue);
    });
  });
}
