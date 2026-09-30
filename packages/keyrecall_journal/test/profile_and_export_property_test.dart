import 'dart:convert';

import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:kiri_check/kiri_check.dart';
import 'package:test/test.dart';

import 'package:keyrecall_journal/keyrecall_journal.dart';

import 'support/journal_arbitraries.dart';

final Arbitrary<Profile> anyProfile =
    combine5(
      anyProfileId,
      anyText,
      anyTime,
      choiceOf(PlacementTier.values),
      optional(anyText),
    ).map(
      (parts) => Profile(
        id: parts.$1,
        displayName: parts.$2,
        createdAt: parts.$3,
        placement: parts.$4,
        presentationHint: parts.$5,
      ),
    );

/// A session as the app exports one: attempts numbered by their place, and
/// supported work from the same session no earlier than its start.
final Arbitrary<SessionExport> anyExport =
    combine5(
      anyProfileId,
      anyText,
      anyTime,
      list(
        combine3(anyExercise, anyOutcome, choiceOf(MaterialFamiliarity.values)),
        maxLength: 8,
      ),
      list(
        combine3(
          anyAttemptContent,
          anyExercise,
          integer(min: 0, max: 30 * 86400000),
        ),
        maxLength: 4,
      ),
    ).map((parts) {
      final (profileId, sessionId, startedAt, attempts, supported) = parts;
      return SessionExport(
        profileId: profileId,
        sessionId: sessionId,
        startedAt: startedAt,
        attempts: [
          for (final (index, (exercise, outcome, familiarity))
              in attempts.indexed)
            ExportedAttempt(
              index: index,
              exercise: exercise,
              outcome: outcome,
              familiarity: familiarity,
            ),
        ],
        acquisition: [
          for (final (index, (content, parent, delayMs)) in supported.indexed)
            attemptOf(
              content,
              parent: parent,
              journalSequence: index,
              identity: AttemptIdentity(
                profileId: profileId,
                attemptId: 'supported-$index',
                sessionId: sessionId,
                indexInSession: index,
                occurredAt: switch (startedAt.add(
                  Duration(milliseconds: delayMs),
                )) {
                  final later when later.year <= 9999 => later,
                  _ => startedAt,
                },
              ),
            ),
        ],
      );
    });

/// What an export says, compared with the domain's own equality where the
/// types have one.
List<Object?> meaningOf(SessionExport export) => [
  export.schemaVersion,
  export.profileId,
  export.sessionId,
  export.startedAt,
  for (final attempt in export.attempts)
    [
      attempt.index,
      attempt.exercise,
      attempt.exercise.guidance,
      attempt.exercise.opportunities,
      attempt.exercise.opportunitySites,
      attempt.outcome,
      attempt.familiarity,
    ],
  for (final record in export.acquisition)
    [record.identity, record.task, canonicalJson(record.toJson())],
];

void main() {
  property('a profile reads back as what was written', () {
    forAll(
      anyProfile,
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      failingOnErrors<Profile>((profile) {
        final back = Profile.fromJson(
          jsonDecode(stored(canonicalJson(profile.toJson())))
              as Map<String, Object?>,
        );

        expect(back, profile);
        expect(canonicalJson(back.toJson()), canonicalJson(profile.toJson()));
      }),
    );
  });

  property('renaming or reshowing a profile keeps who it is', () {
    forAll(
      combine3(anyProfile, anyText, optional(anyText)),
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      failingOnErrors<(Profile, String, String?)>((parts) {
        final (profile, name, hint) = parts;
        final renamed = profile.renamed(name);
        final shown = profile.shownAs(hint);

        expect(renamed, predicate<Profile>((p) => p.displayName == name));
        expect(shown, predicate<Profile>((p) => p.presentationHint == hint));
        for (final changed in [renamed, shown]) {
          expect(changed.id, profile.id);
          expect(changed.createdAt, profile.createdAt);
          expect(changed.placement, profile.placement);
        }
        expect(renamed.presentationHint, profile.presentationHint);
        expect(shown.displayName, profile.displayName);
      }),
    );
  });

  property('an export reads back as what was written', () {
    forAll(
      anyExport,
      seed: propertySeed,
      maxExamples: propertyBudget(200),
      failingOnErrors<SessionExport>((export) {
        final back = decodeSessionExport(stored(encodeSessionExport(export)));

        expect(meaningOf(back), meaningOf(export));
        expect(encodeSessionExport(back), encodeSessionExport(export));
      }),
    );
  });
}
