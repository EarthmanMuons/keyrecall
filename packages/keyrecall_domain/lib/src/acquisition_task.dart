import 'package:meta/meta.dart';

import 'exercise.dart';
import 'presentation_conditions.dart';
import 'realization.dart';
import 'technical_material.dart';

/// Which part of the parent exercise is played.
///
/// Sealed rather than an enum because the value a fragment needs carries data:
/// where the window starts, where it ends, and which transition it exists to
/// rehearse. Only [FullTraversal] is constructible; a window is added when
/// observations say which transition is worth isolating.
@immutable
sealed class TaskPortion {
  const TaskPortion();
}

/// The whole of the parent exercise, in its own order.
@immutable
final class FullTraversal extends TaskPortion {
  const FullTraversal();

  @override
  bool operator ==(Object other) => other is FullTraversal;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'FullTraversal()';
}

/// Whether the task asks the learner to keep to a pulse.
///
/// Its own axis, and not a guidance rung. Removing the tempo obligation
/// changes what the task is; a guidance rung changes only how much of the
/// material is supplied for a task that is otherwise unchanged.
///
/// A continuity-only demand sits between these two: keep going, at whatever
/// speed. It is not offered until there is a reason to prefer it to either
/// end.
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
  /// Nothing was asked for under [unmetered], so how fast the learner happened
  /// to play is a fact about the attempt and not a reading of a request.
  bool get supportsTempoEvidence => requestsTempo;
}

/// Who decides when the next moment happens.
///
/// Assisted advancement, where the app sequences the material and the learner
/// answers each prompt, is a different task again: it takes over remembering
/// what comes next. It is not offered until an unmetered traversal has shown
/// that learner-driven sequencing is the thing in the way.
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
/// Three values, not a score. Reaching the end after corrections is real work
/// and is recorded as such; it is simply not the same thing as reaching the
/// end without them.
///
/// Completion means the material was produced, not that every position was
/// accounted for. Alignment explains a wrong note as a substitution, which
/// covers the position it fell on, so a traversal of arbitrary notes satisfies
/// every position without any of the material having been played.
enum AcquisitionCompletion {
  /// Something the task asked for was never played.
  ///
  /// Either it never arrived, or something else was played in its place and
  /// the learner moved on. A position covered by a wrong note is not the
  /// material having been produced.
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
/// Not an [Exercise], and deliberately not one. An exercise under any guidance
/// rung is still an ordinary realization of its material, so what it observes
/// is ordinary evidence. An acquisition task relaxes the task itself, so what
/// it observes is evidence about the relaxed task and nothing else. Keeping it
/// off the [Exercise] type is what stops it reaching candidate ranking, the
/// frontier, and the learner model by any route that already exists.
///
/// Three choices, held apart from the [parent]'s guidance because they are not
/// support for the same task: [portion] says how much is played, [timing] says
/// whether a pulse is asked for, and [advancement] says who sequences it.
/// Calling all of them "more guidance" would hide a change to what the learner
/// demonstrated.
///
/// Success here earns a probe of the unchanged [parent]. Only that probe
/// establishes ordinary readiness or a frontier.
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
  /// learner *is* the parent. Admitting it here would fence off evidence the
  /// attempt actually earned.
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
  /// The one acquisition task V1 offers. It keeps the material, the hand, the
  /// span, the direction, and the cues exactly as the parent has them, and
  /// asks a narrower question: can you produce this sequence when time is not
  /// the limiting resource?
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
  /// rule rather than an invariant of either value alone, checked where the
  /// pair is formed, as [PresentationConditions.suitsGuidance] is.
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
/// The parent's realization, narrowed to the portion. Nothing about the
/// timing demand reaches it: a realization says which notes in what order, and
/// a moment's metric offset is where it would fall if a pulse were asked for.
ExerciseRealization realizeAcquisition(AcquisitionTask task) =>
    switch (task.portion) {
      FullTraversal() => realize(task.parent),
    };
