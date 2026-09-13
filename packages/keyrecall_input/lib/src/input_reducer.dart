import 'input_integrity.dart';
import 'input_temporal_event.dart';
import 'input_temporal_state.dart';
import 'raw_input_envelope.dart';

/// Where an observation stands.
enum InputObservationPhase {
  /// Nothing is being observed. Raw input is discarded.
  idle,

  /// One continuous observation is open.
  observing,

  /// An integrity fault ended the observation. Raw input is discarded until
  /// [InputReducer.begin] opens a new one.
  faulted,
}

/// Whether a pedal reading counts as down. The MIDI convention.
const int _defaultSustainThreshold = 64;

const int _maxDataByte = 127;

/// The one interpretation of raw input.
///
/// Normalization, sounding state, source admission, and temporal continuity
/// are the same decision made once. Every earlier version of this had them in
/// separate places, which is how two authoritative representations came to
/// disagree about whether a pitch was sounding.
///
/// The governing rule is that an observation must be provable. The moment the
/// reducer cannot show that what it emitted was one continuous stream from one
/// instrument, it emits an [InputTemporalFaultEvent] and stops. Nothing after
/// that reaches the stream, even if the instrument resumes behaving perfectly,
/// until a caller explicitly opens a new observation with [begin].
///
/// It is not a Riverpod object and holds no subscriptions. Wiring a transport
/// to it, and deciding when an observation begins and ends, are the caller's.
class InputReducer {
  InputReducer({int sustainThreshold = _defaultSustainThreshold})
    : _sustainThreshold = sustainThreshold;

  final int _sustainThreshold;

  final Set<int> _pressed = {};
  final Set<int> _sustained = {};
  bool _pedalDown = false;

  InputSourceIdentity? _adopted;
  InputObservationPhase _phase = InputObservationPhase.idle;
  InputIntegrityFault? _fault;
  int _lastTimestampMs = 0;
  int _rejectedForeignCount = 0;

  /// The instrument whose input is admitted, or null while none is adopted.
  InputSourceIdentity? get adopted => _adopted;

  /// Where the observation stands.
  InputObservationPhase get phase => _phase;

  /// Whether an observation is open.
  bool get isObserving => _phase == InputObservationPhase.observing;

  /// What ended the observation, if a fault did.
  InputIntegrityFault? get fault => _fault;

  /// How many events were turned away for coming from another instrument.
  int get rejectedForeignCount => _rejectedForeignCount;

  /// Exactly what is sounding.
  InputTemporalSnapshot get snapshot => InputTemporalSnapshot(
    pressedNoteNumbers: _pressed,
    sustainedNoteNumbers: _sustained,
    pedalDown: _pedalDown,
  );

  /// The sounding state plus the fault that ended the observation, if any.
  InputTemporalState get observation => InputTemporalState(
    pressedNoteNumbers: {..._pressed},
    sustainedNoteNumbers: {..._sustained},
    pedalDown: _pedalDown,
    fault: _fault,
  );

  /// Restricts admitted input to [source].
  ///
  /// While nothing is adopted every source is admitted, because there is no
  /// instrument to tell them apart from. Once one is, everything else is
  /// turned away rather than faulting the observation: another keyboard in the
  /// room is not evidence that this one's stream broke.
  ///
  /// Adoption does not open or close an observation. A caller swapping
  /// instruments calls [begin] as well, since the notes on either side of the
  /// swap are not one performance.
  void adopt(InputSourceIdentity? source) => _adopted = source;

  /// Opens a fresh observation, discarding whatever the last one believed.
  ///
  /// The opening [InputTemporalResetEvent] reports silence, because an
  /// observation that has just started has not seen a key go down and cannot
  /// claim to know what is held.
  List<InputTemporalEvent> begin({required int timestampMs}) {
    _pressed.clear();
    _sustained.clear();
    _pedalDown = false;
    _fault = null;
    _phase = InputObservationPhase.observing;
    _lastTimestampMs = timestampMs;
    return [
      InputTemporalResetEvent(
        timestampMs: timestampMs,
        snapshot: InputTemporalSnapshot.silent,
      ),
    ];
  }

  /// A boundary that hands the current sounding state to a new consumer.
  ///
  /// For a listener attaching partway through: it needs the whole snapshot,
  /// which replaying the last event cannot give it. The observation continues,
  /// but the boundary is real, so anything measuring across it must not.
  ///
  /// Throws [StateError] when no observation is open.
  InputTemporalEvent resync({required int timestampMs}) {
    if (!isObserving) {
      throw StateError('cannot resync without an open observation');
    }
    _lastTimestampMs = _atLeastLast(timestampMs);
    return InputTemporalResetEvent(
      timestampMs: _lastTimestampMs,
      snapshot: snapshot,
    );
  }

