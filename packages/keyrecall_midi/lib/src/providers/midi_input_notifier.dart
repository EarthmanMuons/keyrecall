import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';

import '../models/midi_connection.dart';
import '../models/midi_constants.dart';
import '../models/midi_device.dart';
import '../models/midi_message.dart';
import '../models/midi_source_message.dart';
import '../models/midi_transport_record.dart';
import 'midi_ble_service_provider.dart';
import 'midi_connection_notifier.dart';
import 'midi_device_manager.dart';

/// The MIDI input boundary: one reducer, one interpretation.
///
/// Everything the app believes about live MIDI comes from here. Sounding
/// state, the normalized event stream, and whether the observation can still
/// be trusted are three readings of one [InputReducer] rather than three
/// listeners racing the same raw stream to their own conclusions.
final midiInputProvider = NotifierProvider<MidiInputNotifier, MidiInputState>(
  MidiInputNotifier.new,
);

/// What the input boundary currently knows.
@immutable
class MidiInputState {
  /// What is sounding on the adopted instrument.
  final InputTemporalSnapshot snapshot;

  /// What ended the observation, when one has ended.
  final InputIntegrityFault? fault;

  /// Whether a continuous observation is open.
  final bool isObserving;

  /// The instrument and transport session input is admitted from.
  ///
  /// Null while nothing is adopted, which is when nothing is admitted.
  final InputSourceIdentity? adopted;

  /// How many messages were turned away for coming from another instrument.
  final int rejectedForeignMessages;

  /// What the adopted instrument's clock has been measured to be.
  ///
  /// The mapper's own reading, taken from the reducer that is timing the
  /// stream, rather than a second detector's opinion of traffic that includes
  /// sources this one turned away.
  final ClockDomainObservation clockObservation;

  /// Where that clock stands, which is what decides whether anything is timed.
  final PerformanceClockPhase clockPhase;

  const MidiInputState({
    required this.snapshot,
    required this.isObserving,
    this.adopted,
    this.fault,
    this.rejectedForeignMessages = 0,
    this.clockObservation = ClockDomainObservation.none,
    this.clockPhase = PerformanceClockPhase.detecting,
  });
}

class MidiInputNotifier extends Notifier<MidiInputState> {
  final InputReducer _reducer = InputReducer(
    sustainThreshold: MidiConstants.sustainPedalThreshold,
  );
  final StreamController<InputTemporalEvent> _events =
      StreamController<InputTemporalEvent>.broadcast(sync: true);

  /// The passive view of the raw boundary, for characterizing transports.
  final StreamController<MidiTransportRecord> _transport =
      StreamController<MidiTransportRecord>.broadcast(sync: true);
  int _records = 0;

  late final InputEventClock _clock;
  StreamSubscription<MidiSourceMessage>? _messages;

  /// The instrument every session since adoption has been listening for.
  MidiDevice? _instrument;

  /// The observation epoch input is currently admitted into.
  ///
  /// The transport reports a device id, never which link delivered a message,
  /// so a reconnect that reuses the id is indistinguishable at the wire. This
  /// names the epoch instead, so the adopted identity changes when the same
  /// instrument is readopted and a trace can say which side of a boundary a
  /// message fell on.
  String _session = 'midi-0';
  int _sessionsOpened = 0;

  /// Whether the transport can still deliver.
  ///
  /// False once its stream ends, which the subscription cannot come back
  /// from. Tracked rather than inferred from the reducer, because an
  /// observation being closed says nothing about whether the transport could
  /// open another one.
  bool _transportAlive = false;

  /// Whether observation was deliberately put down.
  ///
  /// Backgrounding sets this, and only coming back clears it. An error
  /// arriving in between must not take it for an invitation to start
  /// observing again.
  bool _suspended = false;

  /// Whether [build] has returned, and so whether [state] can be assigned.
  bool _isBuilt = false;

  /// The normalized stream, live for as long as this notifier is.
  ///
  /// Broadcast, and it carries no history: a consumer attaching partway
  /// through asks for [openObservation] first, so it starts from a snapshot
  /// rather than from whatever happens to arrive next.
  Stream<InputTemporalEvent> get events => _events.stream;

  /// Everything the transport did, ahead of admission and normalization.
  ///
  /// Deliveries include the ones the boundary went on to reject, since a
  /// dataset filtered to what was accepted cannot explain what was not.
  /// Nothing is recorded while nobody is listening, and listening changes
  /// nothing: a listener must only take what it is handed, since this is
  /// delivered synchronously on the message path.
  ///
  /// For characterization, not for running on. What the app plays from is
  /// [events].
  Stream<MidiTransportRecord> get transportRecords => _transport.stream;

