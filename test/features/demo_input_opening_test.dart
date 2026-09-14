import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/demo_input/demo_input.dart';

/// What a source's opening says about what it is already holding.
///
/// Opening an observation establishes the instrument's current state. It does
/// not replay that state as playing: a note the pedal has been holding since
/// before anybody subscribed was not struck now.
void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
  });

  /// Everything the demo stream says once it is subscribed.
  Future<List<InputTemporalEvent>> opened() async {
    final events = <InputTemporalEvent>[];
    // Held, because the provider disposes itself when nothing is watching and
    // takes the listener that feeds it with it.
    final held = container.listen(demoTemporalEventsProvider, (_, _) {});
    addTearDown(held.close);
    final subscription = held.read().listen(events.add);
    addTearDown(subscription.cancel);
    await Future<void>.delayed(Duration.zero);
    return events;
  }

  test('an opening with nothing held reports silence', () async {
    final events = await opened();

    expect(events.single, isA<InputTemporalResetEvent>());
    expect(
      (events.single as InputTemporalResetEvent).snapshot.isSilent,
      isTrue,
    );
  });

  test('a held key opens as held rather than as struck', () async {
    container.read(demoInputProvider.notifier).playChord({60, 64});

    final events = await opened();
    final opening = events.single as InputTemporalResetEvent;

    expect(opening.snapshot.pressedNoteNumbers, {60, 64});
    expect(
      events.whereType<InputTemporalNoteOnEvent>(),
      isEmpty,
      reason: 'nobody struck these keys at this moment',
    );
  });

  // The case the opening used to lose entirely: the pedal is down and it is
  // holding a note whose key is already up.
  test('the pedal and what it is holding survive the opening', () async {
    final demo = container.read(demoInputProvider.notifier)
      ..setPedalDown(true)
      ..playChord({60})
      ..playChord(const {});

    expect(container.read(demoInputProvider).sustainedNoteNumbers, {60});

    final events = await opened();
    final opening = events.single as InputTemporalResetEvent;

    expect(opening.snapshot.pedalDown, isTrue);
    expect(opening.snapshot.sustainedNoteNumbers, {60});
    expect(opening.snapshot.soundingNoteNumbers, {60});

    // And the reducer owns it, so lifting the pedal ends it the way it would
    // for a note played after the opening.
    demo.setPedalDown(false);
    await Future<void>.delayed(Duration.zero);

    expect(events.last, isA<InputTemporalPedalEvent>());
  });
}
