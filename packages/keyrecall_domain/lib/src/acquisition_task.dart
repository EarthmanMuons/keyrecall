import 'package:meta/meta.dart';

import 'exercise.dart';
import 'presentation_conditions.dart';
import 'realization.dart';
import 'technical_material.dart';

/// Which part of the parent exercise is played.
///
/// Sealed rather than an enum because a portion can carry data, such as the
/// bounds of a window over the parent.
@immutable
sealed class TaskPortion {
  const TaskPortion();

  /// How many complete traversals of the parent are asked for.
  int get traversals;
}

/// The whole of the parent exercise, in its own order.
@immutable
final class FullTraversal extends TaskPortion {
  const FullTraversal();

  @override
  int get traversals => 1;

  @override
  bool operator ==(Object other) => other is FullTraversal;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'FullTraversal()';
}

/// The whole of the parent exercise, played through more than once.
///
/// Repetitions rather than a longer traversal, so the material stays exactly
/// what the parent asks for instead of gaining the crossing a wider span would
/// add. A pattern too short to say anything about continuity supplies more
/// intervals by being played again.
///
/// First-class rather than a longer list of notes, because the boundary between
/// one traversal and the next belongs to neither: the learner resets their hand
/// there, and nothing should read that as hesitation.
@immutable
final class TraversalRepetitions extends TaskPortion {
  @override
  final int traversals;

