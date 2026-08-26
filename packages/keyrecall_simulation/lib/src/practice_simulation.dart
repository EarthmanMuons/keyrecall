import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'attempt_trace.dart';
import 'python_compatible_random.dart';
import 'synthetic_learner.dart';

/// The reference instant simulations count from.
///
/// An arbitrary fixed UTC point. Simulated time is deliberately absolute
/// rather than relative to the wall clock, so a run made today and the same
/// run made next year produce identical traces.
final DateTime defaultSimulationEpoch = DateTime.utc(2026);

/// Simulated time between consecutive attempts.
const Duration defaultAttemptSpacing = Duration(hours: 12);

/// What a chooser knows when it decides what to present next.
class AttemptContext {
  /// The simulation's random stream, for choosers that want to sample.
  final PythonCompatibleRandom rng;

  /// Position of the upcoming attempt, counting from zero.
  final int attemptIndex;

  /// Learner state, already propagated to [at].
  final LearnerState state;

  /// When the upcoming attempt happens.
  final DateTime at;

  const AttemptContext({
    required this.rng,
    required this.attemptIndex,
    required this.state,
    required this.at,
  });
}

/// Decides what to present for one attempt.
///
/// A scripted fixture, a random draw, or the real scheduler all fit this
/// shape, which is what lets one harness drive every kind of run.
typedef ExerciseChooser = Exercise Function(AttemptContext context);

/// Called once the outcome exists, for choosers that keep their own
/// bookkeeping.
typedef OutcomeObserver =
    void Function(Exercise exercise, Outcome outcome, DateTime at);

/// A synthetic learner practicing over simulated time.
///
/// One object owns the whole run: the hidden truth, the model's estimate of
/// it, the clock, and the random stream. Attempts can be run in batches, and
/// the run continues where it left off, so a caller can inspect or checkpoint
/// state partway without perturbing the sequence.
///
/// Defaults to [LearnerModel.v1Prototype] rather than the live model, because
/// this harness exists to hold the port against the frozen Python reference.
/// Its synthetic learner samples an achieved tempo below the requested one on
/// nearly every attempt, so under the live model these runs would diverge from
/// the reference by design and stop testing what they were built to test.
/// Pass the live model explicitly to simulate current behavior.
class PracticeSimulation {
  /// The learner model under test.
  final LearnerModel learner;

  /// The hidden learner outcomes are sampled from.
  final TrueLearnerProfile truth;

  /// The instant the run counts from, before any attempt.
  final DateTime epoch;

  /// Simulated time between consecutive attempts.
  final Duration attemptSpacing;

  /// The random stream driving outcome sampling and any sampling chooser.
  final PythonCompatibleRandom rng;

  /// The model's current estimate of the learner.
  final LearnerState state;

  DateTime _at;
  int _attemptIndex = 0;

  PracticeSimulation._({
    required this.learner,
    required this.truth,
    required this.epoch,
    required this.attemptSpacing,
    required this.rng,
    required this.state,
  }) : _at = epoch;

  /// A run of [profile], seeded at placement from its self-report.
  ///
  /// The estimate starts from what the learner says about themselves, not from
  /// the hidden truth: closing that gap is what the run measures.
  factory PracticeSimulation.of(
    SyntheticProfile profile, {
    required int seed,
    LearnerModel learner = const LearnerModel.v1Prototype(),
    DateTime? epoch,
    Duration attemptSpacing = defaultAttemptSpacing,
  }) {
    final start = epoch ?? defaultSimulationEpoch;
    final truth = profile.build(start: start);
    return PracticeSimulation._(
      learner: learner,
      truth: truth,
      epoch: start,
      attemptSpacing: attemptSpacing,
      rng: PythonCompatibleRandom(seed),
      state: learner.placementState(truth.selfReportTier, at: start),
    );
  }

