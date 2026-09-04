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
import 'attempt_feedback.dart';
import 'attempt_review.dart';
import 'attempt_transcript.dart';
import 'developer_screen.dart';
import 'exercise_presentation.dart';
import 'fingering.dart';
import 'focus_bar.dart';
import 'hands_icon.dart';
import 'latency_probe.dart';
import 'loop_failure.dart';
import 'practice_plan_screen.dart';
import 'practice_providers.dart';
import 'presentation_policy.dart';
import 'profile_avatar.dart';
import 'scheduler_benchmark.dart';
import 'profiles_screen.dart';
import 'screen_wake_lock.dart';
import 'staff_cue.dart';
import 'task_help.dart';

/// How long the screen takes to hand the task over to the bar, and how it
/// moves while it does.
///
/// One duration and one curve for every part of it. The statement leaving the
/// screen, the bar's controls giving up their width, and the task arriving in
/// their place are one movement, and they only read as one if they are timed
/// as one.
const Duration attemptTransition = Duration(milliseconds: 280);
const Curve attemptCurve = Curves.easeInOutCubic;

/// The pause between pressing Ready and the first counted beat.
///
/// The transition, and a moment on the other side of it. The count-in is the
/// cue to start playing, and sounding it while the screen is still moving asks
/// somebody to read a new layout and catch a beat at the same time.
const Duration attemptSettle = Duration(milliseconds: 400);

/// The space under the last thing on the practice screen.
const double _bottomInset = 16;

