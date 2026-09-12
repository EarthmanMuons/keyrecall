import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

import 'acquisition_observation.dart';

/// One step of a task, named by the positions it runs between.
typedef Transition = ({int fromPosition, int toPosition});

/// How often each transition of one task was played, and how often it stalled.
///
/// A single attempt says where the playing broke, and only repetition says a
/// transition is in the way. This counts, and does not decide what counts as
/// repeatedly troublesome.
///
/// Both counts are kept because they have different denominators: a transition
/// past the point a learner keeps stopping is played rarely, so a raw stall
/// count understates it.
///
/// Scoped to one [task], since positions mean nothing across tasks.
@immutable
class TransitionCensus {
  /// The task every recorded attempt was an attempt at.
  final AcquisitionTask task;

  /// How many attempts were recorded, including those that produced no gaps.
  final int attempts;

  /// How many times each transition was played.
  final Map<Transition, int> played;

  /// How many of those times it stalled.
  final Map<Transition, int> stalled;

  TransitionCensus._({
    required this.task,
    required this.attempts,
    required Map<Transition, int> played,
    required Map<Transition, int> stalled,
  }) : played = Map.unmodifiable(played),
       stalled = Map.unmodifiable(stalled);

  /// Nothing recorded yet.
  TransitionCensus.of(AcquisitionTask task)
    : this._(task: task, attempts: 0, played: const {}, stalled: const {});

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

    final playedNow = {...played};
    final stalledNow = {...stalled};
    for (final gap in observation.gaps) {
      final transition = (
        fromPosition: gap.fromPosition,
        toPosition: gap.toPosition,
      );
      playedNow.update(transition, (count) => count + 1, ifAbsent: () => 1);
    }
    for (final gap in observation.stalls) {
      final transition = (
        fromPosition: gap.fromPosition,
        toPosition: gap.toPosition,
      );
      stalledNow.update(transition, (count) => count + 1, ifAbsent: () => 1);
    }

    return TransitionCensus._(
      task: task,
      attempts: attempts + 1,
      played: playedNow,
      stalled: stalledNow,
    );
  }

  /// How often [transition] stalled when it was played, or null when it never
  /// was.
  ///
  /// Null rather than zero, because a transition the learner never reached and
  /// one they reached and played through are not the same observation.
  double? stallRateOf(Transition transition) {
    final times = played[transition];
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
