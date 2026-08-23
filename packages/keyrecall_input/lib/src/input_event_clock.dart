/// Milliseconds since input observation started.
///
/// Monotonic by contract. A wall clock can be corrected backward mid
/// performance, and an input stream that reordered itself when that happened
/// would be unusable for anything measuring timing.
typedef InputEventClock = int Function();

/// A monotonic clock backed by a [Stopwatch].
///
/// One per input session: every source in that session must share it, or
/// events from different sources could not be ordered against each other.
class StopwatchInputClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Milliseconds elapsed since this clock was created.
  int call() => _stopwatch.elapsedMilliseconds;

  /// Stops the underlying stopwatch.
  void stop() => _stopwatch.stop();
}

/// A clock a test drives by hand.
///
/// Timing is most of what an input stream means, so tests need to state it
/// rather than race a real one.
class ManualInputClock {
  int _milliseconds;

  ManualInputClock([this._milliseconds = 0]);

  /// The current reading.
  int call() => _milliseconds;

  /// Moves the clock forward.
  ///
  /// Throws [ArgumentError] for a negative step, which would break the
  /// monotonic contract this type exists to keep.
  void advance(int milliseconds) {
    if (milliseconds < 0) {
      throw ArgumentError.value(
        milliseconds,
        'milliseconds',
        'an input clock cannot run backward',
      );
    }
    _milliseconds += milliseconds;
  }
}
