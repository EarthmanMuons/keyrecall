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
/// Recording is explicit rather than continuous. Live input is always visible,
/// so a learner can warm up, check the instrument, and settle their hands, and
/// none of it becomes part of an attempt: an exercise that has not begun cannot
/// have been played, and exploratory notes would otherwise make the attempt
/// look started and arrive in the alignment as extra notes.
///
/// The window opens at Ready, so the count-in is inside the attempt. Coming in
/// early is a fact about the performance rather than noise, and dropping those
/// notes would make an eager entry look like a missing one.
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