  @override
  MidiInputState build() {
    // Read rather than watched: both are container-lifetime constants, and
    // rebuilding this notifier would close the stream its consumers hold.
    _clock = ref.read(inputEventClockProvider);
    ref.onDispose(() {
      unawaited(_messages?.cancel());
      unawaited(_events.close());
      unawaited(_transport.close());
    });

    _listen();
    _beginEpoch();

    // A connection that comes, goes, or is retried is a boundary in the
    // observation whether or not any note crossed it.
    ref.listen<MidiConnectionPhase>(
      midiConnectionStateProvider.select((state) => state.phase),
      (previous, next) {
        if (previous == next) return;
        _beginEpoch();
      },
    );

    // Adopting an instrument is what makes every other live source foreign.
    ref.listen<MidiDevice?>(
      midiDeviceManagerProvider.select((state) => state.connectedDevice),
      (previous, next) {
        if (previous?.id == next?.id) return;
        _instrument = next;
        _beginEpoch();
      },
      fireImmediately: true,
    );

    _isBuilt = true;
    return _currentState();
  }

  /// Ends the observation because nothing can vouch for it across a gap.
  ///
  /// Backgrounding is the case that matters. The link is deliberately left up,
  /// because whether to keep the transport connected is a separate decision
  /// from whether KeyRecall can still claim to be watching.
  void suspendObservation() {
    _suspended = true;
    _emit(
      _reducer.fail(
        InputIntegrityFault.observationGap,
        timestampMs: _clock(),
        detail: 'observation suspended',
      ),
    );
  }

  /// Opens a fresh observation after a suspension.
  ///
  /// Coming back to the foreground is an establishment event, so it opens a
  /// new observation rather than resuming the one that was suspended.
  void resumeObservation() {
    _suspended = false;
    if (_reducer.isObserving) return;
    _beginEpoch();
  }

  /// Where the observation stands, for a consumer attaching now.
  ///
  /// Never opens one. A consumer subscribing says nothing about whether a
  /// failed transport recovered, and an observation that reopened because
  /// something started watching would be the claim the terminal-fault rule
  /// exists to refuse. A consumer attaching while the observation is closed is
  /// handed the fault instead.
  InputTemporalEvent openObservation() {
    final opening = _reducer.opening(timestampMs: _clock());
    _record(
      (sequence, at) => MidiTransportBoundary(
        sequence: sequence,
        arrivalTimestampMs: at,
        kind: MidiTransportBoundaryKind.consumerAttached,
        adopted: _reducer.adopted,
        fault: _reducer.fault,
      ),
    );
    return opening;
  }

  /// Opens a fresh observation, leaving the transport alone.
  ///
  /// The only thing that opens one. Every caller is an actual establishment
  /// event: the app starting, a connection transition, adopting an instrument,
  /// coming back to the foreground, or a failed source being taken up again.
  ///
  /// It does not touch the subscription. An observation epoch is a fact about
  /// what KeyRecall can vouch for; a subscription is a fact about the
  /// transport, and the plugin's stream is the same stream throughout. See
  /// `docs/system/input.md`.
  void _beginEpoch() {
    // Three separate facts, and an epoch needs all of them: the transport can
    // deliver, nobody has put observation down, and an instrument is adopted.
    // None of them follows from the reducer's phase.
    if (!_canObserve) {
      // Whatever was open cannot continue either: an instrument that went
      // away is not still holding the keys it was holding.
      _emit(
        _reducer.fail(
          InputIntegrityFault.observationGap,
          timestampMs: _clock(),
          detail: _instrument == null
              ? 'no instrument adopted'
              : _suspended
              ? 'observation suspended'
              : 'the MIDI source ended',
        ),
      );
      return;
    }
    final session = 'midi-${++_sessionsOpened}';
    _session = session;
    _reducer.adopt(_identityOf(_instrument, session));
    _record(
      (sequence, at) => MidiTransportBoundary(
        sequence: sequence,
        arrivalTimestampMs: at,
        kind: MidiTransportBoundaryKind.sessionOpened,
        session: session,
        adopted: _reducer.adopted,
      ),
    );
    _emit(_reducer.begin(timestampMs: _clock()));
  }

  /// Whether an observation can be opened at all.
  bool get _canObserve => _transportAlive && !_suspended && _instrument != null;

  /// Attaches to the transport, once, for as long as this notifier lives.
  void _listen() {
    _transportAlive = true;
    _messages = ref
        .read(midiBleServiceProvider)
        .onMidiMessages
        .listen(
          _receive,
          // An error is not a quiet gap in the input: the observation ends
          // and a new one opens. The subscription does not cancel on error,
          // so a transient failure costs an epoch rather than the instrument.
          onError: (Object error, StackTrace _) {
            if (!kReleaseMode) debugPrint('MIDI message error: $error');
            _emit(
              _reducer.fail(
                InputIntegrityFault.sourceFailure,
                timestampMs: _clock(),
                detail: '$error',
              ),
            );
            _beginEpoch();
          },
          // Nothing is left to observe, and this subscription cannot deliver
          // again. Recovery takes an actual replacement rather than somebody
          // asking for one.
          onDone: () {
            _transportAlive = false;
            _emit(
              _reducer.fail(
                InputIntegrityFault.sourceClosed,
                timestampMs: _clock(),
                detail: 'the MIDI source ended',
              ),
            );
          },
          cancelOnError: false,
        );
  }

