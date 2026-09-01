import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import '../../layout.dart';
import '../../wordmark.dart';
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
import 'profile_avatar.dart';
import 'presentation_policy.dart';
import 'profiles_screen.dart';
import 'staff_cue.dart';
import 'task_help.dart';

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

  /// The attempt being played right now, if one is.
  ///
  /// The bar goes away for the length of it. Nothing on it is usable with both
  /// hands on the keys, and what it costs is the height the music and the
  /// keyboard are short of on a phone. It comes back by itself: an attempt
  /// that ends puts a different one on screen.
  String? _playing;

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

    final attemptId =
        loop.value?.presented?.decision.attemptId ??
        loop.value?.pending?.attemptId;
    if (_playing != attemptId) _playing = null;

    return Scaffold(
      appBar: _playing == null ? const _PracticeAppBar() : null,
      body: switch (loop) {
        AsyncData(:final value) when value.exercise != null => AttemptView(
          // A new decision restarts the view at Ready rather than inheriting
          // the previous attempt's phase.
          key: ValueKey(attemptId),
          exercise: value.exercise!,
          onFinish: (termination) => notifier.finish(termination: termination),
          onDecline: notifier.decline,
          onUnderWay: () => setState(() => _playing = attemptId),
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

/// The bar over every practice state: the app's name, the instrument, and a
/// menu holding everything else.
///
/// The instrument is the one control kept out of the menu, because connecting
/// one is the only setup this app has and it is what somebody reaches for when
/// notes are not arriving. Everything that is a setting goes behind the menu,
/// which is where the settings this app has yet to grow will go too.
class _PracticeAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const _PracticeAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(profileRosterProvider).value ?? const [];
    final active = roster.where((summary) => summary.isActive).toList();

    return AppBar(
      title: const Wordmark(),
      actions: [
        // Only when MIDI is the source: reading the connection state starts the
        // Bluetooth stack, which the synthetic instrument has no use for.
        if (ref.watch(inputSourceProvider) == InputSourceKind.midi)
          const _InstrumentButton(),
        _MenuButton(
          profile: active.isEmpty ? null : active.single.profile,
          // Who is practicing is worth saying on the bar only where it is in
          // question. On an install with one profile it is nobody's doubt, and
          // a coloured disc where the menu goes would be decoration.
          showsProfile: roster.length > 1,
        ),
      ],
    );
  }
}

/// Everything the practice screen offers that is not the instrument.
///
/// Wears the active profile's colour where more than one person practices
/// here, so a glance at the bar says whose history the next attempt lands in.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.profile, required this.showsProfile});

  final Profile? profile;
  final bool showsProfile;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    onSelected: (open) => open(),
    icon: showsProfile && profile != null
        ? ProfileAvatar(profile: profile!, radius: 15, icon: Icons.person)
        : null,
    itemBuilder: (context) => [
      PopupMenuItem(
        value: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (context) => const ProfilesScreen()),
        ),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: profile == null
              ? const Icon(Icons.people_outline)
              : ProfileAvatar(profile: profile!, radius: 16),
          title: Text(profile?.displayName ?? 'Profiles'),
        ),
      ),
      // A profile build is how this gets taken to a real instrument across the
      // room, and a release build is what a learner sees.
      if (!kReleaseMode)
        PopupMenuItem(
          value: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (context) => const DeveloperScreen(),
            ),
          ),
          child: const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.build_outlined),
            title: Text('Developer'),
          ),
        ),
    ],
  );
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
    this.onUnderWay,
    this.presentation,
    super.key,
  });

  /// What the scheduler decided to present.
  final Exercise exercise;

  /// Commits what was played and moves on, saying how the attempt ended.
  final Future<void> Function(AttemptTermination) onFinish;

  /// Records that the material could not be retrieved, and moves on.
  ///
  /// Absent where there is no loop to record it, which is the debug case list.
  final Future<void> Function()? onDecline;

  /// Says the attempt has started, for a screen that gives it the room the app
  /// bar was taking. Never says it stopped: this view is replaced wholesale
  /// when the attempt ends.
  final VoidCallback? onUnderWay;

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

  /// How often the attempt's clocks are read against its windows. Short enough
  /// that the shortest of them lands where it says it does.
  static const Duration _watchdogTick = Duration(milliseconds: 250);

  _Phase _phase = _Phase.ready;
  int _beatsLeft = _countInBeats;
  Timer? _countIn;
  Timer? _watchdog;
  bool _finishing = false;
  int _painted = 0;

  /// How long the attempt has been running, counted by the watchdog rather
  /// than read off a clock, so the windows advance with the timers a test
  /// drives.
  Duration _elapsed = Duration.zero;

  /// How long the current silence has run.
  ///
  /// Reset by a note arriving and by the learner saying they are still going,
  /// so it measures the gap rather than the attempt.
  Duration _quiet = Duration.zero;

  /// Whether the attempt has asked whether it is over.
  ///
  /// An offer, never a seizure: input is still recorded, the instrument still
  /// echoes, and a note arriving takes the question back down.
  bool _questioned = false;

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
    _watchdog?.cancel();
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
    widget.onUnderWay?.call();
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
          _watchdog = Timer.periodic(_watchdogTick, (_) => _watch());
        }
      });
    });
  }

  /// Reads the clocks against the attempt's windows.
  ///
  /// Nothing here looks at what was played, only at whether anything did and
  /// how long ago. A window passing either raises the question or closes an
  /// attempt nobody is answering; neither is a reading of the performance.
  void _watch() {
    if (!mounted || _finishing) return;
    _elapsed += _watchdogTick;
    _quiet += _watchdogTick;
    final windows = AttemptWindows.forExercise(widget.exercise);

    if (_elapsed >= windows.limit) {
      unawaited(_finish(AttemptTermination.durationLimit));
      return;
    }
    if (_quiet >= windows.abandon) {
      unawaited(_finish(AttemptTermination.inactivityTimeout));
      return;
    }

    final played = ref.read(attemptTranscriptProvider).isNotEmpty;
    final asks =
        _quiet >= (played ? windows.afterPlaying : windows.beforePlaying);
    if (asks != _questioned) setState(() => _questioned = asks);
  }

  /// Says the learner is still going, which puts the question back down.
  void _keepPlaying() => setState(() {
    _quiet = Duration.zero;
    _questioned = false;
  });

  Future<void> _decline() async {
    if (_finishing) return;
    _finishing = true;
    _watchdog?.cancel();
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    await widget.onDecline!();
  }

  Future<void> _finish(AttemptTermination termination) async {
    if (_finishing) return;
    _finishing = true;
    _watchdog?.cancel();
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    // What was played is the evidence. Nobody is asked how it went.
    await widget.onFinish(termination);
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
    final capture = ref.watch(attemptTranscriptProvider);
    final transcript = capture.transcript;

    if (capture.isInterrupted && !_finishing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_finish(AttemptTermination.inputInterrupted));
      });
    }

    if (transcript.isNotEmpty && transcript.length != _painted) {
      // The frame after the note is on screen is when it was actually seen.
      final sequence = transcript.notes.last.sequence;
      _painted = transcript.length;
      // Playing is the answer to the question, so it takes it back down. Set
      // rather than announced: this frame is already being built.
      _quiet = Duration.zero;
      _questioned = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(latencyProbeProvider.notifier).painted(sequence);
      });
    }

    if (_phase == _Phase.playing && _hasCoveredTraversal(transcript)) {
      // After the frame, so finishing does not run inside a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_finish(AttemptTermination.learnerStopped));
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

    final layout = Layout.of(context);
    final task = Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 16, layout.gutter, 0),
      child: _TaskStatement(exercise),
    );
    final notation = _Notation(
      gutter: layout.gutter,
      children: [
        if (showsCue && cueOnStaff(presentation.cueModality))
          StaffCue(
            exercise: exercise,
            showsFingering: presentation.motorCue == MotorCue.fingering,
          ),
        if (staffCarriesTranscript)
          TranscriptStaff(transcript: transcript, exercise: exercise),
      ],
    );
    final controls = Padding(
      padding: EdgeInsets.fromLTRB(layout.gutter, 0, layout.gutter, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Status(phase: _phase, guidance: guidance),
          const SizedBox(height: 12),
          _control(),
        ],
      ),
    );

    return Column(
      children: [
        // The task, the material, and what to do about it. Stacked while
        // there is height for it, and side by side when there is not: a
        // window on its side has no room to put a scale and a button under
        // each other, and one wide enough to would be leaving the width
        // empty.
        Expanded(
          child: SafeArea(
            top: false,
            bottom: staffCarriesTranscript,
            child: layout.hasRoomBeside
                ? Row(
                    // Stretched, so each pane is handed the full height to lay
                    // itself out in.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // The task takes what the control leaves and
                            // scrolls inside it: a window on its side can be
                            // shorter than the two of them together.
                            Expanded(child: SingleChildScrollView(child: task)),
                            controls,
                          ],
                        ),
                      ),
                      Expanded(flex: 2, child: notation),
                    ],
                  )
                : Column(
                    children: [
                      task,
                      Expanded(child: notation),
                      controls,
                    ],
                  ),
          ),
        ),
        // The instrument sits at the bottom edge, full width, the way a
        // keyboard does: it is where playing shows up, so it stays put while
        // everything above it changes. It runs past the safe area rather than
        // stopping short of it: it is a diagram, nothing on it is touched, and
        // the strip below it is height the music does not have.
        if (!staffCarriesTranscript)
          _Instrument(
            exercise: exercise,
            showsCue: showsCue && cueOnKeyboard(presentation.cueModality),
            echoes: echoes,
            showsFingering: presentation.motorCue == MotorCue.fingering,
            height: layout.instrumentHeight,
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
    // The same height the Ready button had, so the count replaces it rather
    // than moving everything around it.
    _Phase.countIn => SizedBox(
      height: 88,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_beatsLeft',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text('Counting in', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ),
    _Phase.playing =>
      _questioned
          ? _Question(
              played: ref.watch(attemptTranscriptProvider).isNotEmpty,
              onDone: () => _finish(AttemptTermination.learnerStopped),
              onKeepPlaying: _keepPlaying,
            )
          : Center(
              child: FilledButton.tonal(
                onPressed: () => _finish(AttemptTermination.learnerStopped),
                child: const Text('Done'),
              ),
            ),
    // Still Done, just no longer pressable. Swapping in a spinner for an
    // append and a scheduler decision makes a wait out of something that is
    // not one, and moves the screen while the learner is still looking at it.
    _Phase.finishing => const Center(
      child: FilledButton.tonal(onPressed: null, child: Text('Done')),
    ),
  };
}