/// How much taller a text button is than the text in it.
///
/// Material gives one a touch target whatever its text measures, and half of
/// what that adds sits under the words as space nobody asked for.
const double _touchTargetSlack = 14;

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

  final Set<String> _feedbackRecorded = {};
  final Set<String> _detailsRecorded = {};

  /// The attempt being played right now, if one is.
  ///
  /// The bar keeps its place and changes what it holds: nothing on it is
  /// usable with both hands on the keys, so for the length of the attempt it
  /// carries the task instead, and the screen below it is only what is being
  /// played. It comes back by itself: an attempt that ends puts a different
  /// one on screen.
  String? _playing;

  @override
  Widget build(BuildContext context) {
    final loop = ref.watch(practiceLoopProvider);
    final notifier = ref.read(practiceLoopProvider.notifier);

    // The attempt just finished takes the screen until it is dismissed, even
    // though the next exercise is already decided behind it. That is the point:
    // the decision happens while the review is being read, so Continue never
    // waits.
    final committed = loop.value?.lastCommitted;
    if (committed != null && committed.identity.attemptId != _reviewed) {
      final history = loop.value!.session.journal.records;
      final progress = progressEventsFor(committed, history: history);
      if (!_feedbackRecorded.contains(committed.identity.attemptId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted ||
              _feedbackRecorded.contains(committed.identity.attemptId)) {
            return;
          }
          _feedbackRecorded.add(committed.identity.attemptId);
          try {
            await notifier.recordFeedbackExposure(
              record: committed,
              progress: progress,
            );
          } catch (_) {
            _feedbackRecorded.remove(committed.identity.attemptId);
          }
        });
      }
      return Scaffold(
        // The review is still about the attempt that just ran, so the bar
        // keeps holding it. Continue hands the screen back, and the bar comes
        // back with it.
        appBar: _PracticeAppBar(
          running: _playing == null ? null : committed.exercise,
        ),
        body: AttemptReview(
          record: committed,
          history: history,
          instrument: ref.watch(instrumentReadinessProvider),
          reading: loop.value?.lastReading,
          next: loop.value?.presented,
          onDetailsViewed: () {
            final attemptId = committed.identity.attemptId;
            if (!_detailsRecorded.add(attemptId)) return;
            unawaited(
              notifier.recordAttemptDetailsViewed(committed).catchError((_) {
                _detailsRecorded.remove(attemptId);
              }),
            );
          },
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
      appBar: _PracticeAppBar(
        running: _playing == null ? null : loop.value?.exercise,
      ),
      // The strip goes over whatever the loop produced, and only while nothing
      // is being played: what it says is about the next exercise, and during
      // one it would be a control nobody can reach.
      body: switch (loop) {
        AsyncData(:final value) when value.exercise != null => Column(
          children: [
            if (_playing == null) const FocusBar(),
            Expanded(
              child: AttemptView(
                // A new decision restarts the view at Ready rather than
                // inheriting the previous attempt's phase.
                key: ValueKey(attemptId),
                exercise: value.exercise!,
                onFinish: (termination) =>
                    notifier.finish(termination: termination),
                onDecline: notifier.decline,
                onUnderWay: () => setState(() => _playing = attemptId),
                onBackToReady: () => setState(() => _playing = null),
              ),
            ),
          ],
        ),
        AsyncData(:final value) => Column(
          children: [
            const FocusBar(),
            Expanded(child: _NothingToPlay(state: value)),
          ],
        ),
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
  const _PracticeAppBar({this.running});

  /// The attempt under way, whose task the bar carries instead of the app's
  /// name and its controls.
  final Exercise? running;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roster = ref.watch(profileRosterProvider).value ?? const [];
    final active = roster.where((summary) => summary.isActive).toList();
    final task = running;

    return AppBar(
      // Both of them sit where a name sits, against the leading edge.
      centerTitle: false,
      title: AnimatedSwitcher(
        duration: attemptTransition,
        // The name and the controls are gone before the task arrives, so
        // nothing is read through anything else: what animates is the task
        // rising into the room they left.
        //
        // The outgoing child's animation counts down from one, so the interval
        // that clears it early sits at the top of the range and the one that
        // holds the arriving child back sits in the middle. They do not
        // overlap: out by a fifth of the way through, in from a third.
        switchOutCurve: const Interval(0.8, 1),
        switchInCurve: const Interval(0.35, 1, curve: Curves.easeOutCubic),
        // Against the leading edge while both are in the tree. The default
        // centers them, which lands the arriving one in the middle of the bar
        // and slides it left once the other is gone.
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.6),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: task == null
            ? const Wordmark(key: ValueKey('wordmark'))
            : _RunningTask(task, key: const ValueKey('task')),
      ),
      actions: [
        // Gone at once rather than animated out. They are what the task is
        // replacing, and a control sliding around underneath it reads as two
        // things happening instead of one.
        if (task == null)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: attemptTransition,
            curve: const Interval(0.35, 1),
            builder: (context, arrival, child) =>
                Opacity(opacity: arrival, child: child),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Only when MIDI is the source: reading the connection
                // state starts the Bluetooth stack, which the synthetic
                // instrument has no use for.
                if (ref.watch(inputSourceProvider) == InputSourceKind.midi)
                  const _InstrumentButton(),
                _MenuButton(
                  profile: active.isEmpty ? null : active.single.profile,
                  // Who is practicing is worth saying on the bar only where it
                  // is in question. On an install with one profile it is
                  // nobody's doubt, and a colored disc where the menu goes
                  // would be decoration.
                  showsProfile: roster.length > 1,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The task as the bar carries it while it is being played.
///
/// The statement's own words, in the room a bar has: the scale keeps its name,
/// the hand becomes its mark, and the rest runs on one line under it. A
/// learner glancing up mid-scale is checking what they were asked for, which
/// is the same question the statement answers with the whole screen.
class _RunningTask extends StatelessWidget {
  const _RunningTask(this.exercise, {super.key});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final conditions = exercise.conditions;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HandsIcon(conditions.hands, size: 20),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                materialName(exercise.material),
                style: theme.textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${traversalName(conditions)} · '
                '${octavesName(conditions.octaves)} · '
                '${conditions.tempoBpm.round()} bpm',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Everything the practice screen offers that is not the instrument.
///
/// Wears the active profile's color where more than one person practices
/// here, so a glance at the bar says whose history the next attempt lands in.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.profile, required this.showsProfile});

  final Profile? profile;
  final bool showsProfile;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    onSelected: (open) => open(),
    icon: showsProfile && profile != null
        ? ProfileAvatar(profile: profile!, radius: 15)
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
      PopupMenuItem(
        value: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const PracticePlanScreen(),
          ),
        ),
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.flag_outlined),
          title: Text('Goals & focus'),
        ),
      ),
      // Temporary, and deliberately not behind the build-mode check the
      // developer screen is: what it measures is release-build scheduling cost
      // on real hardware, which is the one thing a profile build cannot say.
      PopupMenuItem(
        value: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const SchedulerBenchmarkScreen(),
          ),
        ),
        child: const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.speed),
          title: Text('Scheduler benchmark'),
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

  /// The count-in has been interrupted before the observation begins.
  paused,

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
    this.onBackToReady,
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

  /// Says the presentation has started, for a screen that gives it the room
  /// the app bar was taking.
  final VoidCallback? onUnderWay;

  /// Says the presentation returned to Ready before the attempt began.
  final VoidCallback? onBackToReady;

  /// What to present it under, when something other than practice policy is
  /// choosing. Only the debug case list passes this, to compare one exercise
  /// in more than one modality.
  final PresentationConditions? presentation;

  @override
  ConsumerState<AttemptView> createState() => _AttemptViewState();
}

