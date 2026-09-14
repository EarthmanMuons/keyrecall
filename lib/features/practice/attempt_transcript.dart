import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_journal/keyrecall_journal.dart';

import '../input/input.dart';
import 'latency_probe.dart';

/// What has been played during the attempt on screen.
///
/// One note-on becomes one transcript note, spelled in the key the exercise
/// named. Note-offs and the pedal are not transcript events. A reset interrupts
/// the capture because the notes on either side are not one observation, and
/// an integrity fault interrupts it because there is no longer any reason to
/// believe the notes already captured came from one.
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

  /// Why the input boundary stopped vouching for the capture, when that is
  /// what interrupted it. Null for an ordinary observation boundary.
  final InputIntegrityFault? fault;

  /// Which recording produced this, or zero when no attempt did.
  ///
  /// What was played outlives the attempt that played it, so between attempts
  /// this holds notes and a disposition belonging to the one before. An
  /// attempt reads only the capture it started: without that, a screen that
  /// has not begun recording shows the last attempt's notes and acts on the
  /// interruption that ended it.
  final int recording;

  const AttemptCapture({
    required this.transcript,
    this.isInterrupted = false,
    this.fault,
    this.recording = 0,
  });

  /// Nothing recorded, by nobody.
  static final AttemptCapture none = AttemptCapture(
    transcript: PerformanceTranscript.empty,
  );

  /// Whether [recording] is what produced this capture.
  bool belongsTo(int? recording) =>
      recording != null && recording != 0 && recording == this.recording;

  int get length => transcript.length;
  bool get isEmpty => transcript.isEmpty;
  bool get isNotEmpty => transcript.isNotEmpty;
  List<PlayedNote> get notes => transcript.notes;
}

/// An attempt, as it ended.
///
/// The way it ended and what was played, taken together at the instant
/// recording stopped. They are one attempt's terminal disposition and its
/// evidence, and they travel as one because deriving the second from the
/// provider when the first arrives reads whatever is in it by then: an
/// interrupted attempt was once recommitted as one nobody played, because the
/// capture had been discarded between the two reads.
@immutable
class AttemptCompletion {
  /// Which of the ways an attempt can end this was.
  final AttemptTermination termination;

  /// What was played, as it stood when the attempt ended.
  final AttemptCapture capture;

  const AttemptCompletion({required this.termination, required this.capture});

  /// Nothing played, however the attempt ended.
  AttemptCompletion.unplayed(this.termination) : capture = AttemptCapture.none;

  /// What was played.
  PerformanceTranscript get transcript => capture.transcript;

  /// Whether this attempt lost its input, however that reached here.
  ///
  /// Two readings of one fact, and either saying so settles it. The capture
  /// holds what the input boundary observed; the termination holds what the
  /// screen closed on. A caller that only had one of them would have to guess.
  bool get isInterrupted =>
      capture.isInterrupted ||
      termination == AttemptTermination.inputInterrupted;

  /// Why the input boundary stopped vouching for it, where it said.
  InputIntegrityFault? get fault => capture.fault;
}

class AttemptTranscriptNotifier extends Notifier<AttemptCapture> {
  /// The material being played, which is what spells an observation. Null when
  /// nothing is being recorded.
  TechnicalMaterial? _material;

  /// Names each recording, so an attempt can tell its capture from the last.
  int _recordings = 0;

  /// Names each live input observation, and is null while none is.
  ///
  /// A separate question from [_recordings]: that one says which attempt owns
  /// a capture, this one says which uninterrupted observation supplied it.
  /// Tracked whether or not anything is recording, because a source that fails
  /// between attempts is the case this exists for: nothing else would arrive
  /// to say so before the next attempt closed as ordinary playing.
  int? _observation;
  int _observations = 0;

  /// What closed the last observation, for a recording that starts after it.
  InputIntegrityFault? _lastFault;

  /// Whether the stream has said anything about its lifecycle yet.
  ///
  /// Until it has, the source's own state is what this knows. After it has,
  /// the events are: they come from the same reducer the source answers from,
  /// and they are the more recent word.
  bool _heardLifecycle = false;

  /// When the last accepted note arrived, so continuity is checked before the
  /// transcript is asked to hold something it would refuse.
  int _lastTimestampMs = 0;

