import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';

void main() {
  // Once a reset has broken continuity, the capture is closed to further
  // input: the notes on either side are not one observation, so a later
  // note-on must not quietly reopen the attempt that was interrupted.
  test('an interrupted capture cannot resume', () async {
    final events = StreamController<InputTemporalEvent>();
    final container = ProviderContainer(
      overrides: [
        inputTemporalEventsProvider.overrideWith((ref) => events.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await events.close();
    });

    Future<void> deliver(InputTemporalEvent event) async {
      events.add(event);
      await Future<void>.delayed(Duration.zero);
    }

    // Nothing watches the capture in a unit test, so hold it built: recording
    // happens in the listener the notifier registers while building.
    container.listen(
      attemptTranscriptProvider,
      (_, _) {},
      fireImmediately: true,
    );
    container
        .read(attemptTranscriptProvider.notifier)
        .start(TechnicalMaterial('C', ScaleForm.major));
    await deliver(
      InputTemporalNoteOnEvent(
        timestampMs: 1000,
        noteNumber: 60,
        velocity: 100,
      ),
    );
    await deliver(
      InputTemporalResetEvent(
        timestampMs: 1001,
        snapshot: InputTemporalSnapshot.silent,
      ),
    );

    final interrupted = container.read(attemptTranscriptProvider);
    expect(interrupted.length, 1);
    expect(interrupted.isInterrupted, isTrue);

    await deliver(
      InputTemporalNoteOnEvent(
        timestampMs: 1002,
        noteNumber: 62,
        velocity: 100,
      ),
    );

    final afterLaterNote = container.read(attemptTranscriptProvider);
    expect(
      afterLaterNote.transcript,
      same(interrupted.transcript),
      reason: 'a note after the break belongs to no attempt',
    );
    expect(afterLaterNote.isInterrupted, isTrue);
  });
}