class _AttemptViewState extends ConsumerState<AttemptView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// Beats in the count-in. One bar of four, which also gives the learner time
  /// to get their hands from the screen to the keyboard.
  static const int _countInBeats = 4;

  /// How often the attempt's clocks are read against its windows. Short enough
  /// that the shortest of them lands where it says it does.
  static const Duration _watchdogTick = Duration(milliseconds: 250);

  /// Where the instrument sits, from `0` in place to `1` off the bottom.
  ///
  /// It arrives by running back to nought, so a new exercise slides the
  /// keyboard up into the room the last attempt took it out of, and Ready
  /// sends it down the way it came.
  late final AnimationController _handover;

  _Phase _phase = _Phase.ready;
  int _beatsLeft = _countInBeats;
  Timer? _settling;
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
  late final ScreenWakeLock _screenWakeLock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _handover = AnimationController(
      vsync: this,
      duration: attemptTransition,
      value: 1,
    )..reverse();
    _pulse = ref.read(pulseClickerProvider);
    _screenWakeLock = ref.read(screenWakeLockProvider);
    _screenWakeLock.setEnabled(true).ignore();
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
    WidgetsBinding.instance.removeObserver(this);
    _screenWakeLock.setEnabled(false).ignore();
    _handover.dispose();
    _settling?.cancel();
    _countIn?.cancel();
    _watchdog?.cancel();
    // Leaving the screen ends the attempt, and a pulse that outlived it would
    // keep sounding over whatever comes next.
    unawaited(_pulse.stop());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _screenWakeLock.setEnabled(true).ignore();
    }
  }

  /// Whether the attempt has reached the end of what was asked for.
  ///
  /// Progress, not a verdict: a wrong note covers its position as well as a
  /// right one does, so this cannot tell a learner they got it. Counting
  /// arrivals instead would end a corrected attempt one note early, since an
  /// extra note in the middle would pay for the last note of the scale.
  bool _hasCoveredTraversal(PerformanceTranscript transcript) =>
      hasCoveredTraversal(exercise: widget.exercise, transcript: transcript);

  /// Whether the way out of an exercise nobody can retrieve is on screen.
  bool get _showsDecline =>
      _phase == _Phase.ready &&
      widget.onDecline != null &&
      widget.exercise.guidance.isRetrievalObserved;

  /// Whether the instrument has nothing left to carry once the attempt starts.
  ///
  /// The same reading the build makes of what each surface is for: with the
  /// cue withdrawn and the echo going to the staff, the diagram is a picture
  /// of an instrument nobody is being told anything about.
  bool get _instrumentLeavesAtReady {
    final presentation =
        widget.presentation ??
        presentationFor(widget.exercise.guidance, exercise: widget.exercise);
    return presentation.performanceFeedback != PerformanceFeedback.none &&
        !showsPitchCueDuringAttempt(widget.exercise.guidance);
  }

  /// Hands the screen over to the attempt, and counts in once it has settled.
  void _start() {
    // Only where the rung has no further use for it. At the cued rung the
    // keyboard is the cue, and it stays where it is.
    if (_instrumentLeavesAtReady) _handover.forward();
    widget.onUnderWay?.call();
    _beginCountIn();
  }

  void _beginCountIn() {
    _settling?.cancel();
    _countIn?.cancel();
    unawaited(_pulse.prepare());
    setState(() {
      _phase = _Phase.countIn;
      _beatsLeft = _countInBeats;
    });
    _settling = Timer(attemptSettle, () {
      if (mounted) _countInAndPlay();
    });
  }

  void _countInAndPlay() {
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
          ref
              .read(attemptTranscriptProvider.notifier)
              .start(widget.exercise.material);
          _watchdog = Timer.periodic(_watchdogTick, (_) => _watch());
        }
      });
    });
  }

  void _pause() {
    if (_phase != _Phase.countIn) return;
    _settling?.cancel();
    _countIn?.cancel();
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).discard();
    setState(() => _phase = _Phase.paused);
  }

  void _backToReady() {
    if (_phase != _Phase.paused) return;
    ref.read(attemptTranscriptProvider.notifier).discard();
    _handover.reverse();
    setState(() {
      _phase = _Phase.ready;
      _beatsLeft = _countInBeats;
    });
    widget.onBackToReady?.call();
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
    await _handOverTheScreen();
    await widget.onDecline!();
  }

  /// Sends the instrument off the bottom, if it is still there, and waits for
  /// it to go.
  ///
  /// What an attempt ends with, so it ends the way it began: the review takes
  /// a screen the keyboard has left rather than one it blinks out of.
  Future<void> _handOverTheScreen() async {
    if (_handover.isCompleted) return;
    _handover.forward();
    await Future<void>.delayed(attemptTransition);
  }

  Future<void> _finish(AttemptTermination termination) async {
    if (_finishing) return;
    _finishing = true;
    _watchdog?.cancel();
    unawaited(_pulse.stop());
    ref.read(attemptTranscriptProvider.notifier).stop();
    setState(() => _phase = _Phase.finishing);
    await _handOverTheScreen();
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

    // With nothing cued, the staff is free to carry what was played in the
    // order it arrived. With a cue on it, it is not: writing observations
    // into a score that already shows the answer means saying which expected
    // note each of them was, which is a judgment. A cue staff lights the note
    // each hand has reached instead, which says where in the exercise a hand
    // is rather than whether what it played was right.
    //
    // It changes hands at Ready rather than at the first beat, so the screen
    // the count-in runs over is the screen the attempt is played on.
    final staffCarriesTranscript =
        echoes && !showsCue && _phase != _Phase.ready;

    final layout = Layout.of(context);
    // The statement is on screen only until the attempt starts, and the bar
    // takes it from there. Collapsed rather than hidden, so the music grows
    // into the room it leaves as it leaves it.
    final task = AnimatedCrossFade(
      duration: attemptTransition,
      sizeCurve: attemptCurve,
      crossFadeState: _phase == _Phase.ready
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: Padding(
        padding: EdgeInsets.fromLTRB(layout.gutter, 16, layout.gutter, 0),
        child: _TaskStatement(exercise),
      ),
      secondChild: const SizedBox(width: double.infinity),
    );
    final notation = AnimatedOpacity(
      duration: attemptTransition,
      opacity: _phase == _Phase.paused ? 0.35 : 1,
      child: _Notation(
        gutter: layout.gutter,
        follows: staffCarriesTranscript,
        children: [
          if (showsCue && cueOnStaff(presentation.cueModality))
            StaffCue(
              exercise: exercise,
              showsFingering: presentation.motorCue == MotorCue.fingering,
              locates: echoes && _phase == _Phase.playing,
            ),
          if (staffCarriesTranscript)
            TranscriptStaff(transcript: transcript, exercise: exercise),
        ],
      ),
    );
    final instrument = _Instrument(
      exercise: exercise,
      showsCue: showsCue && cueOnKeyboard(presentation.cueModality),
      echoes: echoes,
      showsFingering: presentation.motorCue == MotorCue.fingering,
      height: layout.instrumentHeight,
    );
    // Sized to what the phase actually needs, and animated between them: the
    // Ready block is three things tall and Done is one, and the music takes
    // the difference rather than the screen keeping it empty.
    //
    // A text button carries its own touch target, which is taller than its
    // text and reads as space under it. Where one is showing, that height is
    // taken off the bottom, so what is below the last thing on screen looks
    // the same whichever thing it is.
    final controls = AnimatedSize(
      duration: attemptTransition,
      curve: attemptCurve,
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          layout.gutter,
          0,
          layout.gutter,
          _showsDecline ? _bottomInset - _touchTargetSlack : _bottomInset,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Status(phase: _phase, guidance: guidance),
            const SizedBox(height: 12),
            _control(),
          ],
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _phase == _Phase.countIn ? _pause : null,
      child: Column(
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
                              Expanded(
                                child: SingleChildScrollView(child: task),
                              ),
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
          //
          // Where the rung has no further use for it, it leaves downward with
          // the rest of the movement rather than vanishing under the count.
          _slot(instrument),
        ],
      ),
    );
  }

  /// The instrument, wherever it is between the bottom edge and its place.
  ///
  /// Its top follows the moving edge while the rest of it is clipped, so it
  /// arrives and leaves the way a keyboard slid onto a table would, and it is
  /// out of the tree whenever it is out of sight.
  Widget _slot(Widget instrument) => AnimatedBuilder(
    animation: _handover,
    child: instrument,
    builder: (context, child) {
      // Out of the tree once it has left, and not merely because it is at the
      // bottom: it starts there on its way up.
      if (_handover.status == AnimationStatus.completed) {
        return const SizedBox(width: double.infinity);
      }
      final gone = attemptCurve.transform(_handover.value);
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1 - gone,
          child: child,
        ),
      );
    },
  );

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
        //
        // What it says depends on what is on screen. With the notes shown for
        // study, nobody is being asked to remember anything yet, and a button
        // saying they do not is one they would have to translate.
        if (_showsDecline) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _decline,
            child: Text(
              widget.exercise.guidance.independence == 1
                  ? "I can't play this from memory"
                  : "I don't remember",
            ),
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
    _Phase.paused => SizedBox(
      height: 88,
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _backToReady,
              child: const Text('Back to Ready'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _beginCountIn,
              child: const Text('Resume'),
            ),
          ),
        ],
      ),
    ),
    // Done keeps the height the count had, so the music above it stays where
    // it was laid out when the count ends.
    _Phase.playing =>
      _questioned
          ? _Question(
              played: ref.watch(attemptTranscriptProvider).isNotEmpty,
              onDone: () => _finish(AttemptTermination.learnerStopped),
              onKeepPlaying: _keepPlaying,
            )
          : SizedBox(
              height: 88,
              child: Center(
                child: FilledButton.tonal(
                  onPressed: () => _finish(AttemptTermination.learnerStopped),
                  child: const Text('Done'),
                ),
              ),
            ),
    // Still Done, just no longer pressable. Swapping in a spinner for an
    // append and a scheduler decision makes a wait out of something that is
    // not one, and moves the screen while the learner is still looking at it.
    _Phase.finishing => const SizedBox(
      height: 88,
      child: Center(
        child: FilledButton.tonal(onPressed: null, child: Text('Done')),
      ),
    ),
  };
}

