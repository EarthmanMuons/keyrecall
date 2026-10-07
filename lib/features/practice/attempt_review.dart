import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import '../../motion.dart';
import '../input/input.dart';
import 'attempt_detail_trace.dart';
import 'attempt_details_sheet.dart';
import 'attempt_diagnosis.dart';
import 'attempt_evidence.dart';
import 'attempt_feedback.dart';
import 'attempt_summary_help.dart';
import 'exercise_presentation.dart';
import 'goal_progress.dart';
import 'presentation_exposure.dart';
import 'timing_shortfall.dart';
import 'goal_feedback.dart';

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
            ? 'The same ${materialNoun(next.material)} again, with more of '
                  'it shown.'
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
    // A probe is held back for a slot before it may be chosen, so the attempt
    // it verifies is no longer the one just finished. The copy says earlier
    // rather than just now, and stays true however many attempts intervene.
    ChallengeBypass.tempoProbe => switch (hands) {
      final hands? => 'Now $hands, at the speed you reached earlier.',
      null =>
        sameMaterial
            ? 'Same ${materialNoun(next.material)}, at the speed you reached '
                  'earlier.'
            : 'A quicker one, at a speed you have already reached.',
    },
    // The same exercise both times, so only the metronome is worth saying.
    // Said as a fact about the attempt rather than a verdict on the last one.
    ChallengeBypass.pulseSupport => 'The same one again, with the metronome.',
    ChallengeBypass.pulseWithdrawal =>
      'The same one again, without the metronome.',
    ChallengeBypass.acquisitionFloor => switch (hands) {
      final hands? => 'Starting with $hands and the notes in view.',
      null => 'Starting with the notes in view.',
    },
    // The ordinary question the supported work was preparing for. It says what
    // is being asked now rather than naming a scaffold or an earlier session:
    // the learner has been playing this at their own pace, and the tempo is
    // what comes back.
    //
    // Timing is the only axis V1 relaxes, so the parent's own tempo is the
    // whole of the difference. An acquisition task that changed portion or
    // advancement would need this derived from the task the way [differenceTo]
    // derives from a pair of exercises.
    ChallengeBypass.acquisitionProbe => switch (hands) {
      final hands? =>
        'Now $hands, at ${_tempoText(next.conditions.tempoBpm)} '
            'BPM.',
      null => restoredTempoLine(next),
    },
    ChallengeBypass.override ||
    null => differenceTo(next, previous) ?? (sameMaterial ? 'Again.' : null),
  };
}

/// What the Ready screen says about the metronome, or null where the
/// scheduler did not make it part of this attempt.
///
/// Said on the withdrawal too, since its absence is the point.
String? metronomeLine(ChallengeBypass? admittedBy) => switch (admittedBy) {
  ChallengeBypass.pulseSupport => 'This one uses the metronome.',
  ChallengeBypass.pulseWithdrawal => 'This one is without the metronome.',
  _ => null,
};

/// What an acquisition probe is asking for now, read off the probe itself.
///
/// Derived rather than handed forward, so it stays true however long after the
/// supported work the probe arrives.
String restoredTempoLine(Exercise probe) =>
    'Back at ${_tempoText(probe.conditions.tempoBpm)} BPM this time.';

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
      (HandMotion.contrary, ExerciseDirection.up) => 'Just apart this time.',
      (HandMotion.contrary, ExerciseDirection.upDown) =>
        'Apart and back together this time.',
      (_, ExerciseDirection.up) => 'Just up this time.',
      (_, ExerciseDirection.upDown) => 'Up and back down this time.',
    };
  }
  if (conditions.tempoBpm != was.tempoBpm) {
    return conditions.tempoBpm > was.tempoBpm
        ? 'A little quicker.'
        : 'A little slower.';
  }
  return null;
}

/// What comes next, as a transition screen can say it.
///
/// Presentation-neutral because what comes next is not always an exercise:
/// supported work is decided too, and a review that could only describe a
/// [PresentedAttempt] would have nothing to show when acquisition is next.
///
/// The material and one line of explanation, and no conditions. The Ready
/// screen immediately after states the hand, the direction, the span, and the
/// tempo. This is orientation: the material, and where there is one, the reason
/// the next thing is different.
@immutable
class NextPracticePreview {
  /// What comes next.
  final TechnicalMaterial material;