  /// A run over an existing [truth] and [state], for scenarios that stage a
  /// specific starting position.
  factory PracticeSimulation.from({
    required TrueLearnerProfile truth,
    required LearnerState state,
    required int seed,
    LearnerModel learner = const LearnerModel.v1Prototype(),
    DateTime? epoch,
    Duration attemptSpacing = defaultAttemptSpacing,
  }) => PracticeSimulation._(
    learner: learner,
    truth: truth,
    epoch: epoch ?? defaultSimulationEpoch,
    attemptSpacing: attemptSpacing,
    rng: PythonCompatibleRandom(seed),
    state: state,
  );

  /// Simulated time as of the most recent attempt.
  DateTime get at => _at;

  /// How many attempts have run so far.
  int get attemptCount => _attemptIndex;

  /// Runs [attempts] attempts and returns their traces.
  ///
  /// Each attempt advances the clock, propagates state to the new time, asks
  /// [chooser] what to present, predicts it, samples what the hidden learner
  /// does, weighs that as evidence, and applies the update. [onOutcome] runs
  /// afterward, for a chooser that tracks its own session state.
  ///
  /// Calling this repeatedly is equivalent to one longer call: the clock, the
  /// random stream, and both learners carry over.
  List<AttemptTrace> run(
    int attempts, {
    ExerciseChooser? chooser,
    OutcomeObserver? onOutcome,
  }) {
    final pick = chooser ?? randomExercise;
    final traces = <AttemptTrace>[];

    for (var i = 0; i < attempts; i++) {
      _at = _at.add(attemptSpacing);
      learner.propagate(state, _at);

      final exercise = pick(
        AttemptContext(
          rng: rng,
          attemptIndex: _attemptIndex,
          state: state,
          at: _at,
        ),
      );

      final stateBefore = state.copy();
      final prediction = learner.predict(state, exercise, at: _at);
      final outcome = sampleOutcome(
        profile: truth,
        exercise: exercise,
        at: _at,
        rng: rng,
      );
      final weights = evidenceWeightsFor(exercise, outcome);
      final memoryUpdate = learner.applyOutcome(
        state: state,
        exercise: exercise,
        outcome: outcome,
        weights: weights,
        prediction: prediction,
        at: _at,
      );
      onOutcome?.call(exercise, outcome, _at);

      traces.add(
        AttemptTrace(
          attemptIndex: _attemptIndex,
          at: _at,
          profile: truth.profile,
          exercise: exercise,
          prediction: prediction,
          outcome: outcome,
          weights: weights,
          memoryUpdate: memoryUpdate,
          stateBefore: stateBefore,
          stateAfter: state.copy(),
        ),
      );
      _attemptIndex++;
    }
    return traces;
  }
}

/// A chooser that draws a fresh exercise at random.
///
/// The default when a run is about the learner model rather than about the
/// scheduler's choices.
Exercise randomExercise(AttemptContext context) {
  final rng = context.rng;
  final material = rng.choice(v1ScaleCatalog);
  final hands = rng.choice(HandConfiguration.values);
  final octaves = rng.choice(const [1, 2]);
  final direction = rng.choice(ScaleDirection.values);
  final tempoBpm = rng.choice(const [60.0, 80.0, 100.0, 120.0]);

  // Two independent draws, collapsed onto the support ladder. Drawing both
  // keeps the random stream aligned with the reference implementation, which
  // samples the flags separately; collapsing them keeps "previewed and cued"
  // from becoming a fourth guidance value, since cues left visible supply the
  // material whether or not the notes were also shown first.
  final notesPreviewed = rng.nextDouble() < 0.3;
  final concurrentPitchCues = rng.nextDouble() < 0.15;
  final guidance = concurrentPitchCues
      ? GuidanceContext.continuouslyCued
      : (notesPreviewed
            ? GuidanceContext.notesPreviewedOnly
            : GuidanceContext.unguided);
  return Exercise.linear(
    material: material,
    hands: hands,
    octaves: octaves,
    direction: direction,
    tempoBpm: tempoBpm,
    guidance: guidance,
  );
}

/// A chooser that presents the same exercise every time.
///
/// The workhorse for diagnostics that need one variable to move at a time.
ExerciseChooser fixedExercise(Exercise exercise) =>
    (_) => exercise;
