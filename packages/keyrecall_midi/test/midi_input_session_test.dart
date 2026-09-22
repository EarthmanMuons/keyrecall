import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';
import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'fake_midi_ble_service.dart';

/// A source that counts how many times anything subscribed to it.
///
/// The plugin's stream reaches the platform's own event channel, whose last
/// listener leaving takes the MIDI receivers down with it. Counting
/// subscriptions is how a test says that never happens twice.
class _CountingSource extends Stream<MidiSourceMessage> {
  _CountingSource(this._messages);

  final Stream<MidiSourceMessage> _messages;
  int subscriptions = 0;
  int cancellations = 0;

  @override
  StreamSubscription<MidiSourceMessage> listen(
    void Function(MidiSourceMessage)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    subscriptions += 1;
    final inner = _messages.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _CountingSubscription(inner, () => cancellations += 1);
  }
}

class _CountingSubscription implements StreamSubscription<MidiSourceMessage> {
  _CountingSubscription(this._inner, this._onCancel);

  final StreamSubscription<MidiSourceMessage> _inner;
  final void Function() _onCancel;

  @override
  Future<void> cancel() {
    _onCancel();
    return _inner.cancel();
  }

  @override
  void onData(void Function(MidiSourceMessage)? handleData) =>
      _inner.onData(handleData);
  @override
  void onError(Function? handleError) => _inner.onError(handleError);
  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);
  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);
  @override
  void resume() => _inner.resume();
  @override
  bool get isPaused => _inner.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);
}

class _CountingService extends FakeMidiBleService {
  late final _CountingSource source = _CountingSource(super.onMidiMessages);

  @override
  Stream<MidiSourceMessage> get onMidiMessages => source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _CountingService ble;
  late ProviderContainer container;
  late int nowMs;

