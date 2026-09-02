import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import 'attempt_detail_trace.dart';
import 'attempt_details_sheet.dart';
import 'attempt_diagnosis.dart';
import 'attempt_feedback.dart';
import 'attempt_summary_help.dart';
import 'exercise_presentation.dart';

/// Why the scheduler chose what it chose, when it can be said honestly.
///
/// Only the named exceptions are stated. Those are recorded on the decision
/// and mean exactly one thing each. An ordinary admission wins on a
/// lexicographic key against candidates the decision does not keep, so which
/// term decided it is not something this can know, and it falls back to
/// [differenceTo] rather than guessing.
///
/// A hand change is said whatever the reason was. The screen names the scale
/// and nothing else, so the same name under "Next exercise" is the same one as
/// far as anybody reading it can tell, and the scheduler counts a scale in one
/// hand as material it has never seen.
String? reasonForNext({
  required SchedulerDecision decision,
  required Exercise next,
  required Exercise previous,
}) {
  final sameMaterial = next.material == previous.material;
  final hands = next.conditions.hands == previous.conditions.hands
      ? null
      : switch (next.conditions.hands) {
          HandConfiguration.together => 'both hands',
          HandConfiguration.right => 'the right hand',
          HandConfiguration.left => 'the left hand',
        };

  return switch (decision.challengeBypass) {
    ChallengeBypass.recovery => switch (hands) {
      final hands? => 'Now $hands, with more of it shown.',
      null =>
        sameMaterial
            ? 'The same scale again, with more of it shown.'
            : 'Going back a step.',
    },
    ChallengeBypass.newMaterial => switch (hands) {
      final hands? => 'New with $hands, so it comes with the notes.',
      null => 'New here, so it comes with the notes.',
    },
    ChallengeBypass.consolidation => switch (hands) {
      final hands? => 'Now $hands, from memory.',
      null =>
        sameMaterial
            ? 'That one again, this time from memory.'
            : 'One you have met, this time from memory.',
    },
    ChallengeBypass.executionProgression => switch (hands) {
      final hands? => 'Now $hands, a step further.',
      null =>
        sameMaterial
            ? 'The same one, a step further.'
            : 'One you know, a step further.',
    },
    ChallengeBypass.guidanceProbe ||
    ChallengeBypass.bootstrapProbe ||
    ChallengeBypass.observationProbe => switch (hands) {
      final hands? => 'Now $hands, with less help.',
      null => 'Time to try this one with less help.',
    },
    ChallengeBypass.tempoProbe => switch (hands) {
      final hands? => 'Now $hands, at the speed you played it.',
      null =>
        sameMaterial
            ? 'That looked easy. Same scale, at the speed you played it.'
            : 'That looked easy, so this one is quicker.',
    },
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
  if (conditions.handMotion != was.handMotion) {
    return conditions.handMotion == HandMotion.contrary
        ? 'Hands moving apart this time, then back together.'
        : 'Both hands the same way this time.';
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
    return switch ((conditions.handMotion, conditions.direction)) {
      (HandMotion.contrary, ScaleDirection.up) => 'Just apart this time.',
      (HandMotion.contrary, ScaleDirection.upDown) =>
        'Apart and back together this time.',
      (_, ScaleDirection.up) => 'Just up this time.',
      (_, ScaleDirection.upDown) => 'Up and back down this time.',
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
/// scheduler runs while this is being read, so continuing is instant rather
/// than being the moment the work starts. Nothing on this screen is waited on
/// and nothing animates in.
class AttemptReview extends StatelessWidget {
  const AttemptReview({
    required this.record,
    required this.next,
    required this.onNext,
    required this.history,
    this.reading,
    this.onDetailsViewed,
    super.key,
  });

  /// The attempt that just closed.
  final AttemptRecord record;

  /// What it was read from, when the closure came from a performance.
  final PerformanceReading? reading;

  final VoidCallback? onDetailsViewed;

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
    final detailTrace = reading == null
        ? null
        : attemptDetailTraceFor(reading!);
    final progressEvents = progressEventsFor(record, history: history);
    final progress = progressStatementFor(record, progressEvents);
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
                  // What happened reads from the top left as feedback; what
                  // comes next is anchored to the button, so the transition
                  // sits in the same place however long the feedback runs.
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        diagnosis?.sentence ??
                            unreadableSentence(record.closure),
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.start,
                      ),
                      if (summary != null) ...[
                        const SizedBox(height: 28),
                        _AttemptSummaryView(
                          summary,
                          onHelp: () => showAttemptSummaryHelp(
                            context,
                            includesCoordination: summary.coordination != null,
                          ),
                        ),
                        if (detailTrace != null) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                final details = showAttemptDetails(
                                  context,
                                  exercise: record.exercise,
                                  trace: detailTrace,
                                  achievedTempoBpm: summary.achievedTempoBpm,
                                );
                                onDetailsViewed?.call();
                                await details;
                              },
                              icon: const Icon(Icons.query_stats),
                              label: const Text('View details'),
                            ),
                          ),
                        ],
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 24),
                        _ProgressStatement(progress),
                      ],
                      const SizedBox(height: 40),
                      const Spacer(),
                      if (upcoming != null) ...[
                        Text(
                          'Next exercise',
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
                        const SizedBox(height: 32),
                      ],
                      SizedBox(
                        height: 88,
                        child: FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                            textStyle: theme.textTheme.headlineSmall,
                          ),
                          child: Text(upcoming == null ? 'Done' : 'Continue'),
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

/// A milestone, set apart from the commentary around it.
///
/// Progress events are rare, so this can afford to be noticed. The sentence
/// stays factual and the container carries the emphasis, which keeps a
/// measurement from reading as a reward.
class _ProgressStatement extends StatelessWidget {
  const _ProgressStatement(this.statement);

  final String statement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: 'Progress. $statement',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: colors.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Progress',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                statement,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttemptSummaryView extends StatelessWidget {
  const _AttemptSummaryView(this.summary, {required this.onHelp});

  final AttemptSummary summary;
  final VoidCallback onHelp;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Explain attempt measurements',
      onTap: onHelp,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: onHelp,
        child: Column(
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
        ),
      ),
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
            Text.rich(
              TextSpan(
                style: theme.textTheme.bodyMedium,
                children: [
                  TextSpan(text: '$achievedText BPM'),
                  TextSpan(
                    text: ' · target $targetText',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _tempoText(double bpm) => bpm.round().toString();
