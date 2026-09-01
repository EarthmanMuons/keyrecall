import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// How long an attempt may go quiet, and how long it may run at all.
///
/// Every window here is observed rather than judged: silence and elapsed time
/// are facts about the arrival stream and the requested tempo, and none of
/// them reads a note. What they support is an offer rather than a seizure, so
/// a window passing changes what the screen says and never what the instrument
/// accepts. See `docs/domain-model/attempt-termination.md`.
///
/// The windows scale with the tempo the exercise asked for, because a bar is
/// what a learner feels rather than a number of seconds, with floors so that a
/// quick exercise does not question somebody who is simply thinking.
@immutable
class AttemptWindows {
  /// Silence after a note, after which the performance is taken to have ended.
  ///
  /// A bar, floored: long enough that a hesitation inside the traversal is not
  /// mistaken for the end of it.
  final Duration afterPlaying;

  /// Silence before the first note, after which the attempt asks whether
  /// anybody is still there.
  ///
  /// Longer than [afterPlaying], because getting hands to the keys and reading
  /// what was asked for happens here, and a prompt during it interrupts the
  /// attempt it is meant to protect.
  final Duration beforePlaying;

  /// Silence after which the attempt closes itself.
  ///
  /// The abandoned case: nobody is coming back to answer the offer, and an
  /// attempt left open forever is a decision the next sitting inherits.
  final Duration abandon;

  /// The longest an attempt may run, however much is arriving.
  ///
  /// A backstop for playing that never stops rather than a verdict on it: the
  /// note stream stays honest, so nothing here reads what was played.
  final Duration limit;

  const AttemptWindows({
    required this.afterPlaying,
    required this.beforePlaying,
    required this.abandon,
    required this.limit,
  });

  /// The windows an attempt at [exercise] runs under.
  factory AttemptWindows.forExercise(Exercise exercise) {
    final beat = Duration(
      microseconds:
          (60 * Duration.microsecondsPerSecond / exercise.conditions.tempoBpm)
              .round(),
    );
    final expected = beat * realize(exercise).moments.length;

    return AttemptWindows(
      afterPlaying: _atLeast(beat * 4, const Duration(seconds: 3)),
      beforePlaying: _atLeast(beat * 12, const Duration(seconds: 12)),
      abandon: const Duration(seconds: 45),
      limit: _atLeast(expected * 6, const Duration(minutes: 2)),
    );
  }

  static Duration _atLeast(Duration window, Duration floor) =>
      window < floor ? floor : window;

  @override
  String toString() =>
      'AttemptWindows(after $afterPlaying, before $beforePlaying, '
      'abandon $abandon, limit $limit)';
}