  setUp(() async {
    silenceDebugPrint();
    ble = _CountingService();
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    nowMs = 0;
    container = ProviderContainer(
      overrides: [
        midiPreferenceStoreProvider.overrideWithValue(preferences),
        midiBleServiceProvider.overrideWithValue(ble),
        bluetoothPermissionServiceProvider.overrideWithValue(
          const FakeBluetoothPermissionService(),
        ),
        inputEventClockProvider.overrideWithValue(() => nowMs),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(ble.dispose);
    final held = container.listen(midiInputProvider, (_, _) {});
    addTearDown(held.close);
    await pumpEventQueue();
    await adoptInstrument(container, ble);
  });

  MidiInputNotifier input() => container.read(midiInputProvider.notifier);
  MidiInputState state() => container.read(midiInputProvider);

  // What broke Android. Every connection transition used to replace the
  // transport subscription, which dropped the platform channel's last
  // listener and took its MIDI receivers down with it: delivery stopped, and
  // several epochs went by before anything arrived again.
  test('every epoch after the first leaves the transport alone', () async {
    expect(ble.source.subscriptions, 1);

    const device = MidiDevice(
      id: 'adopted',
      name: 'JamCorder',
      transport: MidiTransportType.ble,
      isConnected: false,
    );
    ble.discoverable = const [device];
    await container.read(midiConnectionStateProvider.notifier).connect(device);
    await pumpEventQueue();
    input()
      ..suspendObservation()
      ..resumeObservation();
    await pumpEventQueue();

    expect(
      state().adopted?.sessionId,
      isNot('midi-1'),
      reason: 'several epochs opened',
    );
    expect(ble.source.subscriptions, 1);
    expect(ble.source.cancellations, 0);
  });

  test('input still arrives after the epochs that used to break it', () async {
    input()
      ..suspendObservation()
      ..resumeObservation();
    await pumpEventQueue();

    ble.emitMessage(
      const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 90),
    );
    await pumpEventQueue();

    expect(state().snapshot.pressedNoteNumbers, {60});
  });

  // The subscription does not cancel on error, so a transient failure costs
  // an epoch rather than the instrument.
  test('a source error costs an epoch, not the subscription', () async {
    ble.emitMessageError(StateError('link hiccup'));
    await pumpEventQueue();

    expect(ble.source.subscriptions, 1);
    expect(state().isObserving, isTrue);

    nowMs = 50;
    ble.emitMessage(
      const MidiMessage(type: MidiMessageType.noteOn, note: 64, velocity: 90),
    );
    await pumpEventQueue();

    expect(state().snapshot.pressedNoteNumbers, {64});
  });

  // The published state is what diagnostics read. A delivery that measures the
  // clock, or fails its timeline, does not have to move a key, and the
  // musical-event path was acting as the only notification boundary.
  group('what the clock is doing reaches the state', () {
    /// A controller message, which normalizes to no event at all.
    void controller(int value, {required int transportTimestamp}) {
      ble.emitMessage(
        MidiMessage(
          type: MidiMessageType.controlChange,
          ccNumber: 1,
          ccValue: value,
        ),
        transportTimestamp: transportTimestamp,
      );
    }

    test('a delivery nobody played still advances the measurement', () async {
      for (var step = 1; step <= 9; step++) {
        nowMs = step;
        controller(step, transportTimestamp: step * 100000);
        await pumpEventQueue();
      }

      expect(state().clockObservation.steps, 8);
      expect(state().clockObservation.granularity, 100000);
    });

    test('the BLE route is timed without waiting for a wrap', () async {
      for (var step = 1; step <= 3; step++) {
        nowMs = step * 100;
        ble.emitMessage(
          MidiMessage(
            type: MidiMessageType.controlChange,
            ccNumber: 1,
            ccValue: step,
          ),
          route: MidiRoute.ble,
          transportTimestamp: 1000 + step * 100,
        );
        await pumpEventQueue();
      }

      expect(state().clockObservation.modulus, isNull);
      expect(state().clockPhase, PerformanceClockPhase.active);
    });

    test('and a timeline that fails is published when it fails', () async {
      for (var step = 1; step <= 10; step++) {
        nowMs = step;
        controller(step, transportTimestamp: step * 100000);
        await pumpEventQueue();
      }
      expect(state().clockPhase, PerformanceClockPhase.active);

      // A reading the clock cannot have produced, on a domain with no
      // characterized wrap.
      nowMs = 11;
      controller(11, transportTimestamp: 100000);
      await pumpEventQueue();

      expect(state().clockPhase, PerformanceClockPhase.failed);
    });
  });

  // Three separate facts: the transport can deliver, nobody has put
  // observation down, and an instrument is adopted. An epoch needs all of
  // them, and inferring any from the reducer's phase is what let these two
  // reopen an observation nothing could vouch for.
  group('an epoch cannot be opened by inference', () {
    test('an error during a suspension does not resume it', () async {
      input().suspendObservation();
      await pumpEventQueue();
      expect(state().isObserving, isFalse);

      ble.emitMessageError(StateError('link hiccup'));
      await pumpEventQueue();

      expect(
        state().isObserving,
        isFalse,
        reason: 'the app is still in the background',
      );
      expect(state().fault, InputIntegrityFault.observationGap);

      input().resumeObservation();
      await pumpEventQueue();

      expect(state().isObserving, isTrue);
    });

    test('a resume does not claim a transport that ended', () async {
      await ble.closeMessages();
      await pumpEventQueue();
      expect(state().fault, InputIntegrityFault.sourceClosed);

      input().resumeObservation();
      await pumpEventQueue();

      expect(
        state().isObserving,
        isFalse,
        reason: 'a subscription that ended cannot deliver again',
      );
    });

    test('a connection transition does not revive an ended transport', () async {
      await ble.closeMessages();
      await pumpEventQueue();

      await adoptInstrument(
        container,
        ble,
        device: const MidiDevice(
          id: 'another',
          name: 'Other',
          transport: MidiTransportType.ble,
          isConnected: false,
        ),
      );

      expect(state().isObserving, isFalse);
    });
  });

  test('a readopted instrument is a new source', () async {
    const device = MidiDevice(
      id: 'adopted',
      name: 'JamCorder',
      transport: MidiTransportType.ble,
      isConnected: false,
    );
    ble.discoverable = const [device];
    await container.read(midiConnectionStateProvider.notifier).connect(device);
    await pumpEventQueue();

    final before = state().adopted;
    expect(before?.sessionId, isNotNull);
    input()
      ..suspendObservation()
      ..resumeObservation();
    await pumpEventQueue();

    expect(state().adopted?.sessionId, isNot(before?.sessionId));
  });
}
