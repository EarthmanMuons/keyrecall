import 'dart:convert';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/journal_arbitraries.dart';

final Arbitrary<TaskPortion> anyPortion = weighted<TaskPortion>([
  (2, constant(const FullTraversal())),
  (1, integer(min: 2, max: 8).map(TraversalRepetitions.new)),
]);

final Arbitrary<RecordedGap> anyGap =
    combine4(
      anyCount,
      integer(min: 1, max: 64),
      anyCount,
      optional(anyScore),
    ).map(
      (parts) => (
        fromPosition: parts.$1,
        toPosition: parts.$1 + parts.$2,
        gapMs: parts.$3,
        ratio: parts.$4 == null ? null : parts.$4! * 8,
      ),
    );

/// Everything about an acquisition attempt but its parent and its place in a
/// log.
typedef AttemptContent = ({
  DateTime? observedWallTime,
  int? executionEvidenceRevision,
  TaskPortion portion,
  PresentationRecord? presentation,
  bool started,
  AttemptTermination? termination,
  AcquisitionCompletion completion,
  (int, int, int) corrections,
  int? firstAbsentPosition,
  List<RecordedGap> gaps,
  CriterionVerdict sequence,
  CriterionVerdict continuity,
});

final Arbitrary<AttemptContent> anyAttemptContent =
    combine2(
      combine8(
        optional(anyTime),
        optional(anyCount),
        anyPortion,
        optional(anyPresentation),
        boolean(),
        optional(choiceOf(AttemptTermination.values)),
        choiceOf(AcquisitionCompletion.values),
        combine3(anyCount, anyCount, anyCount),
      ),
      combine4(
        optional(anyCount),
        list(anyGap, maxLength: 6),
        choiceOf(CriterionVerdict.values),
        choiceOf(CriterionVerdict.values),
      ),
    ).map((parts) {
      final (
        observed,
        revision,
        portion,
        presentation,
        started,
        termination,
        completion,
        corrections,
      ) = parts.$1;
      final (firstAbsent, gaps, sequence, continuity) = parts.$2;
      // A capture that may have lost events judges no criterion, and a probe
      // is earned by both criteria and only as a completion.
      final interrupted = termination == AttemptTermination.inputInterrupted;
      final judgedSequence = interrupted
          ? CriterionVerdict.unavailable
          : sequence;
      final judgedContinuity = interrupted
          ? CriterionVerdict.unavailable
          : continuity;
      final earnsProbe =
          judgedSequence == CriterionVerdict.met &&
          judgedContinuity == CriterionVerdict.met;
      return (
        observedWallTime: observed,
        executionEvidenceRevision: revision,
        portion: portion,
        presentation: presentation,
        started: started,
        termination: termination,
        completion: earnsProbe && !completion.isComplete
            ? AcquisitionCompletion.completedWithCorrections
            : completion,
        corrections: corrections,
        firstAbsentPosition: firstAbsent,
        gaps: gaps,
        sequence: judgedSequence,
        continuity: judgedContinuity,
      );
    });

AcquisitionAttemptRecord attemptOf(
  AttemptContent content, {
  required Exercise parent,
  required int journalSequence,
  required AttemptIdentity identity,
}) => AcquisitionAttemptRecord(
  journalSequence: journalSequence,
  identity: identity,
  observedWallTime: content.observedWallTime,
  executionEvidenceRevision: content.executionEvidenceRevision,
  task: AcquisitionTask(
    parent: parent,
    timing: TimingDemand.unmetered,
    advancement: TaskAdvancement.learnerDriven,
    portion: content.portion,
  ),
  presentation: content.presentation,
  started: content.started,
  termination: content.termination,
  completion: content.completion,
  repairs: content.corrections.$1,
  repeats: content.corrections.$2,
  intrusions: content.corrections.$3,
  firstAbsentPosition: content.firstAbsentPosition,
  gaps: content.gaps,
  earnedProbe:
      content.sequence == CriterionVerdict.met &&
      content.continuity == CriterionVerdict.met,
  sequence: content.sequence,
  continuity: content.continuity,
);

final Arbitrary<AttemptIdentity> anyIdentity =
    combine5(anyProfileId, anyText, anyText, anyCount, anyTime).map(
      (parts) => AttemptIdentity(
        profileId: parts.$1,
        attemptId: parts.$2,
        sessionId: parts.$3,
        indexInSession: parts.$4,
        occurredAt: parts.$5,
      ),
    );

final Arbitrary<AcquisitionAttemptRecord> anyAttempt =
    combine4(anyAttemptContent, anyExercise, anyCount, anyIdentity).map(
      (parts) => attemptOf(
        parts.$1,
        parent: parts.$2,
        journalSequence: parts.$3,
        identity: parts.$4,
      ),
    );

final Arbitrary<AcquisitionProbeServedRecord> anyProbe =
    combine4(optional(anyTime), anyExercise, anyCount, anyIdentity).map(
      (parts) => AcquisitionProbeServedRecord(
        observedWallTime: parts.$1,
        parent: parts.$2,
        journalSequence: parts.$3,
        identity: parts.$4,
      ),
    );

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
      seed: seed,
      maxExamples: examples(400),
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
      seed: seed,
      maxExamples: examples(200),
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
      seed: seed,
      maxExamples: examples(100),
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
      seed: seed,
      maxExamples: examples(100),
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

  test('the generated attempts reach every variant', () {
    expect(reached, containsAll(AttemptTermination.values));
    expect(reached, containsAll(AcquisitionCompletion.values));
    expect(reached, containsAll(CriterionVerdict.values));
    expect(reached, containsAll([FullTraversal, TraversalRepetitions]));
  });
}
