import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'acquisition_observation.dart';
import 'timing_evidence.dart';

/// One step of a task, named by the positions it runs between.
typedef Transition = ({int fromPosition, int toPosition});

/// How often each transition of one task happened, how often its wait could be
/// judged, and how often it stalled.
///
/// A single attempt says where the playing broke, and only repetition says a
/// transition is in the way. This counts, and does not decide what counts as
/// repeatedly troublesome.
///
/// Three counts rather than one, because a transition happening, its wait being
/// judgeable, and its wait being a stall are three separate facts. Each has its
/// own denominator: a transition past the point a learner keeps stopping is
/// reached rarely, so a raw stall count understates it, and an attempt too short
/// to establish a baseline reaches transitions whose waits nothing judged.
///
/// Scoped to one [task], since positions mean nothing across tasks.
@immutable
class TransitionCensus {
  /// The task every recorded attempt was an attempt at.
  final AcquisitionTask task;

  /// How many attempts were recorded, including those that produced no gaps.
  final int attempts;

  /// How many times each transition was played at all.
  final Map<Transition, int> observed;

  /// How many of those times its wait was read against a baseline.
  ///
  /// The denominator [stallRateOf] uses. A transition observed in an attempt
  /// that established no baseline is counted above and not here, so repeating
  /// such attempts cannot dilute a rate toward zero.
  final Map<Transition, int> assessable;

  /// How many of the assessable times it stalled.
  final Map<Transition, int> stalled;

  TransitionCensus._({
    required this.task,
    required this.attempts,
    required Map<Transition, int> observed,
    required Map<Transition, int> assessable,
    required Map<Transition, int> stalled,
  }) : observed = Map.unmodifiable(observed),
       assessable = Map.unmodifiable(assessable),
       stalled = Map.unmodifiable(stalled);

  /// Nothing recorded yet.
  TransitionCensus.of(AcquisitionTask task)
    : this._(
        task: task,
        attempts: 0,
        observed: const {},
        assessable: const {},
        stalled: const {},
      );

  /// This census with [observation] added.
  ///
  /// Throws [ArgumentError] when the observation is of a different task.
  TransitionCensus recording(AcquisitionObservation observation) {
    if (observation.task != task) {
      throw ArgumentError.value(
        observation.task,
        'observation',
        'positions are only comparable within one task',
      );
    }

    final observedNow = {...observed};
    final assessableNow = {...assessable};
    final stalledNow = {...stalled};
    void count(Map<Transition, int> counts, MomentGap gap) {
      counts.update(
        (fromPosition: gap.fromPosition, toPosition: gap.toPosition),
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    for (final gap in observation.gaps) {
      count(observedNow, gap);
    }
    for (final gap in observation.timing.assessableGaps) {
      count(assessableNow, gap);
    }
    for (final gap in observation.stalls) {
      count(stalledNow, gap);
    }

    return TransitionCensus._(
      task: task,
      attempts: attempts + 1,
      observed: observedNow,
      assessable: assessableNow,
      stalled: stalledNow,
    );
  }

  /// How often [transition] stalled when its wait could be judged, or null when
  /// it never could.
  ///
  /// Null rather than zero, because a transition nothing assessed and one played
  /// through cleanly are not the same observation. Null is also what a
  /// transition the learner never reached reports, and [observed] is what
  /// separates the two.
  double? stallRateOf(Transition transition) {
    final times = assessable[transition];
    if (times == null || times == 0) return null;
    return (stalled[transition] ?? 0) / times;
  }

  /// The transitions that stalled at least [times], worst first.
  ///
  /// The threshold is the caller's, since nothing here knows how many stalls
  /// make a transition worth isolating.
  List<Transition> stalledAtLeast(int times) {
    final repeated = [
      for (final MapEntry(key: transition, value: count) in stalled.entries)
        if (count >= times) transition,
    ];
    repeated.sort((a, b) {
      final byCount = stalled[b]!.compareTo(stalled[a]!);
      return byCount != 0 ? byCount : a.toPosition.compareTo(b.toPosition);
    });
    return repeated;
  }

  @override
  String toString() =>
      'TransitionCensus($attempts attempts, '
      '${stalled.length} transitions stalled)';
}
