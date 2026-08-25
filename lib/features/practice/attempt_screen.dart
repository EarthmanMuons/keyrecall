import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../audio/count_in_clicker.dart';
import '../input/input.dart';
import '../piano/piano.dart';
import 'attempt_transcript.dart';
import 'exercise_presentation.dart';
import 'practice_providers.dart';
import 'presentation_policy.dart';
import 'staff_cue.dart';

/// The first learner-facing practice screen: one exercise, presented.
///
/// The screen is the same at every rung. A task statement says what was asked
/// for, an instrument shows what the learner is playing, and guidance controls
/// only what information is placed on that instrument: withdrawal takes the
/// markers away, not the keyboard.
///
/// Tempo is a separate axis, which is why the count-in runs at every rung: it
/// establishes the requested pulse and carries no pitch information. See
/// `presentationFor`.
///
/// The seam this screen must not cross: it presents what an exercise asks for
/// and it echoes what arrived from the instrument, and it never compares them.
/// The markers are a set of pitches with no order, and the echo is the live
/// note state, so neither can say where in the scale the learner is.
class AttemptScreen extends ConsumerWidget {
  const AttemptScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loop = ref.watch(practiceLoopProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: switch (loop) {
        AsyncData(:final value) when value.exercise != null => AttemptView(
          // A new decision restarts the view at Ready rather than inheriting
          // the previous attempt's phase.
          key: ValueKey(
            value.presented?.decision.attemptId ?? value.pending?.attemptId,
          ),
          exercise: value.exercise!,
          onFinish: ref.read(practiceLoopProvider.notifier).finish,
        ),
        AsyncData() => const _NothingToPlay(),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Where the learner is within one attempt.
enum _Phase {
  /// Task stated, cue shown if the rung supplies one, nothing running. Ends
  /// when the learner says they are ready.
  ready,

  /// The pulse being counted in. At the previewed rung the cue is already
  /// gone: it is withdrawn at Ready, not at the first note, so studying it and
  /// performing from memory have a clean boundary.
  countIn,

  /// The attempt itself.
  playing,

  /// Over, and being committed.
  finishing,
}

/// One exercise, from Ready through the count-in to what happened.
///
/// Split from [AttemptScreen] so the guidance rungs can be driven directly:
/// the screen's job is wiring the loop, and this one's is everything the
/// learner sees and does.
class AttemptView extends ConsumerStatefulWidget {
  const AttemptView({
    required this.exercise,
    required this.onFinish,
    this.presentation,
    super.key,
  });

  /// What the scheduler decided to present.
  final Exercise exercise;

  /// Commits what was played and moves on.
  final Future<void> Function() onFinish;

  /// What to present it under, when something other than practice policy is
  /// choosing. Only the debug case list passes this, to compare one exercise
  /// in more than one modality.
  final PresentationConditions? presentation;

  @override
  ConsumerState<AttemptView> createState() => _AttemptViewState();
}

class _AttemptViewState extends ConsumerState<AttemptView> {
  /// Beats in the count-in. One bar of four, which also gives the learner time
  /// to get their hands from the screen to the keyboard.
  static const int _countInBeats = 4;

  _Phase _phase = _Phase.ready;
  int _beatsLeft = _countInBeats;
  Timer? _countIn;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    // Warmed up while the learner reads the screen, so neither the first beat
    // nor the first drawn note is waiting on something to load.
    unawaited(ref.read(countInClickerProvider).prepare());
    unawaited(warmStaffRendering());
  }

  @override
  void dispose() {
    _countIn?.cancel();
    super.dispose();
  }

  /// Whether enough notes have arrived for the attempt to be over.
  ///
  /// A count, not a verdict. The attempt ends when the learner has played as
  /// many notes as the exercise asks for, whatever those notes were; ending it
  /// because they were the *right* notes would be the app telling an unguided
  /// learner they got it, which is the loudest evaluative signal there is.
  bool _hasPlayedEnough(int played) =>
      played >= realize(widget.exercise).moments.length;

  void _start() {
    ref
        .read(attemptTranscriptProvider.notifier)
        .start(widget.exercise.material);
    final beat = Duration(
      microseconds:
          (60 *
                  Duration.microsecondsPerSecond /
                  widget.exercise.conditions.tempoBpm)
              .round(),
    );

    setState(() {
      _phase = _Phase.countIn;
      _beatsLeft = _countInBeats;
    });
    // The clicks are rendered as one buffer, so the pulse is exact whatever
    // this timer does; the number just follows it.
    ref
        .read(countInClickerProvider)
        .playCountIn(beats: _countInBeats, beat: beat);

    _countIn = Timer.periodic(beat, (timer) {
      if (!mounted) return;
      setState(() {
        _beatsLeft--;
        if (_beatsLeft <= 0) {
          timer.cancel();
          _phase = _Phase.playing;
        }
      });
    });
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    // What was played is the evidence. Nobody is asked how it went.
    await widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final guidance = exercise.guidance;
    final presentation = widget.presentation ?? presentationFor(guidance);

    final showsCue = switch (_phase) {
      _Phase.ready => presentation.pitchCue.suppliesMaterial,
      _ => showsPitchCueDuringAttempt(guidance),
    };
    final echoes = presentation.performanceFeedback != PerformanceFeedback.none;
    final played = ref.watch(attemptTranscriptProvider).length;

    if (_phase == _Phase.playing && _hasPlayedEnough(played)) {
      // After the frame, so finishing does not run inside a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_finish());
      });
    }

    // With nothing cued, the staff is free to carry what was played. With a
    // cue on it, it is not: echoing into a score that already shows the
    // answer means saying which expected note each observation was, which is
    // a judgment. There the keyboard carries the echo instead.
    final staffCarriesTranscript =
        echoes &&
        !showsCue &&
        (_phase == _Phase.playing || _phase == _Phase.finishing);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _TaskStatement(exercise),
              const SizedBox(height: 24),
              if (showsCue && cueOnStaff(presentation.cueModality)) ...[
                StaffCue(exercise: exercise),
                const SizedBox(height: 24),
              ],
              if (staffCarriesTranscript) ...[
                TranscriptStaff(
                  transcript: ref.watch(attemptTranscriptProvider),
                  exercise: exercise,
                ),
                const SizedBox(height: 24),
              ],
              _Status(
                phase: _phase,
                guidance: guidance,
                beatsLeft: _beatsLeft,
                played: played,
                expected: realize(exercise).moments.length,
              ),
              const SizedBox(height: 24),
              _control(),
            ],
          ),
        ),
        // The instrument sits at the bottom edge, full width, the way a
        // keyboard does: it is where playing shows up, so it stays put while
        // everything above it changes.
        if (!staffCarriesTranscript)
          _Instrument(
            exercise: exercise,
            showsCue: showsCue && cueOnKeyboard(presentation.cueModality),
            echoes: echoes,
          ),
      ],
    );
  }

  Widget _control() => switch (_phase) {
    _Phase.ready => Center(
      // Large on purpose: the learner is getting their hands back to the keys,
      // and should not have to aim.
      child: SizedBox(
        width: double.infinity,
        height: 88,
        child: FilledButton(
          onPressed: _start,
          style: FilledButton.styleFrom(
            textStyle: Theme.of(context).textTheme.headlineSmall,
          ),
          child: const Text('Ready'),
        ),
      ),
    ),
    _Phase.countIn => const SizedBox.shrink(),
    _Phase.playing => Center(
      child: FilledButton.tonal(onPressed: _finish, child: const Text('Done')),
    ),
    _Phase.finishing => const Center(child: CircularProgressIndicator()),
  };
}