  /// Throws [ArgumentError] for fewer than two, which is [FullTraversal].
  TraversalRepetitions(this.traversals) {
    if (traversals < 2) {
      throw ArgumentError.value(
        traversals,
        'traversals',
        'one traversal is a FullTraversal',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TraversalRepetitions && other.traversals == traversals;

  @override
  int get hashCode => traversals;

  @override
  String toString() => 'TraversalRepetitions($traversals)';
}

/// Whether the task asks the learner to keep to a pulse.
///
/// Its own axis, and not a guidance rung. Removing the tempo obligation changes
/// what the task is, where a guidance rung changes only how much of the
/// material is supplied for an otherwise unchanged task.
enum TimingDemand {
  /// A tempo is asked for and the learner is expected to hold it.
  metered('METERED'),

  /// No tempo is asked for. The learner controls when each note happens.
  unmetered('UNMETERED');

  const TimingDemand(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The demand with the given [id].
  ///
  /// Throws [ArgumentError] when no demand matches.
  static TimingDemand fromId(String id) => values.firstWhere(
    (demand) => demand.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown timing demand'),
  );

  /// Whether a tempo is stated for the learner to play to.
  bool get requestsTempo => this == TimingDemand.metered;

  /// Whether an attempt under this demand can say anything about tempo.
  ///
  /// Nothing is asked for under [unmetered], so how fast the learner happened
  /// to play answers no request.
  bool get supportsTempoEvidence => requestsTempo;
}

/// Who decides when the next moment happens.
///
/// Separate from [TimingDemand] and from guidance because it records who
/// determines sequence progression, which neither of those says.
enum TaskAdvancement {
  /// The learner produces the next note when they are ready.
  learnerDriven('LEARNER_DRIVEN');

  const TaskAdvancement(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// The advancement with the given [id].
  ///
  /// Throws [ArgumentError] when no advancement matches.
  static TaskAdvancement fromId(String id) => values.firstWhere(
    (advancement) => advancement.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown advancement'),
  );
}

/// What an acquisition attempt delivered against what it asked for.
///
/// Three values, not a score. Completion means the material was produced, not
/// that every position was accounted for: alignment covers a position with a
/// substitution, so arbitrary notes satisfy every position without any of the
/// material having been played.
enum AcquisitionCompletion {
  /// Something the task asked for was never played.
  ///
  /// Either it never arrived, or something else was played in its place and
  /// the learner moved on.
  notCompleted('NOT_COMPLETED'),

  /// Every note the task asked for was played, with extra notes along the way.
  completedWithCorrections('COMPLETED_WITH_CORRECTIONS'),

  /// Everything arrived, right the first time.
  completedCleanly('COMPLETED_CLEANLY');

  const AcquisitionCompletion(this.id);

  /// Stable identifier used in persisted state and traces.
  final String id;

  /// Whether the task was played through.
  bool get isComplete => this != AcquisitionCompletion.notCompleted;
}

/// Supported acquisition of part of an ordinary exercise.
///
/// Not an [Exercise]. An exercise under any guidance rung is still an ordinary
/// realization of its material, where an acquisition task relaxes the task
/// itself and observes only the relaxed task. Keeping it off the [Exercise]
/// type is what stops it reaching candidate ranking, the frontier, and the
/// learner model.
///
/// [portion] says how much is played, [timing] whether a pulse is asked for,
/// and [advancement] who sequences it. Success here earns a probe of the
/// unchanged [parent], and only that probe establishes ordinary readiness or a
/// frontier.
@immutable
class AcquisitionTask {
  /// The ordinary exercise this rehearses part of.
  final Exercise parent;

  /// How much of the parent is played.
  final TaskPortion portion;

  /// Whether a pulse is asked for.
  final TimingDemand timing;

  /// Who decides when the next moment happens.
  final TaskAdvancement advancement;

  /// Throws [ArgumentError] when nothing about the parent is relaxed.
  ///
  /// A task that asks for the whole parent, at its tempo, sequenced by the
  /// learner *is* the parent, and admitting it here would fence off evidence
  /// the attempt earned.
  AcquisitionTask({
    required this.parent,
    required this.timing,
    required this.advancement,
    this.portion = const FullTraversal(),
  }) {
    if (portion is FullTraversal &&
        timing == TimingDemand.metered &&
        advancement == TaskAdvancement.learnerDriven) {
      throw ArgumentError.value(
        parent,
        'parent',
        'an acquisition task relaxes something about its parent',
      );
    }
  }

  /// The whole parent traversal, at whatever pace the learner takes.
  ///
  /// The one acquisition task V1 offers. Material, hand, span, direction, and
  /// cues are the parent's; only the tempo obligation is dropped.
  AcquisitionTask.unmeteredTraversal(Exercise parent)
    : this(
        parent: parent,
        timing: TimingDemand.unmetered,
        advancement: TaskAdvancement.learnerDriven,
      );

  /// What is being played.
  TechnicalMaterial get material => parent.material;

  /// Whether [presentation] can carry this task.
  ///
  /// An unmetered task states no tempo, so nothing may sound one. A pairing
  /// rule rather than an invariant of either value alone, like
  /// [PresentationConditions.suitsGuidance].
  bool suitsPresentation(PresentationConditions presentation) =>
      timing.requestsTempo || presentation.tempoSupport == TempoSupport.none;

  @override
  bool operator ==(Object other) =>
      other is AcquisitionTask &&
      other.parent == parent &&
      other.portion == portion &&
      other.timing == timing &&
      other.advancement == advancement;

  @override
  int get hashCode => Object.hash(parent, portion, timing, advancement);

  @override
  String toString() =>
      'AcquisitionTask($portion, ${timing.id}, ${advancement.id}, '
      'of $parent)';
}

/// The notes [task] asks for, in order.
///
/// The parent's realization, narrowed to the portion. Nothing about the timing
/// demand reaches it: a moment's metric offset is only where it would fall if a
/// pulse were asked for.
ExerciseRealization realizeAcquisition(AcquisitionTask task) {
  final traversal = realize(task.parent);
  if (task.portion.traversals == 1) return traversal;
  final beats =
      traversal.moments.last.metricOffset -
      traversal.moments.first.metricOffset;
  return ExerciseRealization([
    for (var repetition = 0; repetition < task.portion.traversals; repetition++)
      for (final moment in traversal.moments)
        RealizationMoment(
          position: repetition * traversal.moments.length + moment.position,
          // Repetitions continue past the end of the first traversal. A
          // repeated task states no tempo, so nothing reads this.
          metricOffset: moment.metricOffset + repetition * (beats + 1),
          notes: moment.notes,
        ),
  ]);
}

/// The position each traversal of [task] begins at, the first included.
///
/// Where the learner is allowed to stop and start again. A gap spanning one of
/// these boundaries is the reset between traversals, not a wait inside one.
List<int> acquisitionTraversalStarts(AcquisitionTask task) {
  if (task.portion.traversals == 1) return const [0];
  final length = realize(task.parent).moments.length;
  return [
    for (var repetition = 0; repetition < task.portion.traversals; repetition++)
      repetition * length,
  ];
}

/// The supported task a family offers below one of its declared floors.
///
/// Declared by the family rather than assumed by whoever offers it, since what
/// a supported version of the work is follows from the family's motor
/// structure. The rule that reads this stays family-neutral: a floor with a
/// scaffold can be acquired, a floor without one cannot.
@immutable
class AcquisitionScaffold {
  /// Whether a pulse is asked for.
  final TimingDemand timing;

  /// Who decides when the next moment happens.
  final TaskAdvancement advancement;

  /// How much of the parent is played.
  final TaskPortion portion;

  const AcquisitionScaffold({
    required this.timing,
    required this.advancement,
    this.portion = const FullTraversal(),
  });

  /// The whole traversal, at whatever pace the learner takes.
  const AcquisitionScaffold.unmeteredTraversal()
    : this(
        timing: TimingDemand.unmetered,
        advancement: TaskAdvancement.learnerDriven,
      );

  /// The whole traversal [traversals] times over, at the learner's own pace.
  ///
  /// For a pattern whose single traversal is too short to say anything about
  /// continuity. The family works out the fewest repetitions that supply what
  /// the criterion asks for.
  ///
  /// Throws [ArgumentError] for fewer than one traversal, which asks for no
  /// work at all.
  AcquisitionScaffold.unmeteredRepetitions(int traversals)
    : this(
        timing: TimingDemand.unmetered,
        advancement: TaskAdvancement.learnerDriven,
        portion: _repetitionsOf(traversals),
      );

  /// This scaffold applied to [parent].
  AcquisitionTask taskFor(Exercise parent) => AcquisitionTask(
    parent: parent,
    timing: timing,
    advancement: advancement,
    portion: portion,
  );

  @override
  bool operator ==(Object other) =>
      other is AcquisitionScaffold &&
      other.timing == timing &&
      other.advancement == advancement &&
      other.portion == portion;

  @override
  int get hashCode => Object.hash(timing, advancement, portion);

  @override
  String toString() =>
      'AcquisitionScaffold($portion, ${timing.id}, ${advancement.id})';
}

TaskPortion _repetitionsOf(int traversals) => switch (traversals) {
  < 1 => throw ArgumentError.value(
    traversals,
    'traversals',
    'must be at least one',
  ),
  1 => const FullTraversal(),
  _ => TraversalRepetitions(traversals),
};
