import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall/features/input/midi_device_sheet.dart';

import '../../packages/keyrecall_midi/test/fake_midi_ble_service.dart';

const _otherInstrument = MidiDevice(
  id: 'bbb',
  name: 'Stage Piano',
  transport: MidiTransportType.ble,
  isConnected: false,
);

void main() {
  late ProviderContainer container;
  late FakeMidiBleService ble;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ble = FakeMidiBleService()..discoverable = [_otherInstrument];
    container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        midiBleServiceProvider.overrideWithValue(ble),
        bluetoothPermissionServiceProvider.overrideWithValue(
          const FakeBluetoothPermissionService(),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    ble.dispose();
  });

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => MidiDeviceSheet.show(context),
                child: const Text('Choose instrument'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose instrument'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('another instrument can be selected during auto reconnect', (
    tester,
  ) async {
    await container
        .read(midiPreferencesProvider.notifier)
        .setLastConnectedDevice(testInstrument);
    unawaited(
      container
          .read(midiConnectionStateProvider.notifier)
          .tryAutoReconnect(reason: MidiReconnectTrigger.startup),
    );
    await openSheet(tester);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Stage Piano'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(find.byType(MidiDeviceSheet), findsNothing);
    expect(ble.connectedIds, {_otherInstrument.id});
    expect(tester.takeException(), isNull);
    await container.read(midiConnectionStateProvider.notifier).disconnect();
  });

  testWidgets('cancel keeps the picker open and allows an immediate retry', (
    tester,
  ) async {
    final gate = Completer<void>();
    ble.connectGate = gate;
    await openSheet(tester);
    await tester.tap(find.text('Stage Piano'));
    await tester.pump();
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.byType(MidiDeviceSheet), findsOneWidget);

    ble.connectGate = null;
    await tester.tap(find.text('Stage Piano'));
    await tester.pump();
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MidiDeviceSheet), findsNothing);
    expect(ble.connectedIds, {_otherInstrument.id});
    expect(tester.takeException(), isNull);
    await container.read(midiConnectionStateProvider.notifier).disconnect();
  });

  testWidgets('a superseded selection cannot close the pending picker', (
    tester,
  ) async {
    ble.discoverable = [testInstrument, _otherInstrument];
    final firstGate = Completer<void>();
    ble.connectGate = firstGate;
    await openSheet(tester);
    await tester.tap(find.text(testInstrument.name));
    await tester.pump();

    final secondGate = Completer<void>();
    ble.connectGate = secondGate;
    await tester.tap(find.text('Stage Piano'));
    await tester.pump();
    firstGate.complete();
    await tester.pump();
    expect(find.byType(MidiDeviceSheet), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Could not connect.'), findsNothing);

    secondGate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MidiDeviceSheet), findsNothing);
    expect(ble.connectedIds, {_otherInstrument.id});
    expect(tester.takeException(), isNull);
    await container.read(midiConnectionStateProvider.notifier).disconnect();
  });

  testWidgets('a failed selection stays in the picker with an error', (
    tester,
  ) async {
    ble.connectError = const MidiException('Instrument unavailable');
    await openSheet(tester);
    await tester.tap(find.text('Stage Piano'));
    await tester.pump();
    expect(find.byType(MidiDeviceSheet), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.textContaining('Failed to connect'), findsWidgets);
    expect(tester.takeException(), isNull);
    await container.read(midiConnectionStateProvider.notifier).disconnect();
  });
}
