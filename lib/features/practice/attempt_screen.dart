import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../input/input.dart';
import '../piano/piano.dart';
import 'exercise_presentation.dart';
import 'practice_providers.dart';
import 'presentation_policy.dart';
import 'reported_result.dart';

/// The first learner-facing practice screen: one exercise, presented.
///
/// Two layers, and only one of them guidance controls. The *task statement*
/// (what scale, which hand, how far, which way, how fast) is what was asked
/// for and is visible at every rung. The *pitch surface* is what tells the
/// learner which notes, and is the only thing [GuidanceContext] governs. So
/// fading guidance removes exactly one panel and changes nothing else.
///
/// Tempo is a separate axis, which is why the count-in runs at every rung: it
/// establishes the requested pulse and carries no pitch information. See
/// `presentationFor`.
///
/// The seam this screen must not cross: it presents an [Exercise] and it shows
/// live input, and it never compares them. Nothing here knows where in the
/// scale the learner is, and the pitch surface is a set of member notes with
/// no order, so a follow-along cue is not expressible without new API.
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
          onReport: ref.read(practiceLoopProvider.notifier).report,
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
  /// Task stated, pitch surface shown if the rung supplies one, nothing
  /// running. Ends when the learner says they are ready.
  ready,

  /// The pulse being counted in. The pitch surface is already gone at the
  /// previewed rung: it is withdrawn at Ready, not at the first note, so
  /// studying the cue and performing from memory have a clean boundary.
  countIn,

  /// The attempt itself.
  playing,

  /// Over, waiting to hear how it went.
  reporting,
}

/// One exercise, from Ready through the count-in to what happened.
///
/// Split from [AttemptScreen] so the guidance rungs can be driven directly:
/// the screen's job is wiring the loop, and this one's is everything the
/// learner sees and does.
class AttemptView extends ConsumerStatefulWidget {
  const AttemptView({
    required this.exercise,
    required this.onReport,
    super.key,
  });

  /// What the scheduler decided to present.
  final Exercise exercise;

  /// Where the stand-in for measurement goes.
  final Future<void> Function(ReportedResult) onReport;

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

  @override
  void dispose() {
    _countIn?.cancel();
    super.dispose();
  }

  void _start() {
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

  void _finish() => setState(() => _phase = _Phase.reporting);

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final guidance = exercise.guidance;
    final presentation = presentationFor(guidance);

    final showsSurface = switch (_phase) {
      _Phase.ready => presentation.pitchRepresentation.suppliesPitchMaterial,
      _ => showsPitchDuringAttempt(guidance),
    };

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _TaskStatement(exercise),
        const SizedBox(height: 24),
        if (showsSurface)
          _PitchSurfaceView(
            exercise: exercise,
            showsLiveKeys:
                _phase == _Phase.playing &&
                showsLiveKeysDuringAttempt(guidance),
          )
        else
          _SurfaceAbsent(phase: _phase, guidance: guidance),
        const SizedBox(height: 24),
        switch (_phase) {
          _Phase.ready => _ReadyControl(guidance: guidance, onReady: _start),
          _Phase.countIn => _CountIn(beatsLeft: _beatsLeft),
          _Phase.playing => _PlayingControl(onFinish: _finish),
          _Phase.reporting => _ReportControl(onReport: widget.onReport),
        },
      ],
    );
  }
}

/// What was asked for. Visible at every rung, because it is the task rather
/// than a cue.
class _TaskStatement extends StatelessWidget {
  const _TaskStatement(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          materialName(exercise.material),
          style: theme.textTheme.displaySmall,
        ),
        const SizedBox(height: 8),
        Text(
          conditionsLine(exercise.conditions),
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The pitch material, drawn as marked keys.
class _PitchSurfaceView extends ConsumerWidget {
  const _PitchSurfaceView({
    required this.exercise,
    required this.showsLiveKeys,
  });

  final Exercise exercise;

  /// Whether played notes light up. Only true at the continuously cued rung.
  final bool showsLiveKeys;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagram = KeyboardDiagram.forExercise(exercise);
    // Watched only when it is allowed to be seen, so a rung that hides live
    // keys is not one wiring mistake away from showing them.
    final sounding = showsLiveKeys
        ? ref.watch(inputActivityProvider).soundingNoteNumbers
        : const <int>{};

    return PianoKeyboard(
      whiteKeyCount: diagram.whiteKeyCount,
      firstMidiNote: diagram.firstWhiteMidi,
      scaleNoteNumbers: diagram.memberNotes,
      tonicPitchClass: diagram.tonicPitchClass,
      highlightedNoteNumbers: sounding,
      // No pitch-class filter: a wrong note lights up like any other. Marking
      // it as out of scale would be correctness feedback, which is a different
      // thing from a cue and is not what this rung offers.
      height: 160,
    );
  }
}

/// What stands where the pitch surface would be when there is none.
///
/// Never a hint about the notes. Before the attempt it says what this rung is;
/// during it, it shows that the app is listening, using nothing pitch-bearing:
/// showing the notes that just arrived would put a cue back on screen through
/// the input side.
class _SurfaceAbsent extends ConsumerWidget {
  const _SurfaceAbsent({required this.phase, required this.guidance});

  final _Phase phase;
  final GuidanceContext guidance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = switch (phase) {
      _Phase.playing => 'Listening',
      // Only reachable at the previewed rung, where the surface was on screen
      // a moment ago and has now been withdrawn for good.
      _ when guidance.isMaterialSupplied => 'The notes are hidden now.',
      _ => 'Nothing shown for this one.',
    };
    final activity = ref.watch(inputActivityProvider);

    return Container(
      height: 160,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(text, style: theme.textTheme.titleMedium),
          if (phase == _Phase.playing) ...[
            const SizedBox(height: 12),
            // A count, not a transcript: it shows the stream is alive without
            // naming a single pitch.
            Text(
              '${activity.eventCount} events',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReadyControl extends StatelessWidget {
  const _ReadyControl({required this.guidance, required this.onReady});

  final GuidanceContext guidance;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    // Ready means different things per rung and should say so, since at the
    // previewed rung it is also the moment the notes disappear.
    final caption = switch (guidance.independence) {
      0 => 'The notes stay up while you play.',
      1 => 'Study these, then start. They disappear when you do.',
      _ => 'Play it from memory.',
    };
    return Column(
      children: [
        Text(caption, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 12),
        FilledButton(onPressed: onReady, child: const Text('Ready')),
      ],
    );
  }
}

class _CountIn extends StatelessWidget {
  const _CountIn({required this.beatsLeft});

  final int beatsLeft;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('$beatsLeft', style: Theme.of(context).textTheme.displayLarge),
      const SizedBox(height: 8),
      // Silent for now: nothing in the app makes sound yet, so the count-in
      // shows the pulse rather than sounding it. Audible clicks are the same
      // decision, better delivered.
      Text('Counting in', style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _PlayingControl extends StatelessWidget {
  const _PlayingControl({required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) => Center(
    child: FilledButton.tonal(onPressed: onFinish, child: const Text('Done')),
  );
}

/// Still the mocked boundary, in a learner's words.
///
/// Measurement does not exist yet, so a person says what happened. These
/// buttons are a stand-in for that, not a scoring design.
class _ReportControl extends StatelessWidget {
  const _ReportControl({required this.onReport});

  final Future<void> Function(ReportedResult) onReport;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('How did that go?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          for (final result in ReportedResult.values)
            FilledButton.tonal(
              onPressed: () => onReport(result),
              child: Text(result.label),
            ),
        ],
      ),
    ],
  );
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