  /// Why it is different, where anything honest can be said.
  final String? explanation;

  /// Which way the scheduler moved the challenge to get here.
  final ChallengeDirection direction;

  const NextPracticePreview({
    required this.material,
    this.explanation,
    this.direction = ChallengeDirection.neutral,
  });
}

/// Which way a scheduler decision moved the challenge.
///
/// Advance is the one a review emphasizes, and only where something
/// demonstrated earned the harder version. A step the scheduler takes on a
/// timer, for lack of anything else, or as the second half of a remediation
/// cycle asks more of the learner without having been earned, so it is
/// neutral. Support is calm rather than marked down, because stepping back is
/// not a failure.
enum ChallengeDirection { advance, support, neutral }

ChallengeDirection challengeDirectionOf(ChallengeBypass? bypass) =>
    switch (bypass) {
      ChallengeBypass.executionProgression ||
      ChallengeBypass.guidanceProbe ||
      ChallengeBypass.tempoProbe ||
      ChallengeBypass.acquisitionProbe => ChallengeDirection.advance,
      ChallengeBypass.recovery ||
      ChallengeBypass.pulseSupport ||
      ChallengeBypass.acquisitionFloor => ChallengeDirection.support,
      ChallengeBypass.consolidation ||
      ChallengeBypass.bootstrapProbe ||
      ChallengeBypass.observationProbe ||
      ChallengeBypass.pulseWithdrawal ||
      ChallengeBypass.newMaterial ||
      ChallengeBypass.override ||
      null => ChallengeDirection.neutral,
    };

/// The parts of a review that arrive after the screen itself does.
enum ReviewPart { progress, continuation }

/// How long after the screen [part] starts to arrive.
///
/// Compact when there is no progress card, so an ordinary review is barely
/// slower than one with no entrance at all.
Duration reviewArrivalDelay(ReviewPart part, {required bool hasProgress}) =>
    switch (part) {
      ReviewPart.progress => const Duration(milliseconds: 160),
      ReviewPart.continuation =>
        hasProgress
            ? const Duration(milliseconds: 320)
            : const Duration(milliseconds: 100),
    };

/// How long after the screen [part] has finished arriving.
Duration reviewArrivalEnd(ReviewPart part, {required bool hasProgress}) =>
    reviewArrivalDelay(part, hasProgress: hasProgress) + attemptTransition;

/// A part of a review rising into place on its [reviewArrivalDelay], or simply
/// there under reduced motion.
///
/// The same widgets either way, so a change of preference never remounts what
/// is inside, and an exposure it already reported stays reported.
class ReviewArrival extends StatefulWidget {
  const ReviewArrival({
    required this.part,
    required this.hasProgress,
    required this.child,
    super.key,
  });

  final ReviewPart part;

  /// Whether the review has a progress card, which spaces the parts out.
  final bool hasProgress;

  final Widget child;

  @override
  State<ReviewArrival> createState() => _ReviewArrivalState();
}