/// The space the written music takes, whether or not there is any.
///
/// Centered while it fits and scrollable once it does not: an exercise runs from
/// nothing on screen to four systems of it, and a staff pinned to the top of a
/// tall phone reads as an afterthought at one octave.
class _Notation extends StatefulWidget {
  const _Notation({
    required this.gutter,
    required this.children,
    this.follows = false,
  });

  final double gutter;
  final List<Widget> children;

  /// Whether the music is being written as it is played, which decides both
  /// where it sits and whether it moves.
  ///
  /// Something still being written grows downward, so it is held to the top:
  /// centering it would move every system already on screen each time another
  /// one opened. Something finished is centered, because then there is nothing
  /// left to come and the empty half of the screen is just empty.
  final bool follows;

  @override
  State<_Notation> createState() => _NotationState();
}

class _NotationState extends State<_Notation> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_Notation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.follows) _keepUp();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the system being played on screen once there are more of them than
  /// fit, letting the ones already played leave off the top.
  ///
  /// Only ever forward. A learner who has scrolled back to look at something
  /// is reading, and dragging them to the end of it would be answering a
  /// question they did not ask.
  void _keepUp() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (end <= _scroll.offset) return;
      unawaited(
        _scroll.animateTo(
          end,
          duration: attemptTransition,
          curve: attemptCurve,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final music = Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.children,
    );

    return LayoutBuilder(
      builder: (context, constraints) => _FadingEdges(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(widget.gutter, 16, widget.gutter, 16),
          child: widget.follows
              ? music
              : ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 32).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Center(child: music),
                ),
        ),
      ),
    );
  }
}

