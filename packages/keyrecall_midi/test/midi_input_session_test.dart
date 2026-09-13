import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'fake_midi_ble_service.dart';

/// A subscription that keeps its callbacks after it has been cancelled.
///
/// A real transport should not do this. The guard being tested exists because
/// whether a particular platform stream can fire a terminal callback around a
/// cancel is not something the input boundary should have to depend on.
class _StaleSubscription implements StreamSubscription<MidiSourceMessage> {
  _StaleSubscription(this._onData, this._onError, this._onDone);

  final void Function(MidiSourceMessage)? _onData;
  final Function? _onError;
  final void Function()? _onDone;

  bool isCancelled = false;

  void deliver(MidiSourceMessage message) => _onData?.call(message);

  void deliverError(Object error) =>
      (_onError as void Function(Object, StackTrace)?)?.call(
        error,
        StackTrace.empty,
      );

  void deliverDone() => _onDone?.call();

  @override
  Future<void> cancel() async {
    isCancelled = true;
  }

  @override
  void onData(void Function(MidiSourceMessage)? handleData) {}
  @override
  void onError(Function? handleError) {}
  @override
  void onDone(void Function()? handleDone) {}
  @override
  void pause([Future<void>? resumeSignal]) {}
  @override
  void resume() {}
  @override
  bool get isPaused => false;
  @override
  Future<E> asFuture<E>([E? futureValue]) => Completer<E>().future;
}

/// A source that hands every subscription it made to the test.
class _StaleSource extends Stream<MidiSourceMessage> {
  final List<_StaleSubscription> subscriptions = [];

  @override
  StreamSubscription<MidiSourceMessage> listen(
    void Function(MidiSourceMessage)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = _StaleSubscription(onData, onError, onDone);
    subscriptions.add(subscription);
    return subscription;
  }
}

class _StaleSourceService extends FakeMidiBleService {
  final _StaleSource source = _StaleSource();

  @override
  Stream<MidiSourceMessage> get onMidiMessages => source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StaleSourceService ble;
  late ProviderContainer container;
  late int nowMs;

  setUp(() async {
    silenceDebugPrint();
    ble = _StaleSourceService();
    SharedPreferences.setMockInitialValues(const {});
    final preferences = await SharedPreferences.getInstance();
    nowMs = 0;
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(preferences),
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
  });

  MidiInputNotifier input() => container.read(midiInputProvider.notifier);
  MidiInputState state() => container.read(midiInputProvider);

  /// Replaces the transport session, the way returning to the foreground does.
  Future<_StaleSubscription> supersede() async {
    final superseded = ble.source.subscriptions.last;
    input()
      ..suspendObservation()
      ..resumeObservation();
    await pumpEventQueue();
    expect(superseded.isCancelled, isTrue);
    return superseded;
  }

  test('every session replaces the subscription before it', () async {
    expect(ble.source.subscriptions, hasLength(1));

    await supersede();

    expect(ble.source.subscriptions, hasLength(2));
    expect(state().isObserving, isTrue);
  });

  test(
    'a superseded subscription cannot end the observation that replaced it',
    () async {
      final superseded = await supersede();
      nowMs = 50;

      superseded.deliverError(StateError('late failure from a dead link'));
      await pumpEventQueue();

      expect(state().isObserving, isTrue);
      expect(state().fault, isNull);
      expect(
        ble.source.subscriptions,
        hasLength(2),
        reason: 'a stale error opened no session of its own',
      );
    },
  );

  test(
    'a superseded subscription closing cannot end its replacement',
    () async {
      final superseded = await supersede();
      nowMs = 50;

      superseded.deliverDone();
      await pumpEventQueue();

      expect(state().isObserving, isTrue);
      expect(state().fault, isNull);
    },
  );

  // The admission filter turns stale messages away once an instrument is
  // adopted. Nothing is adopted here, which is when every source is admitted
  // by policy, so this is the case only the subscription guard covers.
  test('a superseded subscription cannot play into its replacement', () async {
    final superseded = await supersede();
    nowMs = 50;

    superseded.deliver(
      const MidiSourceMessage(
        message: MidiMessage(
          type: MidiMessageType.noteOn,
          note: 60,
          velocity: 90,
        ),
        deviceId: 'whatever',
        transport: MidiTransportType.ble,
        transportTimestamp: 0,
      ),
    );
    await pumpEventQueue();

    expect(
      state().adopted,
      isNull,
      reason: 'nothing adopted, so nothing to admit against',
    );
    expect(state().snapshot.isSilent, isTrue);
  });
}
