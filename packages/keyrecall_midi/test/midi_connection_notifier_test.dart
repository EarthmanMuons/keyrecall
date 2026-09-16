import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'fake_midi_ble_service.dart';

const _deviceA = MidiDevice(
  id: 'aaa',
  name: 'JamCorder',
  transport: MidiTransportType.ble,
  isConnected: false,
);

/// Wires a container around the fake transport inside a FakeAsync zone.
///
/// All timers (backoff sleeps, timeouts, the post-connect settle) are fake,
/// so scenarios advance with `async.elapse`. Wall-clock reads
/// (`DateTime.now`) are real, which keeps the 5s auto-reconnect rate limit
/// *engaged* for back-to-back automatic triggers inside a test; scenarios
/// that need a second trigger use manual or bt-ready paths that bypass or
/// escape it.
class _Harness {
  _Harness(FakeAsync async, SharedPreferences prefs)
    : ble = FakeMidiBleService() {
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        midiBleServiceProvider.overrideWithValue(ble),
        bluetoothPermissionServiceProvider.overrideWithValue(
          FakeBluetoothPermissionService(),
        ),
      ],
    );
    _subscription = container.listen(midiConnectionStateProvider, (_, _) {});
    async.flushMicrotasks();
  }

  final FakeMidiBleService ble;
  late final ProviderContainer container;
  late final ProviderSubscription<MidiConnectionState> _subscription;

  MidiConnectionNotifier get notifier =>
      container.read(midiConnectionStateProvider.notifier);
  MidiConnectionState get state => container.read(midiConnectionStateProvider);

  /// Persists a last-connected device so auto reconnect has a target.
  void seedLastConnected(FakeAsync async, MidiDevice device) {
    unawaited(
      container
          .read(midiPreferencesProvider.notifier)
          .setLastConnectedDevice(device),
    );
    async.flushMicrotasks();
  }

  /// Connects [device] through the notifier (a manual user action) and
  /// advances past the post-connect settle.
  void connectNow(FakeAsync async, MidiDevice device) {
    ble.discoverable = [device];
    unawaited(notifier.connect(device));
    async.flushMicrotasks();
    async.elapse(const Duration(seconds: 1));
    async.flushMicrotasks();
  }

  void dispose(FakeAsync async) {
    _subscription.close();
    container.dispose();
    ble.dispose();
    async.flushMicrotasks();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;

  setUp(() async {
    silenceDebugPrint();
    SharedPreferences.setMockInitialValues(const {});
    prefs = await SharedPreferences.getInstance();
  });

  const deviceB = MidiDevice(
    id: 'bbb',
    name: 'Stage Piano',
    transport: MidiTransportType.ble,
    isConnected: false,
  );

  for (final delay in [Duration.zero, const Duration(seconds: 5)]) {
    test('manual selection supersedes reconnect after $delay', () {
      fakeAsync((async) {
        final h = _Harness(async, prefs);
        h.seedLastConnected(async, _deviceA);
        h.ble.discoverable = const [deviceB];
        unawaited(
          h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
        );
        async.flushMicrotasks();
        async.elapse(delay);

        unawaited(h.notifier.connect(deviceB));
        async.flushMicrotasks();
        expect(h.state.device?.id, deviceB.id);
        expect(h.state.isConnected, isTrue);

        h.ble.discoverable = const [_deviceA, deviceB];
        async.elapse(const Duration(minutes: 2));
        expect(h.state.device?.id, deviceB.id);
        expect(h.ble.connectedIds, {deviceB.id});
        expect(h.ble.connectCalls, 1);
        h.dispose(async);
      });
    });
  }

  for (final fail in [false, true]) {
    test('superseded native connect cannot replace the selection, fail=$fail', () {
      fakeAsync((async) {
        final h = _Harness(async, prefs);
        final gate = Completer<void>();
        h.ble.connectGate = gate;
        unawaited(h.notifier.connect(_deviceA));
        async.flushMicrotasks();

        h.ble.connectGate = null;
        h.ble.discoverable = const [deviceB];
        unawaited(h.notifier.connect(deviceB));
        async.flushMicrotasks();
        expect(h.state.device?.id, deviceB.id);
        expect(h.state.isConnected, isTrue);
        expect(h.ble.disconnectCalls, 1);

        if (fail) h.ble.connectError = const MidiException('Old attempt failed');
        gate.complete();
        async.flushMicrotasks();
        expect(h.state.device?.id, deviceB.id);
        expect(h.state.isConnected, isTrue);
        expect(h.ble.connectedIds, {deviceB.id});
        h.dispose(async);
      });
    });
  }

  for (final oldConnectFinishesFirst in [false, true]) {
    test('same-device retry waits for native teardown, '
        'old connect finishes first=$oldConnectFinishesFirst', () {
      fakeAsync((async) {
        final h = _Harness(async, prefs);
        final connectGate = Completer<void>();
        final disconnectGate = Completer<void>();
        h.ble.connectGate = connectGate;
        h.ble.disconnectGate = disconnectGate;
        unawaited(h.notifier.connect(_deviceA));
        async.flushMicrotasks();

        unawaited(h.notifier.cancelConnectionAttempt());
        expect(h.state.phase, MidiConnectionPhase.idle);
        expect(h.ble.disconnectCalls, 1);
        h.ble.connectGate = null;
        unawaited(h.notifier.connect(_deviceA));
        async.flushMicrotasks();
        expect(h.state.phase, MidiConnectionPhase.connecting);
        expect(h.ble.connectCalls, 1, reason: 'native teardown still owns A');

        if (oldConnectFinishesFirst) {
          connectGate.complete();
          async.flushMicrotasks();
        }
        disconnectGate.complete();
        async.flushMicrotasks();
        expect(h.ble.connectCalls, 2);
        expect(h.state.isConnected, isTrue);

        if (!oldConnectFinishesFirst) {
          connectGate.complete();
          async.flushMicrotasks();
        }
        expect(h.ble.connectedIds, {_deviceA.id});
        expect(h.ble.disconnectCalls, 1);
        h.dispose(async);
      });
    });
  }

  test('same-device retry waits for stale-connect cleanup already in progress', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      final connectGate = Completer<void>();
      h.ble.connectGate = connectGate;
      unawaited(h.notifier.connect(_deviceA));
      async.flushMicrotasks();
      unawaited(h.notifier.cancelConnectionAttempt());
      async.flushMicrotasks();

      final disconnectGate = Completer<void>();
      h.ble.disconnectGate = disconnectGate;
      connectGate.complete();
      async.flushMicrotasks();
      expect(h.ble.disconnectCalls, 2);

      h.ble.connectGate = null;
      unawaited(h.notifier.connect(_deviceA));
      async.flushMicrotasks();
      expect(h.ble.connectCalls, 1);
      disconnectGate.complete();
      async.flushMicrotasks();
      expect(h.state.isConnected, isTrue);
      expect(h.ble.connectedIds, {_deviceA.id});
      h.dispose(async);
    });
  });

  test('canceling an attempt does not disconnect an established instrument', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.connectNow(async, _deviceA);
      unawaited(h.notifier.cancelConnectionAttempt());
      async.flushMicrotasks();
      expect(h.state.isConnected, isTrue);
      expect(h.ble.disconnectCalls, 0);
      h.dispose(async);
    });
  });

  test('cancel permits an immediate retry of the same device', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      final gate = Completer<void>();
      h.ble.connectGate = gate;
      unawaited(h.notifier.connect(_deviceA));
      async.flushMicrotasks();
      unawaited(h.notifier.disconnect());
      expect(h.state.phase, MidiConnectionPhase.idle);
      async.flushMicrotasks();

      h.ble.connectGate = null;
      h.ble.discoverable = const [_deviceA];
      unawaited(h.notifier.connect(_deviceA));
      async.flushMicrotasks();
      gate.complete();
      async.flushMicrotasks();
      expect(h.state.isConnected, isTrue);
      expect(h.ble.connectedIds, {_deviceA.id});
      h.dispose(async);
    });
  });

  test('user cancel suppresses resume and Bluetooth recovery', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();
      unawaited(h.notifier.cancel());
      async.flushMicrotasks();
      h.ble.discoverable = const [_deviceA];
      h.ble.emitBluetoothState(BluetoothState.poweredOff);
      async.flushMicrotasks();
      h.ble.emitBluetoothState(BluetoothState.poweredOn);
      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.resume),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(h.ble.connectCalls, 0);
      h.dispose(async);
    });
  });

  test('startup reconnect retries with exponential backoff until the device '
      'reappears', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();

      // Attempt 1 waits out the discovery window before giving up.
      expect(h.state.phase, MidiConnectionPhase.connecting);
      expect(h.state.attempt, 1);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.retrying);
      expect(h.state.nextDelay, const Duration(seconds: 1));

      // The device comes back; the second attempt discovers and connects it.
      h.ble.discoverable = const [_deviceA];
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.state.device?.id, _deviceA.id);
      h.dispose(async);
    });
  });

  test('cancel during backoff stops the loop and settles on idle', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.retrying);

      unawaited(h.notifier.cancel());
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.idle);

      final devicesCalls = h.ble.devicesCalls;
      async.elapse(const Duration(minutes: 2));
      async.flushMicrotasks();
      expect(h.ble.devicesCalls, devicesCalls, reason: 'loop is dead');
      expect(h.state.phase, MidiConnectionPhase.idle);
      h.dispose(async);
    });
  });

  test('backgrounding stops the reconnect loop', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.retrying);

      h.notifier.setBackgrounded(true);
      async.flushMicrotasks();

      final devicesCalls = h.ble.devicesCalls;
      async.elapse(const Duration(minutes: 2));
      async.flushMicrotasks();
      expect(
        h.ble.devicesCalls,
        devicesCalls,
        reason:
            'no attempts while '
            'backgrounded',
      );
      h.dispose(async);
    });
  });

  test('an explicit disconnect suppresses automatic reconnect until a manual '
      'trigger', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.connectNow(async, _deviceA);
      expect(h.state.phase, MidiConnectionPhase.connected);

      unawaited(h.notifier.disconnect());
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.idle);

      final connectCalls = h.ble.connectCalls;
      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.resume),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(h.ble.connectCalls, connectCalls, reason: 'resume suppressed');
      expect(h.state.phase, MidiConnectionPhase.idle);

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.manual),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.ble.connectCalls, connectCalls + 1);
      h.dispose(async);
    });
  });

  test('losing Bluetooth mid-reconnect surfaces unavailable; recovery '
      'reconnects', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.manual),
      );
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.connecting);

      h.ble.emitBluetoothState(BluetoothState.poweredOff);
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.bluetoothUnavailable);

      // Drain the aborted attempt's discovery wait so its in-flight flag
      // clears before recovery arrives.
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      h.ble.discoverable = const [_deviceA];
      h.ble.emitBluetoothState(BluetoothState.poweredOn);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.state.device?.id, _deviceA.id);
      h.dispose(async);
    });
  });

  test('the startup trigger runs at most once per app run', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [_deviceA];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.ble.connectCalls, 1);

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.startup),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();
      expect(h.ble.connectCalls, 1, reason: 'second startup is a no-op');
      h.dispose(async);
    });
  });

  test('resume revalidates a stale connected snapshot and reconnects', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.connectNow(async, _deviceA);
      expect(h.state.phase, MidiConnectionPhase.connected);

      // The link died at the transport level, but app state still says
      // connected (the iOS backgrounded-drop shape).
      h.ble.connectedIds.clear();

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.resume),
      );
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      async.flushMicrotasks();

      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.ble.connectedIds, {_deviceA.id}, reason: 'reconnected');
      expect(h.ble.connectCalls, 2);
      h.dispose(async);
    });
  });

  test('an unexpected link loss triggers the auto-reconnect loop', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.connectNow(async, _deviceA);
      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.ble.connectCalls, 1);

      // The device dies at the transport level; reconciliation notices.
      h.ble.connectedIds.clear();
      unawaited(
        h.container
            .read(midiDeviceManagerProvider.notifier)
            .reconcileConnectedDevice(reason: 'test'),
      );
      async.flushMicrotasks();

      // The loss kicks the reconnect loop; the device is still discoverable,
      // so the first attempt reconnects it.
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.ble.connectCalls, 2);
      h.dispose(async);
    });
  });

  test('switching devices does not read as a link loss', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.connectNow(async, _deviceA);

      const deviceB = MidiDevice(
        id: 'bbb',
        name: 'Stage Piano',
        transport: MidiTransportType.ble,
        isConnected: false,
      );
      h.ble.discoverable = const [_deviceA, deviceB];
      unawaited(h.notifier.connect(deviceB));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.state.device?.id, deviceB.id);
      expect(
        h.ble.connectCalls,
        2,
        reason: 'no phantom reconnect of the switched-away device',
      );
      h.dispose(async);
    });
  });

  test('bluetooth recovery is not throttled by the auto-reconnect rate '
      'limit', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      // A resume attempt stamps the rate limit, then loses Bluetooth.
      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.resume),
      );
      async.flushMicrotasks();
      h.ble.emitBluetoothState(BluetoothState.poweredOff);
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.bluetoothUnavailable);
      async.elapse(const Duration(seconds: 5));
      async.flushMicrotasks();

      // Recovery well inside the 5s rate-limit window still reconnects,
      // because the loss cleared the stamp.
      h.ble.discoverable = const [_deviceA];
      h.ble.emitBluetoothState(BluetoothState.poweredOn);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();
      expect(h.state.phase, MidiConnectionPhase.connected);
      h.dispose(async);
    });
  });

  test('a bluetooth-ready trigger during an in-flight attempt defers until '
      'it unwinds', () {
    fakeAsync((async) {
      final h = _Harness(async, prefs);
      h.seedLastConnected(async, _deviceA);
      h.ble.discoverable = const [];

      unawaited(
        h.notifier.tryAutoReconnect(reason: MidiReconnectTrigger.manual),
      );
      async.flushMicrotasks();

      // Run the loop into its final attempt's discovery wait: four failed
      // attempts (5s each) plus their backoffs (1+2+4+8s).
      async.elapse(const Duration(seconds: 35));
      async.flushMicrotasks();

      // Bluetooth blips while attempt 5 is mid-wait: the ready trigger finds
      // the attempt in flight and must defer rather than drop.
      h.ble.emitBluetoothState(BluetoothState.poweredOff);
      async.flushMicrotasks();
      h.ble.emitBluetoothState(BluetoothState.poweredOn);
      async.flushMicrotasks();

      // Attempt 5's wait and final backoff drain; the loop exhausts, then
      // the deferred trigger starts a fresh attempt that finds the device.
      async.elapse(const Duration(seconds: 21));
      async.flushMicrotasks();
      h.ble.discoverable = const [_deviceA];
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));
      async.flushMicrotasks();

      expect(h.state.phase, MidiConnectionPhase.connected);
      expect(h.state.device?.id, _deviceA.id);
      h.dispose(async);
    });
  });
}
