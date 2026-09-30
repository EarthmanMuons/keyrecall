import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/journal_arbitraries.dart';

final DateTime t0 = DateTime.utc(2026);

/// What an entry says, compared with the domain's own equality rather than
/// through the codec under test.
List<Object?> meaningOf(AcquisitionEntry entry) => [
  entry.journalSequence,
  entry.identity,
  entry.parent,
  entry.parent.guidance,
  entry.parent.opportunities,
  entry.parent.opportunitySites,
  ...switch (entry) {
    AcquisitionAttemptRecord() => [
      entry.schemaVersion,
      entry.observedWallTime,
      entry.executionEvidenceRevision,
      entry.task,
      entry.presentation,
      entry.started,
      entry.termination,
      entry.completion,
      entry.repairs,
      entry.repeats,
      entry.intrusions,
      entry.firstAbsentPosition,
      entry.gaps,
      entry.earnedProbe,
      entry.sequence,
      entry.continuity,
    ],
    AcquisitionProbeServedRecord() => [
      entry.schemaVersion,
      entry.observedWallTime,
    ],
  },
];

Map<String, Object?> storedJson(Map<String, Object?> json) =>
    jsonDecode(stored(canonicalJson(json))) as Map<String, Object?>;

/// One log entry before it is placed: whether it serves a probe, which of the
/// log's parents it is about, and how long after the previous entry it came.
typedef Planned = (bool, int, AttemptContent, DateTime?, int);

/// Arranges [planned] into a log the app could have written: one profile,
/// contiguous sequence, time that never runs backward, and a probe served
/// only for a parent that has acquisition history.
AcquisitionJournal logOf(
  String profileId,
  DateTime createdAt,
  List<Exercise> parents,
  List<Planned> planned,
) {
  final log = AcquisitionJournal(
    AcquisitionJournalHeader(profileId: profileId, createdAt: createdAt),
  );
  var occurredAt = createdAt;
  final attempted = <Exercise>{};
  for (final (sequence, (serves, which, content, observed, gapMicros))
      in planned.indexed) {
    final parent = parents[which % parents.length];
    final later = occurredAt.add(Duration(microseconds: gapMicros));
    occurredAt = later.year > 9999 ? occurredAt : later;
    final identity = AttemptIdentity(
      profileId: profileId,
      attemptId: 'entry-$sequence',
      sessionId: 'session',
      indexInSession: sequence,
      occurredAt: occurredAt,
    );
    if (serves && attempted.contains(parent)) {
      log.append(
        AcquisitionProbeServedRecord(
          journalSequence: sequence,
          identity: identity,
          observedWallTime: observed,
          parent: parent,
        ),
      );
    } else {
      attempted.add(parent);
      log.append(
        attemptOf(
          content,
          parent: parent,
          journalSequence: sequence,
          identity: identity,
        ),
      );
    }
  }
  return log;
}

/// Every enum value and portion the generated attempts reached.
final Set<Object> reached = {};

