import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import '../input/input.dart';
import 'latency_probe.dart';

/// What has been played during the attempt on screen.
///
/// One note-on becomes one transcript note, spelled in the key the exercise
/// named. Note-offs and the pedal are not transcript events. A reset interrupts
/// the capture because the notes on either side are not one observation.
///
/// Recording is explicit rather than continuous. Live input is always visible,
/// so a learner can warm up, check the instrument, and settle their hands, and
/// none of it becomes part of an attempt: an exercise that has not begun cannot
/// have been played, and exploratory notes would otherwise make the attempt
/// look started and arrive in the alignment as extra notes.
///
/// The window opens after the count-in. Until that downbeat the exercise is
/// presented but no performance is being observed.
final attemptTranscriptProvider =
    NotifierProvider<AttemptTranscriptNotifier, AttemptCapture>(
      AttemptTranscriptNotifier.new,
    );

@immutable
class AttemptCapture {
  final PerformanceTranscript transcript;
  final bool isInterrupted;

  const AttemptCapture({required this.transcript, this.isInterrupted = false});

  int get length => transcript.length;
  bool get isEmpty => transcript.isEmpty;
  bool get isNotEmpty => transcript.isNotEmpty;
  List<PlayedNote> get notes => transcript.notes;
}

class AttemptTranscriptNotifier extends Notifier<AttemptCapture> {
  /// The material being played, which is what spells an observation. Null when
  /// nothing is being recorded.
  TechnicalMaterial? _material;

  @override
  AttemptCapture build() {
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      final event = next.value;
      if (event != null) _record(event);
    }, fireImmediately: true);
    return AttemptCapture(transcript: PerformanceTranscript.empty);
  }

  /// Starts a fresh transcript for an attempt at [material].
  void start(TechnicalMaterial material) {
    _material = material;
    state = AttemptCapture(transcript: PerformanceTranscript.empty);
  }

  /// Stops recording, keeping what was played.
  ///
  /// What was played outlives the attempt on purpose: closing it reads the
  /// transcript after recording has stopped. It belongs to that attempt and
  /// nothing else, which is what [discard] is for.
  void stop() => _material = null;

  /// Forgets the last attempt's transcript.
  ///
  /// Between attempts there is a window where recording has stopped but the
  /// notes are still here, and anything that reads them in that window is
  /// reading the wrong attempt.
  void discard() {
    _material = null;
    state = AttemptCapture(transcript: PerformanceTranscript.empty);
  }

  void _record(InputTemporalEvent event) {
    final material = _material;
    if (material == null) return;
    if (event is InputTemporalResetEvent) {
      _material = null;
      state = AttemptCapture(transcript: state.transcript, isInterrupted: true);
      return;
    }
    if (event is! InputTemporalNoteOnEvent) return;

    final sequence = state.length;
    state = AttemptCapture(
      transcript: state.transcript.appending(
        pitch: spellObservedPitch(event.noteNumber, material: material),
        timestampMs: event.timestampMs,
      ),
    );
    ref
        .read(latencyProbeProvider.notifier)
        .appended(sequence: sequence, arrivedMs: event.timestampMs);
  }
}
