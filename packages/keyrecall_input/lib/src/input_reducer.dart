import 'input_integrity.dart';
import 'input_temporal_event.dart';
import 'input_temporal_state.dart';
import 'performance_clock_mapper.dart';
import 'performance_timing.dart';
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

/// The highest channel an instrument can address. The MIDI convention.
const int _maxChannel = 15;

/// What one channel of an instrument is holding.
///
/// Notes and the pedal are owned per channel because that is where an
/// instrument owns them: a release on one channel ends that channel's hold and
/// says nothing about the same pitch held on another.
class _ChannelState {
  final Set<int> pressed = {};
  final Set<int> sustained = {};
  bool pedalDown = false;
}

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
/// Ownership is tracked per channel; the product stream is one keyboard.
/// Those are separate decisions. Merging channels for measurement is a
/// deliberate policy, and it does not require forgetting which channel is
/// holding what: a stage piano splitting its hands across two channels is one
/// player playing, but a release on one hand's channel must not damp the
/// other's note.
///
/// It is not a Riverpod object and holds no subscriptions. Wiring a transport
/// to it, and deciding when an observation begins and ends, are the caller's.
class InputReducer {
  /// [clock] reads the instrument's own timestamps. The reducer decides when
  /// it is consulted and never how it answers, which is why the arithmetic
  /// lives in [PerformanceClockMapper] and not here.
  InputReducer({
    int sustainThreshold = _defaultSustainThreshold,
    PerformanceClockMapper? clock,
  }) : _sustainThreshold = sustainThreshold,
       _clock = clock ?? PerformanceClockMapper();

  final int _sustainThreshold;
  final PerformanceClockMapper _clock;

  /// Per-channel ownership. The null key is a source that reports no channel.
  final Map<int?, _ChannelState> _channels = {};

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

  /// What has been read about the instrument's own clock.
  PerformanceClockMapper get clock => _clock;

  /// Exactly what is sounding, across every channel.
  InputTemporalSnapshot get snapshot => _aggregate().snapshot;

  /// The sounding state plus the fault that ended the observation, if any.
  InputTemporalState get observation {
    final aggregate = _aggregate();
    return InputTemporalState(
      pressedNoteNumbers: aggregate.pressedNoteNumbers,
      sustainedNoteNumbers: aggregate.sustainedNoteNumbers,
      pedalDown: aggregate.pedalDown,
      fault: _fault,
    );
  }

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
    _channels.clear();
    _clock.restart();
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
  /// Throws [StateError] when no observation is open. Use [opening] for a
  /// consumer that has to be told where things stand either way.
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

