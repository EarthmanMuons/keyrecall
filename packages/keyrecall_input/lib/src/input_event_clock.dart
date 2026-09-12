/// Milliseconds since input observation started.
///
/// Monotonic by contract, so a wall-clock correction cannot reorder the stream.
typedef InputEventClock = int Function();

/// A monotonic clock backed by a [Stopwatch].
///
/// Every source in a session must share one, or their events cannot be ordered
/// against each other.
class StopwatchInputClock {
  final Stopwatch _stopwatch = Stopwatch()..start();

  /// Milliseconds elapsed since this clock was created.
  int call() => _stopwatch.elapsedMilliseconds;

  /// Stops the underlying stopwatch.
  void stop() => _stopwatch.stop();
}

/// A clock a test drives by hand.
class ManualInputClock {
  int _milliseconds;

  ManualInputClock([this._milliseconds = 0]);

  /// The current reading.
  int call() => _milliseconds;

  /// Moves the clock forward.
  ///
  /// Throws [ArgumentError] for a negative step.
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
