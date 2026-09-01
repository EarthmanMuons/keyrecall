import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../audio/pulse_clicker.dart';
import '../input/input.dart';
import '../piano/piano.dart';
import 'attempt_review.dart';
import 'attempt_transcript.dart';
import 'developer_screen.dart';
import 'exercise_presentation.dart';
import 'fingering.dart';
import 'latency_probe.dart';
import 'loop_failure.dart';
import 'practice_providers.dart';
import 'presentation_policy.dart';
import 'profiles_screen.dart';
import 'staff_cue.dart';

/// The app's home: one exercise, presented.
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
class AttemptScreen extends ConsumerStatefulWidget {
  const AttemptScreen({super.key});

  @override
  ConsumerState<AttemptScreen> createState() => _AttemptScreenState();
}

class _AttemptScreenState extends ConsumerState<AttemptScreen> {
  /// The attempt whose review has been read and dismissed.
  ///
  /// Held here rather than in the loop, because whether someone has finished
  /// looking at a screen is not something the practice history should carry.
  String? _reviewed;

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(practiceLoopProvider);
    final notifier = ref.read(practiceLoopProvider.notifier);

    // The attempt just finished takes the screen until it is dismissed, even
    // though the next exercise is already decided behind it. That is the point:
    // the decision happens while the review is being read, so Next never waits.
    final committed = loop.value?.lastCommitted;
    if (committed != null && committed.identity.attemptId != _reviewed) {
      return Scaffold(
        appBar: const _PracticeAppBar(),
        body: AttemptReview(
          record: committed,
          reading: loop.value?.lastReading,
          next: loop.value?.presented,
          onNext: () =>
              setState(() => _reviewed = committed.identity.attemptId),
        ),
      );
    }

    return Scaffold(
      appBar: const _PracticeAppBar(),
      body: switch (loop) {
        AsyncData(:final value) when value.exercise != null => AttemptView(
          // A new decision restarts the view at Ready rather than inheriting
          // the previous attempt's phase.
          key: ValueKey(
            value.presented?.decision.attemptId ?? value.pending?.attemptId,
          ),
          exercise: value.exercise!,
          onFinish: notifier.finish,
          onDecline: notifier.decline,
        ),
        AsyncData() => const _NothingToPlay(),
        AsyncError(:final error, :final stackTrace) => LoopFailure(
          error: error,
          stackTrace: stackTrace,
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// The bar over every practice state: who to practice as, what to practice
/// on, and, off release, the panel that shows the loop working.
///
/// The instrument is here rather than in a settings screen because connecting
/// one is the only setup this app has, and it is the thing somebody reaches
/// for when notes are not arriving.
class _PracticeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _PracticeAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) => AppBar(
    title: const Text('Practice'),
    actions: [
      // Only when MIDI is the source: reading the connection state starts the
      // Bluetooth stack, which the synthetic instrument has no use for.
      if (ref.watch(inputSourceProvider) == InputSourceKind.midi)
        const _InstrumentButton(),
      PopupMenuButton<_Destination>(
        onSelected: (destination) =>
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: destination.build)),
        itemBuilder: (context) => [
          for (final destination in _Destination.available)
            PopupMenuItem(
              value: destination,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(destination.icon),
                title: Text(destination.label),
              ),
            ),
        ],
      ),
    ],
  );
}

/// Where the practice screen's menu can go.
enum _Destination {
  profiles(Icons.people_outline, 'Profiles'),
  developer(Icons.build_outlined, 'Developer');

  const _Destination(this.icon, this.label);

  final IconData icon;
  final String label;

  /// The destinations this build offers. The developer panel is not one of
  /// them in release: a profile build is how this gets taken to a real
  /// instrument across the room, and a release build is what a learner sees.
  static List<_Destination> get available => [
    profiles,
    if (!kReleaseMode) developer,
  ];

  Widget build(BuildContext context) => switch (this) {
    _Destination.profiles => const ProfilesScreen(),
    _Destination.developer => const DeveloperScreen(),
  };
}