/// How deep the music fades into an edge it runs past.
const double _fadeExtent = 28;

/// Fades whichever edge the music continues past.
///
/// A staff cut off by a hard edge reads as a staff that ends there. What is
/// off screen is above or below rather than missing, and a fade is how a
/// surface says so without spending height on saying it.
class _FadingEdges extends StatefulWidget {
  const _FadingEdges({required this.controller, required this.child});

  /// The scroll position the edges are read from, for the first frame: before
  /// anything scrolls or resizes, nothing has told this widget anything.
  final ScrollController controller;

  final Widget child;

  @override
  State<_FadingEdges> createState() => _FadingEdgesState();
}

class _FadingEdgesState extends State<_FadingEdges> {
  double _above = 0;
  double _below = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.controller.hasClients) {
        _read(widget.controller.position);
      }
    });
  }

  /// How much of [_fadeExtent] each edge is worth, so an edge a few pixels
  /// from the end fades by a few pixels rather than switching on.
  void _read(ScrollMetrics metrics) {
    final above = ((metrics.extentBefore) / _fadeExtent).clamp(0.0, 1.0);
    final below = ((metrics.extentAfter) / _fadeExtent).clamp(0.0, 1.0);
    if (above == _above && below == _below) return;
    setState(() {
      _above = above;
      _below = below;
    });
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          _read(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _read(notification.metrics);
            return false;
          },
          child: LayoutBuilder(
            builder: (context, constraints) {
              final fade = constraints.maxHeight <= 0
                  ? 0.0
                  : (_fadeExtent / constraints.maxHeight).clamp(0.0, 0.4);
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0, fade, 1 - fade, 1],
                  colors: [
                    Colors.black.withValues(alpha: 1 - _above),
                    Colors.black,
                    Colors.black,
                    Colors.black.withValues(alpha: 1 - _below),
                  ],
                ).createShader(bounds),
                child: widget.child,
              );
            },
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
          child: Text(played ? 'Keep playing' : 'Give me a moment'),
        ),
      ],
    );
  }
}

