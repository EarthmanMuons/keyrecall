import 'dart:async';

/// A set of delayed callbacks that can be abandoned as a group.
///
/// Restarting bumps a generation counter, so callbacks already in flight from
/// an earlier run find themselves stale and do nothing. Without that, notes
/// scheduled for a sequence nobody is playing any more would keep arriving
/// after the next one had started.
///
/// Vendored from WhatChord's `CancelableTimerSequence`.
class CancelableTimerSequence {
  final Set<Timer> _timers = <Timer>{};
  int _generation = 0;

  /// The run callbacks are currently being scheduled for.
  int get generation => _generation;

  /// Whether [generation] is still the current run.
  bool isCurrent(int generation) => generation == _generation;

  /// Abandons everything scheduled and returns the new run's generation.
  int restart() {
    cancel();
    return _generation;
  }

  /// Runs [callback] after [delay], unless its run has been abandoned first.
  ///
  /// A nonpositive delay runs immediately rather than waiting a tick, so a
  /// caller can schedule a whole sequence uniformly without special-casing the
  /// first entry.
  void schedule(
    Duration delay,
    void Function(int generation) callback, {
    int? generation,
  }) {
    final scheduledGeneration = generation ?? _generation;
    if (delay <= Duration.zero) {
      if (isCurrent(scheduledGeneration)) {
        callback(scheduledGeneration);
      }
      return;
    }

    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (isCurrent(scheduledGeneration)) {
        callback(scheduledGeneration);
      }
    });
    _timers.add(timer);
  }

  /// Abandons every pending callback.
  void cancel() {
    _generation++;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  /// Abandons everything and releases the timers.
  void dispose() {
    cancel();
  }
}