void main() {
  property('an acquisition attempt reads back as what was written', () {
    forAll(
      anyAttempt,
      seed: propertySeed,
      maxExamples: propertyBudget(400),
      failingOnErrors<AcquisitionAttemptRecord>((record) {
        reached.addAll([
          ?record.termination,
          record.completion,
          record.sequence,
          record.continuity,
          record.task.portion.runtimeType,
        ]);
        final back = AcquisitionAttemptRecord.fromJson(
          storedJson(record.toJson()),
        );

        expect(meaningOf(back), meaningOf(record));
        expect(canonicalJson(back.toJson()), canonicalJson(record.toJson()));
        expect(contentHash(back.toJson()), contentHash(record.toJson()));
      }),
    );
  });

  property('a served probe reads back as what was written', () {
    forAll(
      anyProbe,
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      failingOnErrors<AcquisitionProbeServedRecord>((record) {
        final back = AcquisitionProbeServedRecord.fromJson(
          storedJson(record.toJson()),
        );

        expect(meaningOf(back), meaningOf(record));
        expect(canonicalJson(back.toJson()), canonicalJson(record.toJson()));
      }),
    );
  });

  property('an acquisition log header reads back as what was written', () {
    forAll(
      combine2(anyProfileId, anyTime),
      seed: propertySeed,
      maxExamples: propertyBudget(100),
      failingOnErrors<(String, DateTime)>((parts) {
        final header = AcquisitionJournalHeader(
          profileId: parts.$1,
          createdAt: parts.$2,
        );
        final back = AcquisitionJournalHeader.fromJson(
          storedJson(header.toJson()),
        );

        expect(back.profileId, header.profileId);
        expect(back.createdAt, header.createdAt);
        expect(canonicalJson(back.toJson()), canonicalJson(header.toJson()));
      }),
    );
  });

  property('a mixed log reads back whole, in order, replaying the same', () {
    forAll(
      combine4(
        anyProfileId,
        anyTime,
        list(anyExercise, minLength: 1, maxLength: 3),
        list(
          combine5(
            weighted<bool>([(3, constant(false)), (1, constant(true))]),
            integer(min: 0, max: 2),
            anyAttemptContent,
            optional(anyTime),
            weighted<int>([
              (4, integer(min: 0, max: 86400000000)),
              (1, constant(0)),
            ]),
          ),
          maxLength: 12,
        ),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(100),
      failingOnErrors<(String, DateTime, List<Exercise>, List<Planned>)>((
        parts,
      ) {
        final log = logOf(parts.$1, parts.$2, parts.$3, parts.$4);
        final back = AcquisitionJournal.fromJsonLines(
          stored(log.toJsonLines()),
        );

        expect(back.header.profileId, log.header.profileId);
        expect(back.header.createdAt, log.header.createdAt);
        expect(back.records.map(meaningOf), log.records.map(meaningOf));
        expect(back.toJsonLines(), log.toJsonLines());
        expect(back.replay().byParent, log.replay().byParent);
        for (final record in back.records) {
          expect(
            log.append(record),
            isFalse,
            reason: 'an entry read back is the one already appended',
          );
        }
      }),
    );
  });

  property('whatever a log accepts, it can replay', () {
    forAll(
      combine2(
        list(anyExercise, minLength: 1, maxLength: 3),
        list(
          combine3(boolean(), integer(min: 0, max: 2), anyAttemptContent),
          maxLength: 12,
        ),
      ),
      seed: propertySeed,
      maxExamples: propertyBudget(100),
      failingOnErrors<(List<Exercise>, List<(bool, int, AttemptContent)>)>((
        parts,
      ) {
        final (parents, planned) = parts;
        final log = AcquisitionJournal(
          AcquisitionJournalHeader(profileId: 'learner', createdAt: t0),
        );
        for (final (index, (serves, which, content)) in planned.indexed) {
          final parent = parents[which % parents.length];
          final identity = AttemptIdentity(
            profileId: 'learner',
            attemptId: 'entry-$index',
            sessionId: 'session',
            indexInSession: index,
            occurredAt: t0.add(Duration(minutes: index)),
          );
          try {
            log.append(
              serves
                  ? AcquisitionProbeServedRecord(
                      journalSequence: log.nextSequence,
                      identity: identity,
                      parent: parent,
                    )
                  : attemptOf(
                      content,
                      parent: parent,
                      journalSequence: log.nextSequence,
                      identity: identity,
                    ),
            );
          } on JournalFormatException {
            // Refused, which is the log keeping itself replayable.
          }
        }

        expect(log.replay, returnsNormally);
      }),
    );
  });

  test('the generated attempts reach every variant', () {
    expect(reached, containsAll(AttemptTermination.values));
    expect(reached, containsAll(AcquisitionCompletion.values));
    expect(reached, containsAll(CriterionVerdict.values));
    expect(reached, containsAll([FullTraversal, TraversalRepetitions]));
  });
}
