import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import '../input/input.dart';

/// What has been played during the attempt on screen.
///
/// One note-on becomes one transcript note, spelled in the key the exercise
/// named. Note-offs, the pedal, and resets are not transcript events: the
/// transcript is what was played and in what order, and how long a key stayed
/// down is a question for a layer that measures.
///
/// Recording is explicit rather than continuous, so notes played while reading
/// the screen do not join an attempt that has not started.
final attemptTranscriptProvider =
    NotifierProvider<AttemptTranscriptNotifier, PerformanceTranscript>(
      AttemptTranscriptNotifier.new,
    );

class AttemptTranscriptNotifier extends Notifier<PerformanceTranscript> {
  /// The material being played, which is what spells an observation. Null when
  /// nothing is being recorded.
  TechnicalMaterial? _material;

  @override
  PerformanceTranscript build() {
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      final event = next.value;
      if (event != null) _record(event);
    }, fireImmediately: true);
    return PerformanceTranscript.empty;
  }

  /// Starts a fresh transcript for an attempt at [material].
  void start(TechnicalMaterial material) {
    _material = material;
    state = PerformanceTranscript.empty;
  }

  /// Stops recording, keeping what was played.
  void stop() => _material = null;

  void _record(InputTemporalEvent event) {
    final material = _material;
    if (material == null) return;
    if (event is! InputTemporalNoteOnEvent) return;

    state = state.appending(
      pitch: spellObservedPitch(event.noteNumber, material: material),
      timestampMs: event.timestampMs,
    );
  }
}