  @override
  AttemptCapture build() {
    // Where the source says it stands, before any event arrives. The shared
    // stream hands a late subscriber the event it last delivered, which may be
    // a note, and a note is not a lifecycle fact.
    _adopt(ref.read(inputObservationProvider));
    // Only actual data notifications. An AsyncError keeps the previous value,
    // so reading `.value` past a failure re-delivers the last note and writes
    // it into the transcript a second time.
    ref.listen<AsyncValue<InputTemporalEvent>>(inputTemporalEventsProvider, (
      _,
      next,
    ) {
      switch (next) {
        case AsyncData(:final value):
          _observe(value);
          _record(value);
        case AsyncError(:final error):
          _heardLifecycle = true;
          _observation = null;
          _lastFault = InputIntegrityFault.sourceFailure;
          _interrupt(
            InputIntegrityFault.sourceFailure,
            detail: error.toString(),
          );
        case _:
          break;
      }
    }, fireImmediately: true);
    return AttemptCapture(transcript: PerformanceTranscript.empty);
  }

  /// Starts a fresh transcript for an attempt at [material].
  ///
  /// Returns the recording's name, which is what the attempt identifies its
  /// own capture by.
  int start(TechnicalMaterial material) {
    _lastTimestampMs = 0;
    _recordings += 1;
    // Asked again rather than remembered: nothing guarantees an event arrived
    // between building and starting, and the source knows.
    _adopt(ref.read(inputObservationProvider));
    // A recording belongs to one live observation. Starting one while nothing
    // is being observed has no observation to belong to, and no later event is
    // coming to say so.
    final observation = _observation;
    _material = observation == null ? null : material;
    state = AttemptCapture(
      transcript: PerformanceTranscript.empty,
      recording: _recordings,
      isInterrupted: observation == null,
      fault: observation == null ? _lastFault : null,
    );
    return _recordings;
  }

  /// Whether a live observation is available to record.
  bool get isObservationLive => _observation != null;

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
    _lastTimestampMs = 0;
    state = AttemptCapture.none;
  }

  /// Ends the current recording the way the input boundary would, for a test
  /// that needs the disposition without a source to break.
  @visibleForTesting
  void interruptForTest(InputIntegrityFault fault) => _interrupt(fault);

  /// Takes the source's word for where its observation stands.
  ///
  /// Only when it says something this has not already heard from the stream: a
  /// fault the events carried stays a fault until an event says otherwise.
  void _adopt(InputObservationState source) {
    if (_heardLifecycle) return;
    if (source.isLive) {
      _observation = ++_observations;
      return;
    }
    _observation = null;
    _lastFault = source.fault;
  }

  /// Follows the health of the input, recording or not.
  void _observe(InputTemporalEvent event) {
    switch (event) {
      case InputTemporalResetEvent():
        _heardLifecycle = true;
        _observation = ++_observations;
        _lastFault = null;
      case InputTemporalFaultEvent(:final fault):
        _heardLifecycle = true;
        _observation = null;
        _lastFault = fault;
      case _:
        break;
    }
  }

  void _record(InputTemporalEvent event) {
    final material = _material;
    if (material == null) return;
    if (event is InputTemporalFaultEvent) {
      _interrupt(event.fault, detail: event.detail);
      return;
    }
    // A reset opens the next observation, and a recording belongs to the one
    // it started in. Continuing under the new one would let an attempt span a
    // boundary while looking live at both ends.
    if (event is InputTemporalResetEvent) {
      _interrupt(null);
      return;
    }
    if (event is! InputTemporalNoteOnEvent) return;

    // The reducer already refuses to emit time running backward. Checking it
    // again here is what keeps a violation from reaching a transcript that
    // would throw, dropping the note and leaving the capture measurable.
    if (event.timestampMs < _lastTimestampMs) {
      _interrupt(InputIntegrityFault.timestampRegression);
      return;
    }

    final sequence = state.length;
    _lastTimestampMs = event.timestampMs;
    state = AttemptCapture(
      transcript: state.transcript.appending(
        pitch: spellObservedPitch(event.noteNumber, material: material),
        timestampMs: event.timestampMs,
        performanceTimeUs: event.performanceTimeUs,
      ),
      recording: state.recording,
    );
    ref
        .read(latencyProbeProvider.notifier)
        .appended(sequence: sequence, arrivedMs: event.timestampMs);
  }

  /// Closes the capture, keeping what was already played.
  ///
  /// Terminal: nothing reopens a capture whose integrity is in doubt, so a
  /// later note belongs to no attempt rather than to this one.
  void _interrupt(InputIntegrityFault? fault, {String? detail}) {
    if (_material == null) return;
    _material = null;
    if (detail != null && !kReleaseMode) {
      debugPrint('Attempt capture interrupted: ${fault?.name} ($detail)');
    }
    state = AttemptCapture(
      transcript: state.transcript,
      isInterrupted: true,
      fault: fault,
      recording: state.recording,
    );
  }
}
