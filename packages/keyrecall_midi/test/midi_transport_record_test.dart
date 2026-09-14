import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall_input/keyrecall_input.dart';
import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';

import 'fake_midi_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMidiBleService ble;
  late ProviderContainer container;
  late List<MidiTransportRecord> records;
  late int nowMs;

  setUp(() async {
    silenceDebugPrint();
    ble = FakeMidiBleService();
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
    await adoptInstrument(container, ble);

    records = [];
    final trace = container
        .read(midiInputProvider.notifier)
        .transportRecords
        .listen(records.add);
    addTearDown(trace.cancel);
  });

  Future<void> emit(MidiMessage message, {String? deviceId}) async {
    ble.emitMessage(message, deviceId: deviceId);
    await pumpEventQueue();
  }

  List<MidiTransportDelivery> deliveries() =>
      records.whereType<MidiTransportDelivery>().toList();
  List<MidiTransportBoundary> boundaries() =>
      records.whereType<MidiTransportBoundary>().toList();

  Future<void> adopt() async {
    const device = MidiDevice(
      id: 'adopted',
      name: 'JamCorder',
      transport: MidiTransportType.ble,
      isConnected: false,
    );
    ble.discoverable = const [device];
    await container.read(midiConnectionStateProvider.notifier).connect(device);
    await pumpEventQueue();
    records.clear();
  }

  test('a delivery keeps both clocks and its provenance', () async {
    nowMs = 40;
    await emit(
      const MidiMessage(
        type: MidiMessageType.noteOn,
        channel: 3,
        note: 60,
        velocity: 90,
      ),
    );

    final envelope = deliveries().last.envelope;
    expect(envelope.arrivalTimestampMs, 40);
    expect(envelope.transportTimestamp, isNotNull);
    expect(envelope.channel, 3);
    expect(envelope.source.transport, 'ble');
    expect(envelope.message.kind, RawInputKind.noteOn);
    expect(envelope.message.note, 60);
    expect(deliveries().last.live, isTrue);
  });

  // The dataset has to explain the discontinuities in itself, so what the
  // boundary threw away is exactly what must not be filtered out of it.
  test('what the boundary rejects is still recorded', () async {
    await adopt();
    await emit(
      const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 90),
      deviceId: 'someone-elses-pad',
    );

    expect(deliveries(), hasLength(1));
    expect(deliveries().single.envelope.source.deviceId, 'someone-elses-pad');
    expect(
      container.read(midiInputProvider).snapshot.isSilent,
      isTrue,
      reason: 'recording it did not admit it',
    );
  });

  test('a malformed payload is recorded as it arrived', () async {
    await emit(
      const MidiMessage(type: MidiMessageType.noteOn, note: 200, velocity: 90),
    );

    expect(
      deliveries().last.envelope.message.note,
      200,
      reason: 'the trace is of the transport, not of what survived validation',
    );
    expect(
      boundaries().last.fault,
      InputIntegrityFault.malformedInput,
      reason: 'and the fault it caused is beside it',
    );
  });

  // An app backgrounded with nobody playing delivers nothing at all, so a
  // discontinuity across it would have nothing to be attributed to.
  test('a boundary nothing crossed is still recorded', () async {
    await adopt();
    nowMs = 100;
    container.read(midiInputProvider.notifier).suspendObservation();
    nowMs = 8000;
    container.read(midiInputProvider.notifier).resumeObservation();
    await pumpEventQueue();

    expect(deliveries(), isEmpty);
    expect(boundaries().map((boundary) => boundary.kind), [
      MidiTransportBoundaryKind.observationFailed,
      MidiTransportBoundaryKind.sessionOpened,
    ]);
    expect(boundaries().first.fault, InputIntegrityFault.observationGap);
    expect(boundaries().first.arrivalTimestampMs, 100);
    expect(boundaries().last.arrivalTimestampMs, 8000);
    expect(
      boundaries().last.session,
      isNot(boundaries().first.adopted?.sessionId),
      reason: 'which session the clocks are either side of',
    );
  });

  test('records are numbered in the order they were taken', () async {
    await emit(
      const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 90),
    );
    await emit(
      const MidiMessage(type: MidiMessageType.noteOff, note: 60, velocity: 0),
    );

    expect([
      for (final record in records) record.sequence,
    ], List.generate(records.length, (index) => index));
  });
}