/// The space the written music takes, whether or not there is any.
///
/// Centred while it fits and scrollable once it does not: an exercise runs from
/// nothing on screen to four systems of it, and a staff pinned to the top of a
/// tall phone reads as an afterthought at one octave.
class _Notation extends StatelessWidget {
  const _Notation({required this.gutter, required this.children});

  final double gutter;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - 32).clamp(0.0, double.infinity),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: children),
        ),
      ),
    ),
  );
}

/// The offer a passed window makes: is this over?
///
/// A question rather than an ending. The instrument is still live behind it
/// and a note takes it back down, so a learner who was thinking loses nothing
/// by ignoring it. What it says depends only on whether anything has arrived,
/// never on what arrived: silence after playing usually means the traversal is
/// over, and silence before it usually means nobody is at the keys.
class _Question extends StatelessWidget {
  const _Question({
    required this.played,
    required this.onDone,
    required this.onKeepPlaying,
  });

  final bool played;
  final VoidCallback onDone;
  final VoidCallback onKeepPlaying;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          played ? 'Finished?' : 'Still there?',
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: FilledButton(onPressed: onDone, child: const Text('Done')),
        ),
        TextButton(
          onPressed: onKeepPlaying,
          child: Text(played ? 'Keep playing' : 'Not yet'),
        ),
      ],
    );
  }
}