class _ReviewArrivalState extends State<ReviewArrival>
    with SingleTickerProviderStateMixin {
  static const double _rise = 12;

  late final AnimationController _controller;

  /// How far in the part has come, from nothing to in place.
  late final Animation<double> _entrance;

  @override
  void initState() {
    super.initState();
    final delay = reviewArrivalDelay(
      widget.part,
      hasProgress: widget.hasProgress,
    );
    final total = reviewArrivalEnd(
      widget.part,
      hasProgress: widget.hasProgress,
    );
    _controller = AnimationController(vsync: this, duration: total)..forward();
    _entrance = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: attemptCurve,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entrance = Motion.of(context).reduced
        ? kAlwaysCompleteAnimation
        : _entrance;
    return FadeTransition(
      opacity: entrance,
      child: AnimatedBuilder(
        animation: entrance,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, _rise * (1 - entrance.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// What comes next, under the review's Continue button.
class NextExercise extends StatelessWidget {
  const NextExercise(this.upcoming, {super.key});

  final NextPracticePreview upcoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final advances = upcoming.direction == ChallengeDirection.advance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Next exercise',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          materialName(upcoming.material),
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        if (upcoming.explanation case final explanation?) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                if (advances)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.trending_up,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                TextSpan(text: explanation),
              ],
            ),
            style: advances
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

/// One part of a review, and what the feedback log calls it.
///
/// A review is reported a part at a time because it is a scrolling screen: the
/// whole of it is built whether or not any of it is reached, and one row for
/// all of it would record exposure to feedback nobody scrolled to.
@immutable
class ReviewExposure {
  /// What kind of performance feedback this part is.
  final PostAttemptFeedback feedback;

  /// The longitudinal claims this part makes, if it makes any.
  final List<ProgressEvent> progress;

  const ReviewExposure(this.feedback, {this.progress = const []});
}

/// What just happened, and what is next.
///
/// Shown between attempts, over a decision that has already been made: the
/// scheduler runs while this is being read, so continuing is instant rather
/// than being the moment the work starts. Nothing on this screen is waited on:
/// what arrives after the outcome does so while Continue already works.
class AttemptReview extends StatelessWidget {
  const AttemptReview({
    required this.record,
    required this.next,
    required this.onNext,
    required this.history,
    required this.instrument,
    this.continues = false,
    this.reading,
    this.timingShortfall,
    this.coverage,
    this.onExposed,
    super.key,
  });

  /// The attempt that just closed.
  final AttemptRecord record;

  /// What it was read from, when the closure came from a performance.
  final PerformanceReading? reading;

  /// Why the attempt carries no timing, where the capture could say.
  final TimingShortfall? timingShortfall;

  /// Records that one part of this review reached the learner, answering
  /// whether the session that owns the history took the report.
  final Future<bool> Function(ReviewExposure)? onExposed;

  /// What has been decided to come next, if anything.
  final NextPracticePreview? next;

  /// Attempts available when deriving longitudinal progress evidence.
  final Iterable<AttemptRecord> history;

  /// Goal targets this attempt covered, which take the place of what
  /// [history] would otherwise say.
  final CoverageProgress? coverage;

  /// Dismisses this and puts the next exercise on screen.
  final VoidCallback onNext;

  /// Whether anything follows this review.
  ///
  /// Separate from [next] because supported work is decided too, and a review
  /// that says Done while an acquisition task is waiting behind it names the
  /// wrong thing. The verb describes what tapping does; the preview describes
  /// what it can describe.
  final bool continues;

  /// Whether an instrument is attached, which is what an attempt nothing was
  /// played in is explained by.
  final InstrumentReadiness instrument;

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
    final evidence = switch (record.closure.measurement) {
      Measured(:final outcome) => AttemptEvidence.of(record.exercise, outcome),
      MeasurementUnavailable() => null,
    };
    final covering = coverage;
    final progressEvents =
        covering?.events ?? progressEventsFor(record, history: history);
    final progress = covering == null
        ? progressStatementFor(record, progressEvents)
        : coverageStatement(covering);

    final silence = nothingWasPlayed(record.closure)
        ? _Silence.of(instrument)
        : null;

    final layout = Layout.of(context);

    return Padding(
      padding: EdgeInsets.all(layout.gutter),
      // Centered and bounded: this screen is read, and a sentence running the
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
                      _Exposed(
                        // Diagnostic only where a fault is named. A line
                        // saying nothing arrived, or that nothing could be
                        // read, interprets no performance.
                        report: ReviewExposure(
                          diagnosis == null
                              ? PostAttemptFeedback.none
                              : PostAttemptFeedback.diagnostic,
                        ),
                        onExposed: onExposed,
                        attempt: record.identity.attemptId,
                        child: Text(
                          silence?.sentence ??
                              diagnosis?.sentence ??
                              unreadableSentence(record.closure),
                          style: theme.textTheme.headlineMedium,
                          textAlign: TextAlign.start,
                        ),
                      ),
                      if (silence != null) ...[
                        const SizedBox(height: 16),
                        _SilenceHelp(silence),
                      ],
                      if (summary != null) ...[
                        const SizedBox(height: 28),
                        _Exposed(
                          report: const ReviewExposure(
                            PostAttemptFeedback.summary,
                          ),
                          onExposed: onExposed,
                          attempt: record.identity.attemptId,
                          child: _AttemptSummaryView(
                            summary,
                            timingShortfall: timingShortfall,
                            onHelp: () => showAttemptSummaryHelp(
                              context,
                              includesCoordination:
                                  summary.coordination != null,
                              pulseSupplied: summary.pulseSupplied,
                            ),
                          ),
                        ),
                        if ((detailTrace, evidence) case (
                          final detailTrace?,
                          final evidence?,
                        )) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              // Awaited, so the sheet reports itself from its
                              // own route rather than the request to open one
                              // standing in for the frame it first drew.
                              onPressed: () => showAttemptDetails(
                                context,
                                exercise: record.exercise,
                                trace: detailTrace,
                                evidence: evidence,
                                achievedTempoBpm: summary.achievedTempoBpm,
                                onExposed: onExposed == null
                                    ? null
                                    : () => onExposed!(
                                        const ReviewExposure(
                                          PostAttemptFeedback
                                              .detailedDiagnostic,
                                        ),
                                      ),
                              ),
                              icon: const Icon(Icons.query_stats),
                              label: const Text('View details'),
                            ),
                          ),
                        ],
                      ],
                      if (progress != null) ...[
                        const SizedBox(height: 24),
                        ReviewArrival(
                          part: ReviewPart.progress,
                          hasProgress: true,
                          child: _Exposed(
                            report: ReviewExposure(
                              PostAttemptFeedback.none,
                              progress: progressEvents,
                            ),
                            onExposed: onExposed,
                            attempt: record.identity.attemptId,
                            child: _ProgressStatement(
                              progress,
                              heading: covering == null
                                  ? 'Progress'
                                  : coverageHeading(covering),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 40),
                      const Spacer(),
                      if (upcoming != null) ...[
                        ReviewArrival(
                          part: ReviewPart.continuation,
                          hasProgress: progress != null,
                          child: NextExercise(upcoming),
                        ),
                        const SizedBox(height: 32),
                      ],
                      SizedBox(
                        height: 88,
                        child: FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                            textStyle: theme.textTheme.headlineSmall,
                          ),
                          child: Text(
                            upcoming == null && !continues
                                ? 'Done'
                                : 'Continue',
                          ),
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

/// What to say about an attempt nothing was played in, and the way out of it.
///
/// The instrument is the likely reason for silence, so the screen names the
/// story it can support rather than leaving the learner to diagnose the app.
enum _Silence {
  /// Nothing is attached, which is the whole explanation.
  disconnected(
    sentence: 'No piano connected.',
    remedy: 'Connect your piano, then try the exercise again.',
    action: 'Connect',
  ),

  /// A piano is attached and none of its notes arrived.
  unheard(
    sentence: 'No notes came through.',
    remedy:
        'KeyRecall received nothing from your piano. Check that it’s still '
        'connected, then try again.',
    action: 'Check connection',
  );

  const _Silence({
    required this.sentence,
    required this.remedy,
    required this.action,
  });

  /// What happened, in place of the diagnosis.
  final String sentence;

  /// What to do about it.
  final String remedy;

  /// The button that does it.
  final String action;

  /// The story [instrument] supports, or null where none was wanted.
  static _Silence? of(InstrumentReadiness instrument) => switch (instrument) {
    InstrumentReadiness.notNeeded => null,
    InstrumentReadiness.disconnected => _Silence.disconnected,
    InstrumentReadiness.connected => _Silence.unheard,
  };
}

/// The remedy for silence, offered where the silence is reported.
/// One part of a review, reported when it is actually on screen.
///
/// Identified by the attempt and the kind of feedback, so scrolling back to a
/// part already reported does not report it twice, and the same part of the
/// next attempt's review is a new thing to report.
class _Exposed extends StatelessWidget {
  const _Exposed({
    required this.report,
    required this.onExposed,
    required this.attempt,
    required this.child,
  });

  final ReviewExposure report;
  final Future<bool> Function(ReviewExposure)? onExposed;
  final String attempt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final record = onExposed;
    if (record == null) return child;
    return ExposureGate(
      presentation: (attempt, report.feedback, report.progress.length),
      onExposed: () => record(report),
      child: child,
    );
  }
}

class _SilenceHelp extends StatelessWidget {
  const _SilenceHelp(this.silence);

  final _Silence silence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          silence.remedy,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: () => MidiDeviceSheet.show(context),
          icon: const Icon(Icons.piano),
          label: Text(silence.action),
        ),
      ],
    );
  }
}

/// A milestone, set apart from the commentary around it.
///
/// Progress events are rare, so this can afford to be noticed. The sentence
/// stays factual and the container carries the emphasis, which keeps a
/// measurement from reading as a reward.
class _ProgressStatement extends StatelessWidget {
  const _ProgressStatement(this.statement, {required this.heading});

  final String statement;
  final String heading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      label: '$heading. $statement',
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
                  _Sparkle(color: colors.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text(
                    heading.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.onPrimaryContainer,
                      letterSpacing: 1.1,
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

/// The progress mark, turning once into place as its card arrives.
class _Sparkle extends StatefulWidget {
  const _Sparkle({required this.color});

  final Color color;

  @override
  State<_Sparkle> createState() => _SparkleState();
}

class _SparkleState extends State<_Sparkle>
    with SingleTickerProviderStateMixin {
  static const Duration _turnLength = Duration(milliseconds: 720);

  late final AnimationController _controller;

  /// How far round the mark has turned, starting once its card is in place.
  late final Animation<double> _turn;

  @override
  void initState() {
    super.initState();
    final delay = reviewArrivalEnd(ReviewPart.progress, hasProgress: true);
    final total = delay + _turnLength;
    _controller = AnimationController(vsync: this, duration: total)..forward();
    _turn = CurvedAnimation(
      parent: _controller,
      curve: Interval(
        delay.inMicroseconds / total.inMicroseconds,
        1,
        curve: Curves.easeOutBack,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final turn = Motion.of(context).reduced ? kAlwaysCompleteAnimation : _turn;
    return RotationTransition(
      turns: Tween(begin: -0.5, end: 0.0).animate(turn),
      child: ScaleTransition(
        scale: Tween(begin: 0.4, end: 1.0).animate(turn),
        child: Icon(Icons.auto_awesome, size: 16, color: widget.color),
      ),
    );
  }
}

class _AttemptSummaryView extends StatelessWidget {
  const _AttemptSummaryView(
    this.summary, {
    required this.timingShortfall,
    required this.onHelp,
  });

  final AttemptSummary summary;
  final TimingShortfall? timingShortfall;
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
            if (summary.flow case final flow?) ...[
              const SizedBox(height: 12),
              _QualityRow(label: 'Flow', value: flow),
            ],
            if (summary.pulse case final pulse?) ...[
              const SizedBox(height: 12),
              _QualityRow(
                label: summary.pulseSupplied
                    ? 'Pulse, with metronome'
                    : 'Pulse',
                value: pulse,
              ),
            ],
            if (summary.coordination case final coordination?) ...[
              const SizedBox(height: 12),
              _QualityRow(label: 'Coordination', value: coordination),
            ],
            if (summary.achievedTempoBpm case final achieved?) ...[
              const SizedBox(height: 12),
              _TempoRow(achieved: achieved, target: summary.targetTempoBpm),
            ],
            if (!summary.hasTiming) ...[
              const SizedBox(height: 12),
              _TimingUnavailableRow(timingShortfall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Why the timing rows are not here.
///
/// Absent rows and rows that scored nothing look the same, and they are not
/// the same: the first is a limit of what this attempt could be observed to
/// do, and the second would be a judgment about the playing.
class _TimingUnavailableRow extends StatelessWidget {
  const _TimingUnavailableRow(this.shortfall);

  final TimingShortfall? shortfall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      '${timingShortfallSentence(shortfall)} '
      'Note accuracy and completion are still measured.',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
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
