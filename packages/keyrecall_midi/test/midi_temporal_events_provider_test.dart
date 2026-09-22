import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:keyrecall_input_sources/keyrecall_input_sources.dart';
import 'package:keyrecall_midi/keyrecall_midi.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'fake_midi_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeMidiBleService ble;
  late ProviderContainer container;
  late List<InputTemporalEvent> events;
  late int nowMs;
  late ProviderSubscription<Stream<InputTemporalEvent>> providerSubscription;
  late StreamSubscription<InputTemporalEvent> streamSubscription;

  /// Drops every consumer, so the next read builds the provider afresh.
  Future<void> detach() async {
    providerSubscription.close();
    await streamSubscription.cancel();
    await pumpEventQueue();
  }

  setUp(() async {
    ble = FakeMidiBleService();
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

    await adoptInstrument(container, ble);

    events = [];
    providerSubscription = container.listen(
      midiTemporalEventsProvider,
      (previous, next) {},
    );
    addTearDown(providerSubscription.close);
    streamSubscription = container
        .read(midiTemporalEventsProvider)
        .listen(events.add);
    addTearDown(streamSubscription.cancel);
    await pumpEventQueue();

    expect(events, hasLength(1));
    final reset = events.single as InputTemporalResetEvent;
    expect(reset.snapshot.pressedNoteNumbers, isEmpty);
    expect(reset.snapshot.sustainedNoteNumbers, isEmpty);
    expect(reset.snapshot.pedalDown, isFalse);
    events.clear();
  });

  test('preserves note, adopted pedal, and sustain event order', () async {
    ble.emitMessage(
      const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 93),
    );
    await pumpEventQueue();
    nowMs = 25;
    ble.emitMessage(
      const MidiMessage(
        type: MidiMessageType.controlChange,
        ccNumber: MidiConstants.ccSustainPedal,
        ccValue: 127,
      ),
    );
    await pumpEventQueue();
    nowMs = 40;
    ble.emitMessage(
      const MidiMessage(type: MidiMessageType.noteOff, note: 60, velocity: 12),
    );
    await pumpEventQueue();
    nowMs = 70;
    ble.emitMessage(
      const MidiMessage(
        type: MidiMessageType.controlChange,
        ccNumber: MidiConstants.ccSustainPedal,
        ccValue: 0,
      ),
    );
    await pumpEventQueue();

    expect(events, hasLength(4));
    expect(events[0], isA<InputTemporalNoteOnEvent>());
    expect((events[0] as InputTemporalNoteOnEvent).velocity, 93);
    expect(events[1], isA<InputTemporalPedalEvent>());
    expect(events[1].timestampMs, 25);
    expect(events[2], isA<InputTemporalNoteOffEvent>());
    expect((events[2] as InputTemporalNoteOffEvent).velocity, 12);
    expect(events[3], isA<InputTemporalPedalEvent>());
    expect((events[3] as InputTemporalPedalEvent).down, isFalse);
  });

  test(
    'normalizes velocity-zero and duplicate messages without bad frames',
    () async {
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOn, note: 64, velocity: 90),
      );
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOn, note: 64, velocity: 91),
      );
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOn, note: 64, velocity: 0),
      );
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOff, note: 64, velocity: 0),
      );
      await pumpEventQueue();

      expect(events, hasLength(2));
      expect(events.first, isA<InputTemporalNoteOnEvent>());
      expect(events.last, isA<InputTemporalNoteOffEvent>());
    },
  );

  for (final (ccNumber, name) in const [
    (MidiConstants.ccAllSoundOff, 'all-sound-off'),
    (MidiConstants.ccAllNotesOff, 'all-notes-off'),
  ]) {
    test('turns $name into an explicit empty reset', () async {
      ble.emitMessage(
        const MidiMessage(
          type: MidiMessageType.noteOn,
          note: 60,
          velocity: 100,
        ),
      );
      await pumpEventQueue();
      nowMs = 10;
      ble.emitMessage(
        MidiMessage(
          type: MidiMessageType.controlChange,
          ccNumber: ccNumber,
          ccValue: 0,
        ),
      );
      await pumpEventQueue();

      final reset = events.last as InputTemporalResetEvent;
      expect(reset.timestampMs, 10);
      expect(reset.snapshot.pressedNoteNumbers, isEmpty);
      expect(reset.snapshot.sustainedNoteNumbers, isEmpty);
    });
  }

  group('integrity', () {
    // The failure that manufactured evidence: reading through an error let a
    // capture keep collecting, and republished the last note as a new one.
    // The failure that manufactured evidence: reading through an error let a
    // capture keep collecting, and republished the last note as a new one.
    test('a source error ends the observation before replacing it', () async {
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 90),
      );
      await pumpEventQueue();
      nowMs = 20;
      ble.emitMessageError(StateError('link dropped'));
      await pumpEventQueue();

      expect(events.whereType<InputTemporalNoteOnEvent>(), hasLength(1));
      final fault = events.firstWhere((e) => e is InputTemporalFaultEvent);
      expect(
        (fault as InputTemporalFaultEvent).fault,
        InputIntegrityFault.sourceFailure,
      );
      expect(
        events.last,
        isA<InputTemporalResetEvent>(),
        reason: 'a replaced subscription is a new observation, not the old one',
      );
      expect(
        container.read(midiInputProvider).snapshot.isSilent,
        isTrue,
        reason: 'the new observation has not seen a key go down',
      );
    });

    test(
      'a suspended observation admits nothing until it is resumed',
      () async {
        final input = container.read(midiInputProvider.notifier);
        input.suspendObservation();
        await pumpEventQueue();
        final afterFault = events.length;

        nowMs = 50;
        ble.emitMessage(
          const MidiMessage(
            type: MidiMessageType.noteOn,
            note: 64,
            velocity: 90,
          ),
        );
        await pumpEventQueue();

        expect(events, hasLength(afterFault));
        expect(container.read(midiNoteStateProvider).pressed, isEmpty);
      },
    );

    test('a source that ends unexpectedly is a fault, not silence', () async {
      await ble.closeMessages();
      await pumpEventQueue();

      final fault = events.last as InputTemporalFaultEvent;
      expect(fault.fault, InputIntegrityFault.sourceClosed);
      expect(container.read(midiInputProvider).isObserving, isFalse);
    });

    // Attaching is not recovery. A consumer that subscribes after the source
    // failed used to reopen the observation by asking what was sounding.
    test('a consumer attaching cannot revive a closed observation', () async {
      await ble.closeMessages();
      await detach();

      final opening = container.read(midiTemporalEventsProvider);
      final attached = <InputTemporalEvent>[];
      final listener = opening.listen(attached.add);
      addTearDown(listener.cancel);
      await pumpEventQueue();

      expect(attached.single, isA<InputTemporalFaultEvent>());
      expect(
        (attached.single as InputTemporalFaultEvent).fault,
        InputIntegrityFault.sourceClosed,
      );
      expect(container.read(midiInputProvider).isObserving, isFalse);
    });

    test(
      'a malformed payload faults rather than becoming a playable note',
      () async {
        ble.emitMessage(
          const MidiMessage(
            type: MidiMessageType.noteOn,
            note: 200,
            velocity: 90,
          ),
        );
        await pumpEventQueue();

        expect(events.whereType<InputTemporalNoteOnEvent>(), isEmpty);
        expect(
          (events.last as InputTemporalFaultEvent).fault,
          InputIntegrityFault.malformedInput,
        );
      },
    );

    test(
      'suspending observation ends it and resuming starts a new one',
      () async {
        ble.emitMessage(
          const MidiMessage(
            type: MidiMessageType.noteOn,
            note: 60,
            velocity: 90,
          ),
        );
        await pumpEventQueue();

        nowMs = 30;
        final input = container.read(midiInputProvider.notifier);
        input.suspendObservation();
        await pumpEventQueue();

        expect(
          (events.last as InputTemporalFaultEvent).fault,
          InputIntegrityFault.observationGap,
        );
        expect(
          container.read(midiNoteStateProvider).soundingNoteNumbers,
          isEmpty,
        );

        nowMs = 40;
        input.resumeObservation();
        await pumpEventQueue();

        expect(events.last, isA<InputTemporalResetEvent>());
        expect(container.read(midiInputProvider).isObserving, isTrue);
      },
    );
  });

  group('admission', () {
    setUp(() async {
      const device = MidiDevice(
        id: 'adopted',
        name: 'JamCorder',
        transport: MidiTransportType.ble,
        isConnected: false,
      );
      ble.discoverable = const [device];
      await container
          .read(midiConnectionStateProvider.notifier)
          .connect(device);
      await pumpEventQueue();
      events.clear();
    });

    test('another live instrument cannot reach the normalized state', () async {
      ble.emitMessage(
        const MidiMessage(type: MidiMessageType.noteOn, note: 60, velocity: 90),
        deviceId: 'someone-elses-pad',
      );
      await pumpEventQueue();

      expect(events, isEmpty);
      expect(container.read(midiNoteStateProvider).pressed, isEmpty);
      expect(container.read(midiInputProvider).rejectedForeignMessages, 1);
    });

    test(
      'a foreign all-notes-off cannot interrupt the adopted instrument',
      () async {
        ble.emitMessage(
          const MidiMessage(
            type: MidiMessageType.noteOn,
            note: 60,
            velocity: 90,
          ),
        );
        await pumpEventQueue();
        ble.emitMessage(
          const MidiMessage(
            type: MidiMessageType.controlChange,
            ccNumber: MidiConstants.ccAllNotesOff,
            ccValue: 0,
          ),
          deviceId: 'someone-elses-pad',
        );
        await pumpEventQueue();

        expect(events.whereType<InputTemporalResetEvent>(), isEmpty);
        expect(container.read(midiNoteStateProvider).pressed, {60});
      },
    );

    // The transport reports a device id, never which link delivered a
    // message, so a reconnect that reuses the id is indistinguishable at the
    // wire. Each subscription mints its own token and the adopted identity
    // moves with it, which is what makes a superseded session foreign rather
    // than the adopted instrument playing.
    test('every transport session is a distinct adopted identity', () async {
      final first = container.read(midiInputProvider).adopted;
      expect(first?.deviceId, 'adopted');
      expect(first?.sessionId, isNotNull);

      container.read(midiInputProvider.notifier)
        ..suspendObservation()
        ..resumeObservation();
      await pumpEventQueue();

      final second = container.read(midiInputProvider).adopted;
      expect(second?.deviceId, 'adopted');
      expect(second?.sessionId, isNot(first?.sessionId));
      expect(second, isNot(first), reason: 'a new session is a new source');
    });

    test('every channel of the adopted instrument is one keyboard', () async {
      ble.emitMessage(
        const MidiMessage(
          type: MidiMessageType.noteOn,
          channel: 0,
          note: 60,
          velocity: 90,
        ),
      );
      ble.emitMessage(
        const MidiMessage(
          type: MidiMessageType.noteOn,
          channel: 3,
          note: 48,
          velocity: 90,
        ),
      );
      await pumpEventQueue();

      expect(container.read(midiNoteStateProvider).pressed, {60, 48});
    });
  });

  test('sounding state and the event stream cannot disagree', () async {
    // An orphan release under the pedal used to reach sounding state while
    // the stream reported nothing at all.
    ble.emitMessage(
      const MidiMessage(
        type: MidiMessageType.controlChange,
        ccNumber: MidiConstants.ccSustainPedal,
        ccValue: 127,
      ),
    );
    ble.emitMessage(
      const MidiMessage(type: MidiMessageType.noteOff, note: 60, velocity: 0),
    );
    await pumpEventQueue();

    expect(container.read(midiNoteStateProvider).sustained, isEmpty);

    var replayed = InputTemporalState.silent;
    for (final event in events) {
      replayed = replayed.applying(event);
    }
    expect(replayed.soundingNoteNumbers, isEmpty);
  });
}
