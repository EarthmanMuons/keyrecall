import 'package:flutter/foundation.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'attempt_diagnosis.dart';
import 'attempt_feedback.dart';
import 'exercise_presentation.dart';

/// Why the scheduler chose what it chose, when it can be said honestly.
///
/// Only the named exceptions are stated. Those are recorded on the decision
/// and mean exactly one thing each. An ordinary admission wins on a
/// lexicographic key against candidates the decision does not keep, so which
/// term decided it is not something this can know, and it falls back to
/// [differenceTo] rather than guessing.
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
    ChallengeBypass.consolidation =>
      sameMaterial
          ? 'That one again, this time from memory.'
          : 'One you have met, this time from memory.',
    ChallengeBypass.executionProgression =>
      sameMaterial
          ? 'The same one, a step further.'
          : 'One you know, a step further.',
    ChallengeBypass.guidanceProbe ||
    ChallengeBypass.bootstrapProbe ||
    ChallengeBypass.observationProbe => 'Time to try this one with less help.',
    ChallengeBypass.tempoProbe =>
      sameMaterial
          ? 'That looked easy. Same scale, at the speed you played it.'
          : 'That looked easy, so this one is quicker.',
    ChallengeBypass.override ||
    null => differenceTo(next, previous) ?? (sameMaterial ? 'Again.' : null),
  };
}

/// What is different about [next], when a learner would notice.
///
/// A fact about the pair rather than a reason for it. Stating what changed
/// claims nothing about the ranking that produced the change, which is what
/// makes this available where [reasonForNext] has nothing honest to say.
///
/// One difference, in salience order rather than in the order the exercise
/// happens to hold them. Two exercises can differ in every condition at once,
/// and reading the changelog is not what somebody with their hands on the keys
/// is there for. The scale itself is not in the order: its name is already on
/// the screen above this.
String? differenceTo(Exercise next, Exercise previous) {
  final conditions = next.conditions;
  final was = previous.conditions;

  if (conditions.hands != was.hands) {
    return switch (conditions.hands) {
      HandConfiguration.together => 'Both hands this time.',
      HandConfiguration.right => 'Right hand alone this time.',
      HandConfiguration.left => 'Left hand alone this time.',
    };
  }
  if (next.guidance != previous.guidance) {
    if (next.guidance == GuidanceContext.continuouslyCued) {
      return 'The notes stay up for this one.';
    }
    if (next.guidance == GuidanceContext.notesPreviewedOnly) {
      return 'A look at the notes first, then from memory.';
    }
    return 'This one is from memory.';
  }
  if (conditions.octaves != was.octaves) {
    return conditions.octaves == 1
        ? 'One octave this time.'
        : '${conditions.octaves} octaves this time.';
  }
  if (conditions.direction != was.direction) {
    return switch (conditions.direction) {
      ScaleDirection.up => 'Just up this time.',
      ScaleDirection.upDown => 'Up and back down this time.',
    };
  }
  if (conditions.tempoBpm != was.tempoBpm) {
    return conditions.tempoBpm > was.tempoBpm
        ? 'A little quicker.'
        : 'A little slower.';
  }
  return null;
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
    required this.history,
    this.reading,
    super.key,
  });

  /// The attempt that just closed.
  final AttemptRecord record;

  /// What it was read from, when the closure came from a performance.
  final PerformanceReading? reading;

  /// What has been decided to come next, if anything.
  final PresentedAttempt? next;

  /// Attempts available when deriving longitudinal progress evidence.
  final Iterable<AttemptRecord> history;

  /// Dismisses this and puts the next exercise on screen.
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final diagnosis = diagnose(
      exercise: record.exercise,
      closure: record.closure,
      reading: reading,
    );
    final upcoming = next;
    final summary = summarizeAttempt(record);
    final progress = progressEventFor(record, history: history);
    final reason = upcoming == null
        ? null
        : reasonForNext(
            decision: upcoming.decision.decision,
            next: upcoming.exercise,
            previous: record.exercise,
          );

    final layout = Layout.of(context);

    return Padding(
      padding: EdgeInsets.all(layout.gutter),
      // Centred and bounded: this screen is read, and a sentence running the
      // width of a tablet is one nobody finishes.
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: layout.readableWidth),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Text(
                        diagnosis?.sentence ??
                            unreadableSentence(record.closure),
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center,
                      ),
                      if (summary != null) ...[
                        const SizedBox(height: 28),
                        _AttemptSummaryView(summary),
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          progress.sentence,
                          style: theme.textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
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
                        _Measured(
                          record: record,
                          next: upcoming,
                          diagnosis: diagnosis,
                        ),
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AttemptSummaryView extends StatelessWidget {
  const _AttemptSummaryView(this.summary);

  final AttemptSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _QualityRow(label: 'Notes', value: summary.notes),
        const SizedBox(height: 12),
        _QualityRow(label: 'Flow', value: summary.flow),
        const SizedBox(height: 12),
        _QualityRow(label: 'Pulse', value: summary.pulse),
        if (summary.coordination case final coordination?) ...[
          const SizedBox(height: 12),
          _QualityRow(label: 'Coordination', value: coordination),
        ],
        const SizedBox(height: 12),
        _TempoRow(
          achieved: summary.achievedTempoBpm,
          target: summary.targetTempoBpm,
        ),
      ],
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounded = value.clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: '${(bounded * 100).round()} percent',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text(label, style: theme.textTheme.labelLarge),
            ),
            Expanded(
              child: SizedBox(
                height: 14,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 2,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      Align(
                        alignment: Alignment(bounded * 2 - 1, 0),
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TempoRow extends StatelessWidget {
  const _TempoRow({required this.achieved, required this.target});

  final double achieved;
  final double target;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final achievedText = _tempoText(achieved);
    final targetText = _tempoText(target);
    return Semantics(
      label: 'Tempo',
      value: '$achievedText BPM, target $targetText BPM',
      child: ExcludeSemantics(
        child: Row(
          children: [
            SizedBox(
              width: 96,
              child: Text('Tempo', style: theme.textTheme.labelLarge),
            ),
            Text('$achievedText BPM', style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              'target $targetText',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _tempoText(double bpm) => bpm == bpm.roundToDouble()
    ? bpm.round().toString()
    : bpm.toStringAsFixed(1);

/// The numbers behind the sentence above it.
///
/// Debug and profile only. The learner is told one true thing; this is for
/// whoever is deciding whether that thing was the right one to say, and for
/// watching values that now change what is learned. Achieved tempo especially:
/// it sets the difficulty execution evidence is attributed at, so a systematic
/// offset between the click and the transcript clock would show up here first.
class _Measured extends StatelessWidget {
  const _Measured({
    required this.record,
    required this.next,
    required this.diagnosis,
  });

  final AttemptRecord record;
  final PresentedAttempt? next;
  final AttemptDiagnosis? diagnosis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decision = next?.decision.decision;
    final rows = <(String, String)>[
      ('termination', record.closure.termination.id),
      if (diagnosis case final diagnosis?) ...[
        ('fault', diagnosis.fault?.name ?? 'none'),
        ('located', diagnosis.where?.name ?? 'nowhere'),
      ],
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
          // The one number a coordination fault is read from, and the one the
          // panel used to leave out: every other row could read 1.000 while
          // the diagnosis said the hands came apart.
          (
            'coordination',
            outcome.coordination?.toStringAsFixed(3) ?? 'one hand',
          ),
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