  void _receive(MidiSourceMessage source) {
    final turnedAway = _reducer.rejectedForeignCount;
    final clock = _reducer.clock.observation;
    final phase = _reducer.clock.phase;
    final envelope = _envelope(source);
    // Ahead of anything deciding what it means: a message the boundary goes
    // on to reject is one the dataset may have to explain a discontinuity
    // with.
    _record(
      (sequence, at) => MidiTransportDelivery(
        sequence: sequence,
        arrivalTimestampMs: at,
        envelope: envelope,
        source: source,
        live: true,
      ),
    );
    _emit(_reducer.receive(envelope));
    // Not every delivery that changes what is known produces an event. A
    // message from another instrument is the only sign that something else is
    // playing into the same transport, and a controller message can measure
    // the clock or fail its timeline without moving a single key.
    if (_reducer.rejectedForeignCount != turnedAway ||
        _reducer.clock.observation != clock ||
        _reducer.clock.phase != phase) {
      _publish();
    }
  }

  /// Every channel of the adopted instrument is one keyboard.
  ///
  /// A stage piano splitting its hands across two channels is still one player
  /// playing, and nothing KeyRecall measures is per-channel. The channel is
  /// carried on the envelope so a later policy can narrow this without
  /// re-plumbing the boundary.
  RawInputEnvelope _envelope(MidiSourceMessage source) => RawInputEnvelope(
    source: InputSourceIdentity(
      deviceId: source.deviceId,
      transport: source.transport.name,
      sessionId: _session,
    ),
    channel: source.message.channel,
    message: _rawMessage(source.message),
    transportTimestamp: source.transportTimestamp,
    arrivalTimestampMs: _clock(),
  );

  static RawInputMessage _rawMessage(MidiMessage message) {
    switch (message.type) {
      case MidiMessageType.noteOn:
        return RawInputMessage(
          kind: RawInputKind.noteOn,
          note: message.note,
          velocity: message.velocity,
        );
      case MidiMessageType.noteOff:
        return RawInputMessage(
          kind: RawInputKind.noteOff,
          note: message.note,
          velocity: message.velocity,
        );
      case MidiMessageType.controlChange:
        if (MidiConstants.endsAllNotes(message.ccNumber)) {
          return const RawInputMessage(kind: RawInputKind.allNotesOff);
        }
        if (message.ccNumber == MidiConstants.ccSustainPedal) {
          return RawInputMessage(
            kind: RawInputKind.sustain,
            sustainValue: message.ccValue,
          );
        }
        return const RawInputMessage(kind: RawInputKind.other);
      case MidiMessageType.programChange:
      case MidiMessageType.pitchBend:
      case MidiMessageType.unknown:
        return const RawInputMessage(kind: RawInputKind.other);
    }
  }

  static InputSourceIdentity? _identityOf(MidiDevice? device, String session) =>
      device == null
      ? null
      : InputSourceIdentity(
          deviceId: device.id,
          transport: device.transport.name,
          sessionId: session,
        );

  void _emit(List<InputTemporalEvent> events) {
    if (events.isEmpty || _events.isClosed) return;
    for (final event in events) {
      _events.add(event);
      if (event is InputTemporalFaultEvent) {
        _record(
          (sequence, at) => MidiTransportBoundary(
            sequence: sequence,
            arrivalTimestampMs: at,
            kind: MidiTransportBoundaryKind.observationFailed,
            adopted: _reducer.adopted,
            fault: event.fault,
            detail: event.detail,
          ),
        );
      }
    }
    _publish();
  }

  /// Hands [make] a sequence number and the clock, when anything is watching.
  void _record(
    MidiTransportRecord Function(int sequence, int arrivalTimestampMs) make,
  ) {
    if (!_transport.hasListener || _transport.isClosed) return;
    _transport.add(make(_records++, _clock()));
  }

  /// Nothing may assign state until build has returned one.
  void _publish() {
    if (_isBuilt) state = _currentState();
  }

  MidiInputState _currentState() => MidiInputState(
    snapshot: _reducer.snapshot,
    isObserving: _reducer.isObserving,
    adopted: _reducer.adopted,
    fault: _reducer.fault,
    rejectedForeignMessages: _reducer.rejectedForeignCount,
    clockObservation: _reducer.clock.observation,
    clockPhase: _reducer.clock.phase,
  );
}
