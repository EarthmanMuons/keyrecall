import 'package:flutter/foundation.dart';

import 'package:material_ui/material_ui.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'exercise_presentation.dart';

/// The best true thing about an attempt, or null when there is none.
///
/// Deliberately one thing and deliberately positive. A learner mid-sitting is
/// deciding whether to keep going, and a list of everything that happened is
/// what the fluency profile is for; this is the sentence that makes the
/// attempt feel finished.
///
/// Positive-only is a presentation choice, not a hidden one: nothing here
/// softens or omits evidence, because the evidence has already been written to
/// the journal in full by the time anyone reads this.
///
/// Returns null rather than inventing praise. An attempt that never started,
/// or one that fell apart, gets no sentence, and the screen says something
/// factual instead of congratulating a learner on nothing.
String? praiseFor(Exercise exercise, Outcome outcome) {
  if (!outcome.started) return null;

  final fromMemory = outcome.retrieval == FactualRetrieval.succeeded;

  if (outcome.completed && outcome.pitchIntegrity >= 0.999) {
    return fromMemory ? 'Every note, from memory.' : 'Every note right.';
  }
  if (outcome.completed && outcome.temporalStability >= 0.8) {
    return 'Nice and steady the whole way.';
  }
  if (outcome.completed && outcome.continuity >= 0.9) {
    return 'Straight through, no stopping.';
  }
  if (outcome.completed) {
    return fromMemory
        ? 'You got there from memory.'
        : 'All the way to the end.';
  }
  if (fromMemory) return 'You had the notes.';
  return null;
}

/// Why the scheduler chose what it chose, when it can be said honestly.
///
/// Only the named exceptions are stated. Those are recorded on the decision
/// and mean exactly one thing each. An ordinary admission wins on a
/// lexicographic key against candidates the decision does not keep, so which
/// term decided it is not something this can know, and it says nothing rather
/// than guessing.
String? reasonForNext({
  required SchedulerDecision decision,
  required Exercise next,
  required Exercise previous,
}) {
  final sameMaterial = next.material == previous.material;

  return switch (decision.challengeBypass) {
    ChallengeBypass.recovery =>
      sameMaterial
          ? 'The same scale again, with more of it shown.'
          : 'Going back a step.',
    ChallengeBypass.newMaterial => 'New here, so it comes with the notes.',
    ChallengeBypass.guidanceProbe ||
    ChallengeBypass.bootstrapProbe => 'Time to try this one with less help.',
    ChallengeBypass.override => null,
    null => sameMaterial ? 'Again, with something changed.' : null,
  };
}

/// What just happened, and what is next.
///
/// Shown between attempts, over a decision that has already been made: the
/// scheduler runs while this is being read, so Next is instant rather than
/// being the moment the work starts. Nothing on this screen is waited on and
/// nothing animates in.
class AttemptReview extends StatelessWidget {
  const AttemptReview({
    required this.record,
    required this.next,
    required this.onNext,
    super.key,
  });

  /// The attempt that just closed.
  final AttemptRecord record;

  /// What has been decided to come next, if anything.
  final PresentedAttempt? next;

  /// Dismisses this and puts the next exercise on screen.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final closure = record.closure;
    final praise = switch (closure.measurement) {
      Measured(:final outcome) => praiseFor(record.exercise, outcome),
      MeasurementUnavailable() => null,
    };
    final upcoming = next;
    final reason = upcoming == null
        ? null
        : reasonForNext(
            decision: upcoming.decision.decision,
            next: upcoming.exercise,
            previous: record.exercise,
          );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            praise ?? 'Logged.',
            style: theme.textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (upcoming != null) ...[
            Text(
              'Next',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              materialName(upcoming.exercise.material),
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (reason != null) ...[
              const SizedBox(height: 4),
              Text(
                reason,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
          const Spacer(),
          if (!kReleaseMode) ...[
            _Measured(record: record, next: upcoming),
            const SizedBox(height: 16),
          ],
          SizedBox(
            height: 88,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                textStyle: theme.textTheme.headlineSmall,
              ),
              child: Text(upcoming == null ? 'Done' : 'Next'),
            ),
          ),
        ],
      ),
    );
  }
}

/// The numbers behind the sentence above it.
///
/// Debug and profile only. The learner is told one true thing; this is for
/// whoever is deciding whether that thing was the right one to say, and for
/// watching values that now change what is learned. Achieved tempo especially:
/// it sets the difficulty execution evidence is attributed at, so a systematic
/// offset between the click and the transcript clock would show up here first.
class _Measured extends StatelessWidget {
  const _Measured({required this.record, required this.next});

  final AttemptRecord record;
  final PresentedAttempt? next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decision = next?.decision.decision;
    final rows = <(String, String)>[
      ('termination', record.closure.termination.id),
      ...switch (record.closure.measurement) {
        Measured(:final outcome, :final weights) => [
          ('retrieval', outcome.retrieval.name),
          ('started / completed', '${outcome.started} / ${outcome.completed}'),
          ('achieved tempo', outcome.achievedTempoRatio.toStringAsFixed(3)),
          (
            'attributed at',
            '${(record.exercise.conditions.tempoBpm * outcome.achievedTempoRatio.clamp(0, 1)).round()} '
                'of ${record.exercise.conditions.tempoBpm.round()} bpm',
          ),
          ('motor score', outcome.motorScore.toStringAsFixed(3)),
          ('pitch integrity', outcome.pitchIntegrity.toStringAsFixed(3)),
          ('continuity', outcome.continuity.toStringAsFixed(3)),
          ('temporal stability', outcome.temporalStability.toStringAsFixed(3)),
          ('topology accuracy', outcome.topologyAccuracy.toStringAsFixed(3)),
          (
            'weights exec / mem',
            '${weights.materialExecution.toStringAsFixed(2)} / '
                '${weights.materialMemory.toStringAsFixed(2)}',
          ),
        ],
        MeasurementUnavailable(:final reason) => [('unmeasured', reason.id)],
      },
      if (decision != null) ...[
        ('next tier', decision.eligibilityTier.id),
        ('next bypass', decision.challengeBypass?.id ?? 'none'),
        ('next predicted', decision.prediction.overallP.toStringAsFixed(3)),
      ],
    ];

    return Align(
      alignment: Alignment.centerLeft,
      child: DefaultTextStyle(
        style: theme.textTheme.bodySmall!.copyWith(
          fontFamily: 'monospace',
          color: theme.colorScheme.onSurfaceVariant,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in rows)
              Text('${label.padRight(20)} $value'),
          ],
        ),
      ),
    );
  }
}
