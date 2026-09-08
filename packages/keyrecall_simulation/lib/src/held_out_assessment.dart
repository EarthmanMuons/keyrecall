import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

import 'python_compatible_random.dart';
import 'synthetic_player.dart';

/// A fixed set of questions asked outside the practice sequence.
///
/// Every quantity a run reports today is endogenous to the policy: managed
/// yield, allocation share and frontier movement all describe what the
/// scheduler chose to ask, so a policy that asks easier questions scores
/// better on all three without the person having learned anything. This set is
/// the same for every policy, at every reading, whatever practice happened in
/// between, which is what makes a difference between two readings a statement
/// about the learner.
///
/// The set is deliberately small and fixed rather than representative. Growing
/// it between experiments would make two readings incomparable, which is the
/// one property it exists to have.
class AssessmentSet {
  /// What this set is called, in reports.
  final String id;

  /// The exercises asked, in order.
  final List<Exercise> exercises;

  /// How many times each exercise is asked.
  ///
  /// One attempt of a noisy player says very little. Repetition is the only
  /// noise control available that does not change the question.
  final int repetitions;

  /// The draw sequence every reading uses.
  ///
  /// Fixed rather than carried forward, so each reading meets the same luck
  /// and a change between two of them is a change in the player. Common random
  /// numbers across readings, in the usual sense.
  final int seed;

  const AssessmentSet({
    required this.id,
    required this.exercises,
    this.repetitions = 3,
    this.seed = 20260101,
  });

  /// How many attempts one reading takes.
  int get attempts => exercises.length * repetitions;
}

/// The standard held-out set: every material, each hand alone and together.
///
/// Unguided, so retrieval is genuinely tested, and at one octave and one tempo
/// for everything, so no reading is easier than another. A player who cannot
/// do any of it reads at the floor, which is a measurement rather than a
/// problem.
AssessmentSet standardAssessment(
  List<TechnicalMaterial> materials, {
  String id = 'v1-standard',
  double tempoBpm = 80,
  int repetitions = 3,
  int seed = 20260101,
}) => AssessmentSet(
  id: id,
  repetitions: repetitions,
  seed: seed,
  exercises: [
    for (final material in materials)
      for (final hands in HandConfiguration.values)
        Exercise.linear(material: material, hands: hands, tempoBpm: tempoBpm),
  ],
);

/// What one reading of a held-out set found.
///
/// Shares are over every attempt of the reading, so an attempt that never
/// started counts against execution rather than being dropped from it. That is
/// the honest denominator for an outcome measure: failing to begin is a way of
/// not playing the scale.
class AssessmentReading {
  /// Which set was asked.
  final String setId;

  /// When it was asked, on the run's own clock.
  final DateTime at;

  /// How many practice attempts the run had played by then.
  ///
  /// Two readings can share this and differ: the one closing a sitting and the
  /// one opening the next are the same amount of practice at two instants, and
  /// what separates them is the break.
  final int afterSlots;

  /// How many attempts this reading took.
  final int attempts;

  /// Share of retrieval-testing attempts where the material came unaided.
  final double retrieval;

  /// Share of attempts that began at all.
  final double started;

  /// Share of attempts that were played to the end.
  final double completion;

  /// Mean pitch integrity.
  final double pitchIntegrity;

  /// Mean temporal stability.
  final double temporalStability;

  /// Mean coordination over the hands-together attempts, or null when the set
  /// asked for none.
  final double? coordination;

  /// Share of attempts production would count as demonstrated execution.
  final double managed;

  /// What the learner model expected of this set, or null when no state was
  /// supplied.
  ///
  /// Held next to [managed] on purpose. A run across a calendar gap moves
  /// belief without moving the person, so the two drifting apart is the
  /// measurement that separates a scheduler reacting to a stale belief from
  /// one reacting to a learner who really has changed.
  final double? predicted;