/// What was asked for. Visible at every rung, because it is the task rather
/// than a cue.
///
/// Ranked rather than listed. The scale is what the task *is*, the hand is who
/// plays it, and the shape and the tempo are how. Three equally weighted boxes
/// would say those matter equally, and a learner glancing up mid-position
/// needs the identity first.
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
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            materialName(exercise.material),
            style: theme.textTheme.displaySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HandsIcon(conditions.hands, size: 18),
              const SizedBox(width: 8),
              Text(
                handsName(conditions.hands).toUpperCase(),
                style: theme.textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // One line, the same one the bar carries during the attempt. The
          // tempo had a line to itself for its own rank in the task, and what
          // that cost was a line of music.
          Text(
            '${traversalName(conditions)} · '
            '${octavesName(conditions.octaves)} · '
            '${conditions.tempoBpm.round()} bpm',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
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
    if (phase == _Phase.paused) {
      return Text(
        'Paused',
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      );
    }
    if (phase != _Phase.ready) return const SizedBox(height: 20);

    return Text(
      switch (guidance.independence) {
        0 => 'The notes stay on screen while you play.',
        1 => 'Study it. The notes go away when you start.',
        _ => 'Play it from memory.',
      },
      style: Theme.of(context).textTheme.bodyMedium,
      textAlign: TextAlign.center,
    );
  }
}

/// A slot that produced nothing to play.
///
/// Three different situations, and only one of them is a defect. A narrow
/// focus that is caught up is a successful outcome and says so; a scope that
/// cannot be resolved is a configuration error the learner can back out of by
/// dropping the focus; and everything else is the scheduler declining every
/// admission path it has, which is worth reporting. That last one read as
/// running out of material once, while a hundred and fifty candidates were
/// still admissible and only the attempt cap had been hit.
class _NothingToPlay extends ConsumerWidget {
  const _NothingToPlay({required this.state});

  final PracticeLoopState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final layout = Layout.of(context);
    final focused = state.plan.isFocused;
    final (title, body) = switch (state.idle) {
      PracticeIdleReason.caughtUp when focused => (
        'Nothing in this focus needs practice.',
        'You are caught up on what you asked for. Review it anyway, widen the '
            'focus, or stop here.',
      ),
      PracticeIdleReason.caughtUp => (
        'Nothing needs practice right now.',
        'You are caught up on your goal. Come back when it has had time to '
            'settle.',
      ),
      PracticeIdleReason.invalidScope => (
        'This focus cannot be practiced.',
        'Part of what it names is not in the catalog this build installs. '
            'Practicing normally will get you moving again.',
      ),
      _ => (
        'Nothing to practice right now.',
        'That should not happen, so it is worth reporting. Try again, or stop '
            'here and come back later.',
      ),
    };

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: layout.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (focused)
              FilledButton(
                onPressed: () =>
                    ref.read(practicePlanProvider.notifier).practiceNormally(),
                child: const Text('Practice normally'),
              )
            else
              FilledButton(
                onPressed: () =>
                    ref.read(practiceLoopProvider.notifier).reopen(),
                child: const Text('Try again'),
              ),
          ],
        ),
      ),
    );
  }
}