/// Whether an instrument is connected, and the way to connect one.
class _InstrumentButton extends ConsumerWidget {
  const _InstrumentButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(midiConnectionStateProvider);
    return IconButton(
      tooltip: connection.isConnected
          ? 'Connected to ${connection.deviceDisplayName ?? 'an instrument'}'
          : 'No instrument connected',
      onPressed: () => MidiDeviceSheet.show(context),
      icon: Icon(connection.isConnected ? Icons.piano : Icons.piano_off),
      color: connection.isConnected
          ? null
          : Theme.of(context).colorScheme.error,
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
    this.onDecline,
    this.presentation,
    super.key,
  });

  /// What the scheduler decided to present.
  final Exercise exercise;

  /// Commits what was played and moves on.
  final Future<void> Function() onFinish;

  /// Records that the material could not be retrieved, and moves on.
  ///
  /// Absent where there is no loop to record it, which is the debug case list.
  final Future<void> Function()? onDecline;

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
  int _painted = 0;

  /// Held rather than read on demand, because the pulse has to be silenced
  /// from [dispose], where reading a provider is no longer safe.
  late final PulseClicker _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = ref.read(pulseClickerProvider);
    // The previous attempt's notes are still in the transcript, because
    // closing an attempt reads them after recording stops. They are not this
    // attempt's, and this screen can be asked about them before it has
    // recorded anything of its own.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(attemptTranscriptProvider.notifier).discard();
    });
    // Warmed up while the learner reads the screen, so neither the first beat
    // nor the first drawn note is waiting on something to load.
    unawaited(_pulse.prepare());
    unawaited(warmStaffRendering());
  }

  @override
  void dispose() {
    _countIn?.cancel();
    // Leaving the screen ends the attempt, and a pulse that outlived it would
    // keep sounding over whatever comes next.
    unawaited(_pulse.stop());
    super.dispose();
  }

  /// Whether the attempt has reached the end of what was asked for.
  ///
  /// Progress, not a verdict: a wrong note covers its position as well as a
  /// right one does, so this cannot tell a learner they got it. Counting
  /// arrivals instead would end a corrected attempt one note early, since an
  /// extra note in the middle would pay for the last note of the scale.
  bool _hasCoveredTraversal(PerformanceTranscript transcript) =>
      hasCoveredTraversal(exercise: widget.exercise, transcript: transcript);

  void _start() {
    ref
        .read(attemptTranscriptProvider.notifier)
        .start(widget.exercise.material);
    final tempoSupport =
        (widget.presentation ??
                presentationFor(
                  widget.exercise.guidance,
                  exercise: widget.exercise,
                ))
            .tempoSupport;
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
    // this timer does, and the audio catches up to the count rather than the
    // count waiting on the audio.
    if (tempoSupport != TempoSupport.none) {
      unawaited(
        _pulse.play(
          countInBeats: _countInBeats,
          // A metronome outlasts the notes on purpose. Ending the pulse on
          // the last expected beat would stop it under anyone playing at
          // all slowly, which is exactly who is following it.
          continuingBeats: tempoSupport == TempoSupport.metronomeThroughout
              ? realize(widget.exercise).moments.length + _countInBeats
              : 0,
          beat: beat,
        ),
      );
    }

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

  Future<void> _decline() async {
    if (_finishing) return;
    _finishing = true;
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    await widget.onDecline!();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    // What was played is the evidence. Nobody is asked how it went.
    await widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.exercise;
    final guidance = exercise.guidance;
    final presentation =
        widget.presentation ?? presentationFor(guidance, exercise: exercise);

    final showsCue = switch (_phase) {
      _Phase.ready => presentation.pitchCue.suppliesMaterial,
      _ => showsPitchCueDuringAttempt(guidance),
    };
    final echoes = presentation.performanceFeedback != PerformanceFeedback.none;
    final transcript = ref.watch(attemptTranscriptProvider);

    if (transcript.isNotEmpty && transcript.length != _painted) {
      // The frame after the note is on screen is when it was actually seen.
      final sequence = transcript.notes.last.sequence;
      _painted = transcript.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(latencyProbeProvider.notifier).painted(sequence);
      });
    }

    if (_phase == _Phase.playing && _hasCoveredTraversal(transcript)) {
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
        // The task, then what to do about it, then the material. Notation
        // grows with the exercise, so anything under it can be pushed off a
        // phone: two octaves of a scale is four systems, and the control the
        // learner is looking for cannot be the thing that scrolls away.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TaskStatement(exercise),
              const SizedBox(height: 16),
              _Status(phase: _phase, guidance: guidance, beatsLeft: _beatsLeft),
              const SizedBox(height: 16),
              _control(),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            children: [
              if (showsCue && cueOnStaff(presentation.cueModality))
                StaffCue(
                  exercise: exercise,
                  showsFingering: presentation.motorCue == MotorCue.fingering,
                ),
              if (staffCarriesTranscript)
                TranscriptStaff(
                  transcript: ref.watch(attemptTranscriptProvider),
                  exercise: exercise,
                ),
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
            showsFingering: presentation.motorCue == MotorCue.fingering,
          ),
      ],
    );
  }

  Widget _control() => switch (_phase) {
    _Phase.ready => Column(
      children: [
        // Large on purpose: the learner is getting their hands back to the
        // keys, and should not have to aim.
        SizedBox(
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
        // Only where retrieval is what the attempt would test, and only before
        // anything is played: afterwards, what happened is a question for the
        // performance rather than for the learner. Quiet beside Ready, because
        // it is the answer to a question the rung asked, not an escape from
        // the exercise.
        if (widget.onDecline != null &&
            widget.exercise.guidance.isRetrievalObserved) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _decline,
            child: const Text("I don't remember"),
          ),
        ],
      ],
    ),
    _Phase.countIn => const SizedBox.shrink(),
    _Phase.playing => Center(
      child: FilledButton.tonal(onPressed: _finish, child: const Text('Done')),
    ),
    // Still Done, just no longer pressable. Swapping in a spinner for an
    // append and a scheduler decision makes a wait out of something that is
    // not one, and moves the screen while the learner is still looking at it.
    _Phase.finishing => const Center(
      child: FilledButton.tonal(onPressed: null, child: Text('Done')),
    ),
  };
}