  /// What the learner model expected the material retrieval to be, or null
  /// when no state was supplied.
  ///
  /// The same event [retrieval] observes, unlike [predicted], which is a
  /// stricter conjunction than [managed] and so carries a level offset by
  /// construction. Calibrating decay against a gap needs the pair that
  /// measures one thing.
  final double? predictedRetrieval;

  const AssessmentReading({
    required this.setId,
    required this.at,
    required this.afterSlots,
    required this.attempts,
    required this.retrieval,
    required this.started,
    required this.completion,
    required this.pitchIntegrity,
    required this.temporalStability,
    required this.managed,
    this.coordination,
    this.predicted,
    this.predictedRetrieval,
  });

  /// How far the model's expectation sits above what the player did.
  double? get beliefGap => predicted == null ? null : predicted! - managed;

  @override
  String toString() =>
      '$setId after $afterSlots: retrieval=${retrieval.toStringAsFixed(3)} '
      'managed=${managed.toStringAsFixed(3)} '
      'predicted=${predicted?.toStringAsFixed(3) ?? 'n/a'}';
}

/// Asks [set] of [playing] without teaching them anything.
///
/// The attempts are not practised, so ability, familiarity and the last
/// performed tempo are all left where the practice sequence left them, and the
/// draws come from the set's own stream. A reading is therefore free: taking
/// one cannot change the run it is measuring.
///
/// [state] is read, never written. Supplying it fills in [predicted].
AssessmentReading assess(
  AssessmentSet set,
  PlayerState playing, {
  required DateTime at,
  int afterSlots = 0,
  LearnerState? state,
  LearnerModel learner = const LearnerModel(),
}) {
  final rng = PythonCompatibleRandom(set.seed);
  final outcomes = <(Exercise, Outcome)>[];
  for (var repetition = 0; repetition < set.repetitions; repetition++) {
    for (final exercise in set.exercises) {
      outcomes.add((exercise, playing.play(exercise, rng, practising: false)));
    }
  }

  double share(bool Function(Outcome) holds) =>
      outcomes.where((o) => holds(o.$2)).length / outcomes.length;
  double mean(double Function(Outcome) of) =>
      outcomes.map((o) => of(o.$2)).reduce((a, b) => a + b) / outcomes.length;

  final predictions = state == null
      ? null
      : _expectationOf(set, state, learner, at);
  final tested = [
    for (final (exercise, outcome) in outcomes)
      if (exercise.guidance.isRetrievalObserved) outcome,
  ];
  final coordinated = [
    for (final (_, outcome) in outcomes) ?outcome.coordination,
  ];

  return AssessmentReading(
    setId: set.id,
    at: at,
    afterSlots: afterSlots,
    attempts: outcomes.length,
    retrieval: tested.isEmpty
        ? 0
        : tested
                  .where((o) => o.retrieval == FactualRetrieval.succeeded)
                  .length /
              tested.length,
    started: share((o) => o.started),
    completion: share((o) => o.completed),
    pitchIntegrity: mean((o) => o.pitchIntegrity),
    temporalStability: mean((o) => o.temporalStability),
    coordination: coordinated.isEmpty
        ? null
        : coordinated.reduce((a, b) => a + b) / coordinated.length,
    managed: share(learner.executionWasManaged),
    predicted: state == null ? null : predictions!.overall,
    predictedRetrieval: predictions?.retrieval,
  );
}

({double overall, double retrieval}) _expectationOf(
  AssessmentSet set,
  LearnerState state,
  LearnerModel learner,
  DateTime at,
) {
  var overall = 0.0;
  var retrieval = 0.0;
  for (final exercise in set.exercises) {
    final prediction = learner.predict(state, exercise, at: at);
    overall += prediction.overallP;
    retrieval += prediction.independentRetrievalP;
  }
  return (
    overall: overall / set.exercises.length,
    retrieval: retrieval / set.exercises.length,
  );
}