  /// Where the observation stands, for a consumer attaching now.
  ///
  /// A reset carrying the snapshot while one is open, and otherwise the fault
  /// that closed it. This never opens one: a consumer subscribing is not
  /// evidence that a failed source recovered, and an observation that resumed
  /// because somebody started watching would be exactly the claim the
  /// terminal-fault rule exists to refuse.
  InputTemporalEvent opening({required int timestampMs}) {
    if (isObserving) return resync(timestampMs: timestampMs);
    _lastTimestampMs = _atLeastLast(timestampMs);
    return InputTemporalFaultEvent(
      timestampMs: _lastTimestampMs,
      fault: _fault ?? InputIntegrityFault.observationGap,
      detail: _fault == null ? 'no observation has been opened' : null,
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
    _channels.clear();
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
  /// repeated note-on for a key the same channel already holds, a release of a
  /// key nobody pressed, a pitch another channel is still holding, a message
  /// from another instrument, a message KeyRecall does not consume.
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

    final malformed = _malformation(envelope);
    if (malformed != null) {
      return fail(
        InputIntegrityFault.malformedInput,
        timestampMs: timestampMs,
        detail: malformed,
      );
    }

    _lastTimestampMs = timestampMs;
    // One reading per delivery, whatever it normalizes to. Every event a
    // delivery produces was played at the same moment, and asking twice would
    // advance a timeline for one keyboard event.
    final source = envelope.source;
    final timing = _clock.map(
      session: '${source.transport}/${source.deviceId}/${source.sessionId}',
      arrivalMs: timestampMs,
      timestamp: envelope.transportTimestamp,
    );
    return _apply(envelope, timestampMs, timing);
  }

  bool _admits(InputSourceIdentity source) {
    final adopted = _adopted;
    return adopted == null || adopted == source;
  }

  /// What is wrong with [envelope], or null when nothing is.
  String? _malformation(RawInputEnvelope envelope) {
    final channel = envelope.channel;
    if (channel != null && (channel < 0 || channel > _maxChannel)) {
      return 'channel $channel outside 0..$_maxChannel';
    }

    final message = envelope.message;
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

  List<InputTemporalEvent> _apply(
    RawInputEnvelope envelope,
    int timestampMs,
    PerformanceTiming timing,
  ) {
    final message = envelope.message;
    if (message.kind == RawInputKind.other) return const [];

    // All-notes-off is an administrative boundary rather than playing, and it
    // is one whether or not anything happened to be sounding when it arrived.
    if (message.kind == RawInputKind.allNotesOff) {
      for (final channel in _channels.values) {
        channel.pressed.clear();
        channel.sustained.clear();
      }
      return [
        InputTemporalResetEvent(
          timestampMs: timestampMs,
          snapshot: _aggregate().snapshot,
        ),
      ];
    }

    final before = _aggregate();
    _own(envelope.channel, message);
    return _eventsToward(before, message, timestampMs, timing);
  }

  /// Applies [message] to the channel that owns it.
  void _own(int? channel, RawInputMessage message) {
    final owner = _channels.putIfAbsent(channel, _ChannelState.new);
    switch (message.kind) {
      case RawInputKind.sustain:
        final down = message.sustainValue! >= _sustainThreshold;
        if (down == owner.pedalDown) return;
        owner.pedalDown = down;
        if (!down) owner.sustained.clear();
      case RawInputKind.noteOn:
        // Velocity zero is how instruments spell a release.
        if (message.velocity == 0) {
          _releaseOn(owner, message.note!);
          return;
        }
        // A repeated note-on for a key this channel already holds is an input
        // no-op. A reattack of a note the pedal was holding is not.
        owner.pressed.add(message.note!);
        owner.sustained.remove(message.note);
      case RawInputKind.noteOff:
        _releaseOn(owner, message.note!);
      case RawInputKind.allNotesOff:
      case RawInputKind.other:
        return;
    }
  }

  /// Ends [owner]'s hold on [note], if it had one.
  ///
  /// A release of a key nobody pressed changes nothing. Letting it through
  /// would let the pedal catch a note that never sounded, which is how
  /// sustained state came to contain pitches the event stream never reported.
  void _releaseOn(_ChannelState owner, int note) {
    if (!owner.pressed.remove(note)) return;
    if (owner.pedalDown) {
      owner.sustained.add(note);
    } else {
      owner.sustained.remove(note);
    }
  }

  /// What is sounding on the one keyboard every channel adds up to.
  ///
  /// A pitch held on any channel is held: that is what makes a release on one
  /// channel unable to damp another's note. A pitch both held and sustained is
  /// held, since the hold is what is keeping it down.
  InputTemporalState _aggregate() {
    final pressed = <int>{};
    final sustained = <int>{};
    var pedalDown = false;
    for (final channel in _channels.values) {
      pressed.addAll(channel.pressed);
      sustained.addAll(channel.sustained);
      pedalDown = pedalDown || channel.pedalDown;
    }
    sustained.removeAll(pressed);
    return InputTemporalState(
      pressedNoteNumbers: pressed,
      sustainedNoteNumbers: sustained,
      pedalDown: pedalDown,
    );
  }

  /// The events that carry the aggregate keyboard from [before] to now.
  ///
  /// Derived from the difference rather than from the message, and then
  /// checked by replaying them: if the normalized vocabulary cannot express
  /// the transition, the result is a reset carrying the whole snapshot. That
  /// is what makes "replaying the stream reproduces the snapshot" structural
  /// instead of an argument about cases. Mixed pedal positions across channels
  /// are the transition that needs it.
  List<InputTemporalEvent> _eventsToward(
    InputTemporalState before,
    RawInputMessage message,
    int timestampMs,
    PerformanceTiming timing,
  ) {
    final after = _aggregate();
    if (before == after) return const [];

    // One message moves at most one note in or out of the aggregate, so the
    // velocity it reports is the velocity of whichever note appears here.
    final released =
        before.pressedNoteNumbers.difference(after.pressedNoteNumbers).toList()
          ..sort();
    final struck =
        after.pressedNoteNumbers.difference(before.pressedNoteNumbers).toList()
          ..sort();

    final events = <InputTemporalEvent>[
      if (before.pedalDown != after.pedalDown)
        InputTemporalPedalEvent(
          timestampMs: timestampMs,
          down: after.pedalDown,
          timing: timing,
        ),
      for (final note in released)
        InputTemporalNoteOffEvent(
          timestampMs: timestampMs,
          noteNumber: note,
          velocity: message.velocity ?? 0,
          timing: timing,
        ),
      for (final note in struck)
        InputTemporalNoteOnEvent(
          timestampMs: timestampMs,
          noteNumber: note,
          velocity: message.velocity ?? 1,
          timing: timing,
        ),
    ];

    var replayed = before;
    for (final event in events) {
      replayed = replayed.applying(event);
    }
    if (replayed == after) return events;

    return [
      InputTemporalResetEvent(
        timestampMs: timestampMs,
        snapshot: after.snapshot,
      ),
    ];
  }

  int _atLeastLast(int timestampMs) =>
      timestampMs < _lastTimestampMs ? _lastTimestampMs : timestampMs;
}
