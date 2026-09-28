import 'dart:math' as math;

import 'package:clock/clock.dart';

/// When each beat of one pulse falls, read from one clock.
///
/// The click, the count on screen, and the beat shown during a metronome all
/// read this, so none of them can drift against another: they do not keep
/// time, they ask it. The click renders its whole track on a sample clock from
/// the same start, which is what keeps it exact.
class PulseSchedule {
  /// Started now.
  PulseSchedule({
    required this.beat,
    required this.countInBeats,
    required this.continuingBeats,
    Duration Function()? elapsed,
  }) : _elapsed = elapsed ?? _startedNow();

  /// How long one beat lasts.
  final Duration beat;

  /// Beats before the attempt begins.
  final int countInBeats;

  /// Beats after it, which is a metronome.
  final int continuingBeats;

  final Duration Function() _elapsed;

  /// Read from `package:clock`, which is the system clock in the app and the
  /// pumped one under a widget test.
  static Duration Function() _startedNow() {
    final watch = clock.stopwatch()..start();
    return () => watch.elapsed;
  }

  /// Every beat the pulse holds.
  int get beats => countInBeats + continuingBeats;

  /// How long since the first beat.
  Duration get elapsed => _elapsed();

  /// The beat under way at [at], counted from zero, which may be past the
  /// last one.
  int beatAt(Duration at) =>
      at.isNegative ? 0 : at.inMicroseconds ~/ beat.inMicroseconds;

  /// The beat under way now.
  int get currentBeat => beatAt(elapsed);

  /// Whether the count-in is over and the attempt has begun.
  bool get countedIn => currentBeat >= countInBeats;

  /// What the count on screen says, down to one on the last beat of it.
  int get beatsLeftInCountIn => math.max(0, countInBeats - currentBeat);

  /// Whether the pulse has played its last beat.
  bool get isOver => currentBeat >= beats;

  /// Where in its bar [beatIndex] falls, from zero on the downbeat.
  static int placeInBar(int beatIndex, {int beatsPerBar = 4}) =>
      beatIndex % beatsPerBar;
}
