import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';

/// One note's journey from the wire to the screen.
///
/// Every stage is stamped against the same monotonic clock the input sources
/// use, so the differences mean something. What it cannot see is the part
/// before the app: a Bluetooth instrument's own latency is already inside
/// [arrived].
@immutable
class LatencySample {
  /// Which note of the transcript.
  final int sequence;

  /// When the normalized input event was stamped.
  final int arrivedMs;

  /// When the transcript had it.
  final int appendedMs;

  /// When the frame that first included it had been painted.
  final int? paintedMs;

  const LatencySample({
    required this.sequence,
    required this.arrivedMs,
    required this.appendedMs,
    this.paintedMs,
  });

  /// How long the app took to record what arrived.
  int get toAppendMs => appendedMs - arrivedMs;

  /// How long the screen took to show it, or null while unpainted.
  int? get toPaintMs => paintedMs == null ? null : paintedMs! - appendedMs;

  LatencySample painted(int at) => LatencySample(
    sequence: sequence,
    arrivedMs: arrivedMs,
    appendedMs: appendedMs,
    paintedMs: at,
  );
}

/// Where a note spends its time between the instrument and the staff.
///
/// A debug instrument, not a product one, and off in release builds. It exists
/// because "the notes feel delayed" has at least four possible causes, and the
/// difference between a 2 ms path to the transcript and an 80 ms path to the
/// screen decides which one is worth chasing.
final latencyProbeProvider =
    NotifierProvider<LatencyProbeNotifier, List<LatencySample>>(
      LatencyProbeNotifier.new,
    );

class LatencyProbeNotifier extends Notifier<List<LatencySample>> {
  /// How many samples to keep. A few attempts' worth.
  static const int _limit = 200;

  @override
  List<LatencySample> build() => const [];

  /// The clock every stage is stamped against.
  InputEventClock get _clock => ref.read(inputEventClockProvider);

  /// Records that a note reached the transcript.
  void appended({required int sequence, required int arrivedMs}) {
    if (kReleaseMode) return;
    state = [
      ...state.length >= _limit ? state.skip(1) : state,
      LatencySample(
        sequence: sequence,
        arrivedMs: arrivedMs,
        appendedMs: _clock(),
      ),
    ];
  }

  /// Records that the frame including everything up to [sequence] is painted.
  void painted(int sequence) {
    if (kReleaseMode || state.isEmpty) return;
    final at = _clock();
    state = [
      for (final sample in state)
        if (sample.sequence == sequence && sample.paintedMs == null)
          sample.painted(at)
        else
          sample,
    ];
  }

  /// Forgets everything measured so far.
  void clear() => state = const [];
}