/// What was asked for. Visible at every rung, because it is the task rather
/// than a cue.
///
/// Ranked rather than listed. The scale is what the task *is*; the hand and
/// the shape of the traversal are how to play it; the tempo is a constraint on
/// it. Four equally weighted boxes would say those matter equally, and a
/// learner glancing up mid-position needs the identity first.
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
        const SizedBox(height: 12),
        Text(
          handsName(conditions.hands).toUpperCase(),
          style: theme.textTheme.titleMedium?.copyWith(
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${directionName(conditions.direction)} · '
          '${octavesName(conditions.octaves)} · '
          '${startingNotesName(realize(exercise))}',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${conditions.tempoBpm.round()} bpm',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
    required this.showsFingering,
  });

  final Exercise exercise;

  /// Whether the exercise's notes are marked.
  final bool showsCue;

  /// Whether played notes light up.
  final bool echoes;

  /// Whether the fingers are named on the marked keys.
  final bool showsFingering;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagram = KeyboardDiagram.forExercise(exercise);
    final sounding = echoes
        ? ref.watch(inputActivityProvider).soundingNoteNumbers
        : const <int>{};

    // Fingering rides with the cue: it is execution support, and withdrawing
    // the notes while leaving the fingers would be telling a learner which
    // finger to use for a note they are trying to recall.
    //
    // One hand only. A key takes one digit, and hands together share keys
    // where their registers meet, so the diagram cannot say whose finger it
    // is. The staff can, and does.
    final realization = realize(exercise);
    final fingering =
        showsCue && showsFingering && realization.hands.length == 1
        ? fingeringByKeyFor(exercise, realization.hands.single)
        : const <int, int>{};

    return PianoKeyboard(
      whiteKeyCount: diagram.whiteKeyCount,
      firstMidiNote: diagram.firstWhiteMidi,
      scaleNoteNumbers: showsCue ? diagram.memberNotes : const {},
      tonicPitchClass: showsCue ? diagram.tonicPitchClass : null,
      highlightedNoteNumbers: sounding,
      decorations: [
        for (final entry in fingering.entries)
          PianoKeyDecoration(midiNote: entry.key, label: '${entry.value}'),
      ],
      // No pitch-class filter: a wrong note lights up like any other. Marking
      // it as out of scale would be evaluative feedback, which no rung offers
      // yet and which changes what an attempt observes.
      height: 160,
    );
  }
}

/// A line saying what is expected right now.
///
/// Sits with the control it qualifies rather than with the notation it
/// describes: "they disappear when you do" is about the button underneath it.
class _Status extends ConsumerWidget {
  const _Status({
    required this.phase,
    required this.guidance,
    required this.beatsLeft,
  });

  final _Phase phase;
  final GuidanceContext guidance;
  final int beatsLeft;

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

/// A slot that admitted nothing.
///
/// Not an ending. Sittings are unbounded and the scheduler has eight ways to
/// admit a candidate outside the ordinary band, so reaching this means every
/// one of them declined and the reason is worth knowing. It read as running
/// out of material once, while a hundred and fifty candidates were still
/// admissible and only the attempt cap had been hit.
class _NothingToPlay extends ConsumerWidget {
  const _NothingToPlay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The scheduler found nothing to offer.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'That should not happen. Stop whenever you like; this one is '
            'worth reporting.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => ref.read(practiceLoopProvider.notifier).reopen(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
