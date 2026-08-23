import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/demo_input/demo_input.dart';
import 'package:keyrecall/features/input/input.dart';

/// Collects everything a stream emits, so a test can assert on a performance
/// rather than on one event at a time.
class _Recorder {
  final List<InputTemporalEvent> events = [];
  late final ProviderSubscription<AsyncValue<InputTemporalEvent>> _listener;

  _Recorder(ProviderContainer container) {
    _listener = container.listen<AsyncValue<InputTemporalEvent>>(
      inputTemporalEventsProvider,
      (_, next) {
        final event = next.value;
        if (event != null) events.add(event);
      },
      fireImmediately: true,
    );
  }

  void close() => _listener.close();

  /// The whole performance, in order, in a form a test can read at a glance.
  ///
  /// Asserting on a transcript rather than on filtered note-ons is what makes
  /// a missing note-off visible: a scale and an accumulating chord look
  /// identical through any filter that only counts arrivals.
  List<String> get transcript => [
    for (final event in events)
      switch (event) {
        InputTemporalNoteOnEvent(:final noteNumber) => 'on $noteNumber',
        InputTemporalNoteOffEvent(:final noteNumber) => 'off $noteNumber',
        InputTemporalPedalEvent(:final down) => 'pedal ${down ? 'down' : 'up'}',
        InputTemporalResetEvent() => 'reset',
      },
  ];

  List<int> get notesOn => [
    for (final event in events)
      if (event is InputTemporalNoteOnEvent) event.noteNumber,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _Recorder recorder;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    recorder = _Recorder(container);
    addTearDown(recorder.close);
  });

  DemoInputNotifier demo() => container.read(demoInputProvider.notifier);
  DemoInputState currently() => container.read(demoInputProvider);

  group('the synthetic instrument', () {
    test('opens with a reset saying nothing is sounding', () async {
      await pumpEventQueue();

      final reset = recorder.events.single as InputTemporalResetEvent;
      expect(reset.snapshot.isSilent, isTrue);
    });

    test('plays a scale one note at a time, not a chord', () async {
      await demo().playAndSettle(const [
        67,
        60,
        64,
      ], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(recorder.transcript, [
        'reset',
        'on 60',
        'off 60',
        'on 64',
        'off 64',
        'on 67',
      ], reason: 'each note is released as the next one is struck');
    });

    test('holds the last note until something else happens', () async {
      await demo().playAndSettle(const [60, 64], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();
      expect(currently().pressedNoteNumbers, {64});

      demo().releaseAll();
      await pumpEventQueue();

      expect(recorder.transcript.last, 'off 64');
      expect(currently().isSilent, isTrue);
    });

    test('releases what was held before playing again', () async {
      await demo().playAndSettle(const [60, 64], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();
      await demo().playAndSettle(const [67], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(recorder.transcript, [
        'reset',
        'on 60',
        'off 60',
        'on 64',
        'off 64',
        'on 67',
      ]);
    });

    test('interrupting a sequence abandons the rest of it', () async {
      demo().play(const [
        60,
        62,
        64,
        65,
        67,
        69,
        71,
        72,
      ], tempo: DemoInputTempo.normal);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      demo().releaseAll();
      final soundedByThen = recorder.notesOn.length;

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await pumpEventQueue();

      expect(
        recorder.notesOn.length,
        soundedByThen,
        reason: 'notes from an abandoned sequence must not keep arriving',
      );
    });

    test('refuses a note outside the keyboard', () {
      expect(() => demo().play(const [128]), throwsRangeError);
    });

    test('timestamps never run backward', () async {
      await demo().playAndSettle(const [
        60,
        62,
        64,
      ], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      var previous = -1;
      for (final event in recorder.events) {
        expect(event.timestampMs, greaterThanOrEqualTo(previous));
        previous = event.timestampMs;
      }
    });
  });

  group('the pedal', () {
    test('is reported when it moves, and only when it moves', () async {
      demo().setPedalDown(true);
      demo().setPedalDown(true);
      await pumpEventQueue();

      expect(recorder.transcript, ['reset', 'pedal down']);
    });

    test('keeps a released note ringing', () async {
      // The reason pressed and sustained are modeled apart: this transition
      // has to stay expressible as an ordinary release.
      demo().setPedalDown(true);
      await demo().playAndSettle(const [60, 64], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(recorder.transcript, [
        'reset',
        'pedal down',
        'on 60',
        'off 60',
        'on 64',
      ]);
      expect(currently().sustainedNoteNumbers, {60});
      expect(currently().soundingNoteNumbers, {60, 64});
    });

    test('damps what it was holding when it lifts, silently', () async {
      // No note-offs follow: those were sent when the keys came up. The pedal
      // event is the whole story, which is what a real instrument reports.
      demo().setPedalDown(true);
      await demo().playAndSettle(const [60, 64], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();
      demo().setPedalDown(false);
      await pumpEventQueue();

      expect(recorder.transcript.sublist(5), ['pedal up']);
      expect(currently().sustainedNoteNumbers, isEmpty);
      expect(currently().pressedNoteNumbers, {64});
    });

    test('never produces a transition a keyboard could not', () async {
      // A snapshot refuses an impossible state, so a reset built from one is
      // the guard: no repair is needed if the instrument cannot get there.
      demo().setPedalDown(true);
      await demo().playAndSettle(const [
        60,
        62,
        64,
      ], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(
        recorder.events.whereType<InputTemporalResetEvent>(),
        hasLength(1),
        reason: 'only the opening reset; playing under the pedal is ordinary',
      );
      expect(
        () => InputTemporalSnapshot(
          pressedNoteNumbers: currently().pressedNoteNumbers,
          sustainedNoteNumbers: currently().sustainedNoteNumbers,
          pedalDown: currently().isPedalDown,
        ),
        returnsNormally,
      );
    });

    test('a struck note is taken back from the pedal', () async {
      demo().setPedalDown(true);
      await demo().playAndSettle(const [60], tempo: DemoInputTempo.brisk);
      demo().releaseAll();
      await pumpEventQueue();
      expect(currently().sustainedNoteNumbers, {60});

      await demo().playAndSettle(const [60], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(currently().pressedNoteNumbers, {60});
      expect(
        currently().sustainedNoteNumbers,
        isEmpty,
        reason: 'a note cannot be both held and sustained',
      );
    });
  });

  group('source selection', () {
    test('starts synthetic, so a launch with no instrument still works', () {
      expect(container.read(inputSourceProvider), InputSourceKind.demo);
      expect(InputSourceKind.demo.requiresInstrument, isFalse);
      expect(InputSourceKind.midi.requiresInstrument, isTrue);
    });

    test('the practice loop sees one stream, whichever source is active', () async {
      // The payoff of normalizing at the boundary: this test reads input
      // without naming a transport, and the stream's static type means nothing
      // above it can either.
      await demo().playAndSettle(const [60], tempo: DemoInputTempo.brisk);
      await pumpEventQueue();

      expect(recorder.transcript, ['reset', 'on 60']);
    });

    test('toggling moves between the two', () {
      final notifier = container.read(inputSourceProvider.notifier);

      notifier.toggle();
      expect(container.read(inputSourceProvider), InputSourceKind.midi);
      notifier.toggle();
      expect(container.read(inputSourceProvider), InputSourceKind.demo);
      notifier.use(InputSourceKind.midi);
      expect(container.read(inputSourceProvider), InputSourceKind.midi);
    });
  });
}
