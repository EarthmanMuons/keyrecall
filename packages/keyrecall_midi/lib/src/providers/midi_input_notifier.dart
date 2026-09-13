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

  /// How many messages were turned away for coming from another instrument.
  final int rejectedForeignMessages;

  const MidiInputState({
    required this.snapshot,
    required this.isObserving,
    this.fault,
    this.rejectedForeignMessages = 0,
  });
}

class MidiInputNotifier extends Notifier<MidiInputState> {
  final InputReducer _reducer = InputReducer(
    sustainThreshold: MidiConstants.sustainPedalThreshold,
  );
  final StreamController<InputTemporalEvent> _events =
      StreamController<InputTemporalEvent>.broadcast(sync: true);

  late final InputEventClock _clock;
  StreamSubscription<MidiSourceMessage>? _messages;

  /// Whether [build] has returned, and so whether [state] can be assigned.
  bool _isBuilt = false;

  /// The normalized stream, live for as long as this notifier is.
  ///
  /// Broadcast, and it carries no history: a consumer attaching partway
  /// through asks for [openObservation] first, so it starts from a snapshot
  /// rather than from whatever happens to arrive next.
  Stream<InputTemporalEvent> get events => _events.stream;

  @override
  MidiInputState build() {
    // Read rather than watched: both are container-lifetime constants, and
    // rebuilding this notifier would close the stream its consumers hold.
    _clock = ref.read(inputEventClockProvider);
    ref.onDispose(() {
      unawaited(_messages?.cancel());
      unawaited(_events.close());
    });

    _subscribe(ref.read(midiBleServiceProvider).onMidiMessages);
    _emit(_reducer.begin(timestampMs: _clock()));

    // A connection that comes, goes, or is retried is a boundary in the
    // observation whether or not any note crossed it.
    ref.listen<MidiConnectionPhase>(
      midiConnectionStateProvider.select((state) => state.phase),
      (previous, next) {
        if (previous == next) return;
        _emit(_reducer.begin(timestampMs: _clock()));
      },
    );

    // Adopting an instrument is what makes every other live source foreign.
    ref.listen<MidiDevice?>(
      midiDeviceManagerProvider.select((state) => state.connectedDevice),
      (previous, next) {
        if (previous?.id == next?.id) return;
        _reducer.adopt(_identityOf(next));
        _emit(_reducer.begin(timestampMs: _clock()));
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
  void suspendObservation() => _emit(
    _reducer.fail(
      InputIntegrityFault.observationGap,
      timestampMs: _clock(),
      detail: 'observation suspended',
    ),
  );

  /// Opens a fresh observation after a suspension or a fault.
  void resumeObservation() {
    if (_reducer.isObserving) return;
    _emit(_reducer.begin(timestampMs: _clock()));
  }

  /// A boundary carrying the whole snapshot, for a consumer attaching now.
  ///
  /// Reopens the observation first when a fault closed it, so a listener can
  /// always be handed a state to start from.
  InputTemporalEvent openObservation() {
    if (!_reducer.isObserving) {
      _emit(_reducer.begin(timestampMs: _clock()));
    }
    return _reducer.resync(timestampMs: _clock());
  }

  void _subscribe(Stream<MidiSourceMessage> messages) {
    unawaited(_messages?.cancel());
    _messages = messages.listen(
      _receive,
      // An error is not a quiet gap in the input. Reading through it is how a
      // capture kept collecting notes after its stream had already failed.
      onError: (Object error, StackTrace _) {
        if (!kReleaseMode) debugPrint('MIDI message error: $error');
        _emit(
          _reducer.fail(
            InputIntegrityFault.sourceFailure,
            timestampMs: _clock(),
            detail: '$error',
          ),
        );
      },
      onDone: () => _emit(
        _reducer.fail(
          InputIntegrityFault.sourceClosed,
          timestampMs: _clock(),
          detail: 'the MIDI source ended',
        ),
      ),
      cancelOnError: false,
    );
  }

  void _receive(MidiSourceMessage source) {
    final turnedAway = _reducer.rejectedForeignCount;
    _emit(_reducer.receive(_envelope(source)));
    // A message from another instrument produces no event but is still worth
    // publishing: it is the only sign that something else is playing into the
    // same transport.
    if (_reducer.rejectedForeignCount != turnedAway) _publish();
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

  static InputSourceIdentity? _identityOf(MidiDevice? device) => device == null
      ? null
      : InputSourceIdentity(
          deviceId: device.id,
          transport: device.transport.name,
        );

  void _emit(List<InputTemporalEvent> events) {
    if (events.isEmpty || _events.isClosed) return;
    for (final event in events) {
      _events.add(event);
    }
    _publish();
  }

  /// Nothing may assign state until build has returned one.
  void _publish() {
    if (_isBuilt) state = _currentState();
  }

  MidiInputState _currentState() => MidiInputState(
    snapshot: _reducer.snapshot,
    isObserving: _reducer.isObserving,
    fault: _reducer.fault,
    rejectedForeignMessages: _reducer.rejectedForeignCount,
  );
}