/// What was asked for. Visible at every rung, because it is the task rather
/// than a cue.
///
/// The scale is the headline, and everything else is how to play it: four
/// facts, each labelled, so the learner can find the one they are unsure about
/// rather than reading a sentence to the end.
class _TaskStatement extends StatelessWidget {
  const _TaskStatement(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conditions = exercise.conditions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          materialName(exercise.material),
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 28,
          runSpacing: 12,
          children: [
            _Fact(label: 'Hands', value: handsName(conditions.hands)),
            _Fact(label: 'Range', value: octavesName(conditions.octaves)),
            _Fact(
              label: 'Direction',
              value: directionName(conditions.direction),
            ),
            _Fact(label: 'Tempo', value: '${conditions.tempoBpm.round()} bpm'),
          ],
        ),
      ],
    );
  }
}

/// One labelled fact about how to play the exercise.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 2),
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

/// The keyboard, present at every rung and in every phase.
///
/// Two channels that never mix. The marks say which notes the exercise asks
/// for and are what guidance withdraws; the lit keys say what the instrument
/// is sending and are the learner's own playing coming back to them. Neither
/// is derived from the other, and nothing here judges what arrives.
class _Instrument extends ConsumerWidget {
  const _Instrument({
    required this.exercise,
    required this.showsCue,
    required this.echoes,
  });

  final Exercise exercise;

  /// Whether the exercise's notes are marked.
  final bool showsCue;

  /// Whether played notes light up.
  final bool echoes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagram = KeyboardDiagram.forExercise(exercise);
    final sounding = echoes
        ? ref.watch(inputActivityProvider).soundingNoteNumbers
        : const <int>{};

    return PianoKeyboard(
      whiteKeyCount: diagram.whiteKeyCount,
      firstMidiNote: diagram.firstWhiteMidi,
      scaleNoteNumbers: showsCue ? diagram.memberNotes : const {},
      tonicPitchClass: showsCue ? diagram.tonicPitchClass : null,
      highlightedNoteNumbers: sounding,
      // No pitch-class filter: a wrong note lights up like any other. Marking
      // it as out of scale would be evaluative feedback, which no rung offers
      // yet and which changes what an attempt observes.
      height: 160,
    );
  }
}

/// A line under the instrument saying what is expected right now.
class _Status extends ConsumerWidget {
  const _Status({
    required this.phase,
    required this.guidance,
    required this.beatsLeft,
    required this.played,
    required this.expected,
  });

  final _Phase phase;
  final GuidanceContext guidance;
  final int beatsLeft;

  /// How many notes have arrived during this attempt.
  final int played;

  /// How many the exercise asks for.
  final int expected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (phase == _Phase.countIn) {
      return Column(
        children: [
          Text('$beatsLeft', style: theme.textTheme.displayLarge),
          Text('Counting in', style: theme.textTheme.bodyMedium),
        ],
      );
    }

    // A count of what arrived against what was asked for, so the attempt does
    // not end at a moment the learner cannot see coming. Both numbers are
    // already in the task statement, so neither discloses anything, and
    // nothing here says whether a note was right.
    if (phase == _Phase.playing) {
      return Text(
        '$played of $expected notes',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final text = switch (phase) {
      _Phase.ready => switch (guidance.independence) {
        0 => 'The notes stay up while you play.',
        1 => 'Study these, then start. They disappear when you do.',
        _ => 'Play it from memory.',
      },
      _ => '',
    };
    if (text.isEmpty) return const SizedBox(height: 20);

    return Text(text, style: theme.textTheme.bodyMedium);
  }
}

class _NothingToPlay extends ConsumerWidget {
  const _NothingToPlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Nothing to practice right now.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => ref.read(practiceLoopProvider.notifier).reopen(),
          child: const Text('Open another sitting'),
        ),
      ],
    ),
  );
}
