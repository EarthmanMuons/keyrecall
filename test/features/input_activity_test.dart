import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/demo_input/demo_input.dart';
import 'package:keyrecall/features/input/input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    // Something has to be watching before the stream opens, exactly as the
    // panel does.
    final subscription = container.listen(inputActivityProvider, (_, _) {});
    addTearDown(subscription.close);
    await pumpEventQueue();
  });

  DemoInputNotifier demo() => container.read(demoInputProvider.notifier);
  InputActivity activity() => container.read(inputActivityProvider);

  test('starts from the opening reset, knowing nothing is sounding', () {
    expect(activity().eventCount, 1);
    expect(activity().resetCount, 1);
    expect(activity().soundingNoteNumbers, isEmpty);
  });

  test('follows a note from held, to under the pedal, to damped', () async {
    // The whole point of the panel: the event stream carries enough to know
    // what is sounding, with no access to the source's own state.
    demo().setPedalDown(true);
    await demo().playSequenceAndSettle(const [60], tempo: DemoInputTempo.brisk);
    await pumpEventQueue();

    expect(activity().pressedNoteNumbers, {60});
    expect(activity().sustainedNoteNumbers, isEmpty);

    demo().releaseAll();
    await pumpEventQueue();

    expect(activity().pressedNoteNumbers, isEmpty);
    expect(activity().sustainedNoteNumbers, {60});
    expect(activity().soundingNoteNumbers, {
      60,
    }, reason: 'a note-off under the pedal ends the hold, not the sound');

    demo().setPedalDown(false);
    await pumpEventQueue();

    expect(activity().soundingNoteNumbers, isEmpty);
    expect(activity().isPedalDown, isFalse);
  });

  test('agrees with the instrument through a scale under the pedal', () async {
    demo().setPedalDown(true);
    await demo().playSequenceAndSettle(const [
      60,
      62,
      64,
    ], tempo: DemoInputTempo.brisk);
    await pumpEventQueue();

    final instrument = container.read(demoInputProvider);
    expect(activity().pressedNoteNumbers, instrument.pressedNoteNumbers);
    expect(activity().sustainedNoteNumbers, instrument.sustainedNoteNumbers);
    expect(activity().soundingNoteNumbers, {60, 62, 64});
  });

  test('takes a reattacked note back from the pedal', () async {
    demo().setPedalDown(true);
    await demo().playSequenceAndSettle(const [60], tempo: DemoInputTempo.brisk);
    demo().releaseAll();
    await pumpEventQueue();
    expect(activity().sustainedNoteNumbers, {60});

    await demo().playSequenceAndSettle(const [60], tempo: DemoInputTempo.brisk);
    await pumpEventQueue();

    expect(activity().pressedNoteNumbers, {60});
    expect(activity().sustainedNoteNumbers, isEmpty);
  });

  test('agrees with the instrument through ordinary playing', () async {
    await demo().playSequenceAndSettle(const [
      60,
      62,
      64,
      65,
    ], tempo: DemoInputTempo.brisk);
    await pumpEventQueue();

    expect(activity().soundingNoteNumbers, {65});
    expect(activity().isPedalDown, isFalse);
  });
}
