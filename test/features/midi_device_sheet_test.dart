import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

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
        midiPreferenceStoreProvider.overrideWithValue(prefs),
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

  Future<void> openSheet(
    WidgetTester tester, {
    bool disableAnimations = false,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('picker-capture'),
        child: UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: disableAnimations,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
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
      ),
    );
    await tester.tap(find.text('Choose instrument'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('selected row paint stays inside the scrolling list', (
    tester,
  ) async {
    ble.discoverable = [
      _otherInstrument,
      for (var index = 0; index < 12; index++)
        MidiDevice(
          id: 'instrument-$index',
          name: 'Instrument $index',
          transport: MidiTransportType.ble,
          isConnected: false,
        ),
    ];
    await container
        .read(midiConnectionStateProvider.notifier)
        .connect(_otherInstrument);
    await openSheet(tester, disableAnimations: true);

    final list = find.descendant(
      of: find.byType(MidiDeviceSheet),
      matching: find.byType(ListView),
    );
    final headingPoint = tester.getTopLeft(list) + const Offset(40, -8);
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('picker-capture')),
    );
    Future<List<int>?> headingPixel() => tester.runAsync(() async {
      final image = await boundary.toImage();
      try {
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset =
            (headingPoint.dy.toInt() * image.width + headingPoint.dx.toInt()) *
            4;
        return bytes.buffer.asUint8List(offset, 4).toList();
      } finally {
        image.dispose();
      }
    });

    final before = await headingPixel();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    scrollable.position.jumpTo(48);
    await tester.pump();
    expect(
      await headingPixel(),
      before,
      reason: 'the selected background must not paint above the list',
    );
    await container.read(midiConnectionStateProvider.notifier).disconnect();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('scan pulses and respects reduced motion', (tester) async {
    await openSheet(tester);
    final fade = find.descendant(
      of: find.byType(MidiDeviceSheet),
      matching: find.byType(FadeTransition),
    );
    final opacity = tester.widget<FadeTransition>(fade).opacity;
    final before = opacity.value;
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity.value, isNot(before));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await openSheet(tester, disableAnimations: true);
    final still = tester.widget<FadeTransition>(fade).opacity;
    expect(still.value, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(still.value, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('connected row stays visible at phone width with larger text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await container
        .read(midiConnectionStateProvider.notifier)
        .connect(_otherInstrument);
    ble.discoverable = [testInstrument];
    await openSheet(tester, textScale: 1.5);

    expect(find.text('Bluetooth · Connected'), findsOneWidget);
    expect(find.textContaining('Connected to'), findsNothing);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Stage Piano')).dy,
      lessThan(tester.getTopLeft(find.text(testInstrument.name)).dy),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Disconnect'));
    await tester.pump();
    expect(find.text('Bluetooth · Connected'), findsNothing);
    expect(find.text('Scanning for instruments'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

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
    final disconnectGate = Completer<void>();
    ble.connectGate = gate;
    ble.disconnectGate = disconnectGate;
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
    expect(ble.connectCalls, 1);
    expect(find.byType(MidiDeviceSheet), findsOneWidget);
    disconnectGate.complete();
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