  /// Ends the observation because its integrity cannot be vouched for.
  ///
  /// Idempotent: a source that errors and then closes faults once.
  List<InputTemporalEvent> fail(
    InputIntegrityFault fault, {
    required int timestampMs,
    String? detail,
  }) {
    if (_phase != InputObservationPhase.observing) return const [];
    _pressed.clear();
    _sustained.clear();
    _pedalDown = false;
    _fault = fault;
    _phase = InputObservationPhase.faulted;
    _lastTimestampMs = _atLeastLast(timestampMs);
    return [
      InputTemporalFaultEvent(
        timestampMs: _lastTimestampMs,
        fault: fault,
        detail: detail,
      ),
    ];
  }

  /// Admits one raw event, returning what it normalizes to.
  ///
  /// An empty result is the ordinary case for input that changes nothing: a
  /// repeated note-on for a key already down, a release of a key nobody
  /// pressed, a message from another instrument, a message KeyRecall does not
  /// consume.
  List<InputTemporalEvent> receive(RawInputEnvelope envelope) {
    if (!isObserving) return const [];

    if (!_admits(envelope.source)) {
      _rejectedForeignCount += 1;
      return const [];
    }

    final timestampMs = envelope.arrivalTimestampMs;
    if (timestampMs < _lastTimestampMs) {
      return fail(
        InputIntegrityFault.timestampRegression,
        timestampMs: _lastTimestampMs,
        detail: 'arrived at ${timestampMs}ms after ${_lastTimestampMs}ms',
      );
    }
    if (timestampMs < 0) {
      return fail(
        InputIntegrityFault.malformedInput,
        timestampMs: _lastTimestampMs,
        detail: 'negative arrival timestamp $timestampMs',
      );
    }

    final malformed = _malformation(envelope.message);
    if (malformed != null) {
      return fail(
        InputIntegrityFault.malformedInput,
        timestampMs: timestampMs,
        detail: malformed,
      );
    }

    _lastTimestampMs = timestampMs;
    return _apply(envelope.message, timestampMs);
  }

  bool _admits(InputSourceIdentity source) {
    final adopted = _adopted;
    return adopted == null || adopted == source;
  }

  /// What is wrong with [message], or null when nothing is.
  String? _malformation(RawInputMessage message) {
    switch (message.kind) {
      case RawInputKind.noteOn:
      case RawInputKind.noteOff:
        final note = message.note;
        final velocity = message.velocity;
        if (note == null || note < 0 || note > _maxDataByte) {
          return 'note $note outside 0..$_maxDataByte';
        }
        if (velocity == null || velocity < 0 || velocity > _maxDataByte) {
          return 'velocity $velocity outside 0..$_maxDataByte';
        }
        return null;
      case RawInputKind.sustain:
        final value = message.sustainValue;
        if (value == null || value < 0 || value > _maxDataByte) {
          return 'sustain value $value outside 0..$_maxDataByte';
        }
        return null;
      case RawInputKind.allNotesOff:
      case RawInputKind.other:
        return null;
    }
  }

  List<InputTemporalEvent> _apply(RawInputMessage message, int timestampMs) {
    switch (message.kind) {
      case RawInputKind.other:
        return const [];

      case RawInputKind.allNotesOff:
        _pressed.clear();
        _sustained.clear();
        return [
          InputTemporalResetEvent(
            timestampMs: timestampMs,
            snapshot: InputTemporalSnapshot(pedalDown: _pedalDown),
          ),
        ];

      case RawInputKind.sustain:
        final down = message.sustainValue! >= _sustainThreshold;
        if (down == _pedalDown) return const [];
        _pedalDown = down;
        if (!down) _sustained.clear();
        return [InputTemporalPedalEvent(timestampMs: timestampMs, down: down)];

      case RawInputKind.noteOn:
        // Velocity zero is how instruments spell a release.
        if (message.velocity == 0) {
          return _release(message.note!, 0, timestampMs);
        }
        // A repeated note-on for a key already down is an input no-op. A
        // reattack of a note the pedal was holding is not.
        if (!_pressed.add(message.note!)) return const [];
        _sustained.remove(message.note);
        return [
          InputTemporalNoteOnEvent(
            timestampMs: timestampMs,
            noteNumber: message.note!,
            velocity: message.velocity!,
          ),
        ];

      case RawInputKind.noteOff:
        return _release(message.note!, message.velocity!, timestampMs);
    }
  }

  /// Releases [note], if this reducer believes it was held.
  ///
  /// A release of a key nobody pressed changes nothing. Letting it through
  /// would let the pedal catch a note that never sounded, which is how
  /// sustained state came to contain pitches the event stream never reported.
  List<InputTemporalEvent> _release(int note, int velocity, int timestampMs) {
    if (!_pressed.remove(note)) return const [];
    if (_pedalDown) {
      _sustained.add(note);
    } else {
      _sustained.remove(note);
    }
    return [
      InputTemporalNoteOffEvent(
        timestampMs: timestampMs,
        noteNumber: note,
        velocity: velocity,
      ),
    ];
  }

  int _atLeastLast(int timestampMs) =>
      timestampMs < _lastTimestampMs ? _lastTimestampMs : timestampMs;
}