/// What was asked for. Visible at every rung, because it is the task rather
/// than a cue.
///
/// Ranked rather than listed. The scale is what the task *is*; the hand and
/// the shape of the traversal are how to play it; the tempo is a constraint on
/// it. Four equally weighted boxes would say those matter equally, and a
/// learner glancing up mid-position needs the identity first.
///
/// Tapping it explains it. The terms are the app's whole vocabulary, and the
/// place somebody wonders what one means is the line it is written on.
class _TaskStatement extends StatelessWidget {
  const _TaskStatement(this.exercise);

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conditions = exercise.conditions;

    return InkWell(
      onTap: () => showTaskHelp(context, exercise),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  materialName(exercise.material),
                  style: theme.textTheme.displaySmall,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.help_outline,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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
            '${octavesName(conditions.octaves)}',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${conditions.tempoBpm.round()} bpm',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
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
    required this.height,
  });

  final Exercise exercise;

  /// Whether the exercise's notes are marked.
  final bool showsCue;

  /// Whether played notes light up.
  final bool echoes;

  /// Whether the fingers are named on the marked keys.
  final bool showsFingering;

  /// How tall the diagram is drawn.
  final double height;

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
      height: height,
    );
  }
}

/// A line saying what is expected right now.
///
/// Sits with the control it qualifies rather than with the notation it
/// describes: what the notes do when the attempt starts is about the button
/// underneath it.
class _Status extends StatelessWidget {
  const _Status({required this.phase, required this.guidance});

  final _Phase phase;
  final GuidanceContext guidance;

  @override
  Widget build(BuildContext context) {
    if (phase != _Phase.ready) return const SizedBox(height: 20);

    return Text(
      switch (guidance.independence) {
        0 => 'The notes stay on screen while you play.',
        1 => 'Take a good look. The notes go away once you start.',
        _ => 'Play it from memory.',
      },
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: TextAlign.center,
    );
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
            'Nothing to practice right now.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'That should not happen, so it is worth reporting. Try again, or '
            'stop here and come back later.',
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
