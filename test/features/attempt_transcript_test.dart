import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';

void main() {
  late StreamController<InputTemporalEvent> events;
  late ProviderContainer container;

  setUp(() {
    events = StreamController<InputTemporalEvent>();
    container = ProviderContainer(
      overrides: [
        inputTemporalEventsProvider.overrideWith((ref) => events.stream),
      ],
    );
    addTearDown(() async {
      container.dispose();
      if (!events.isClosed) await events.close();
    });
    // Nothing watches the capture in a unit test, so hold it built: recording
    // happens in the listener the notifier registers while building.
    container.listen(
      attemptTranscriptProvider,
      (_, _) {},
      fireImmediately: true,
    );
  });

  Future<void> deliver(InputTemporalEvent event) async {
    events.add(event);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> fail(Object error) async {
    events.addError(error);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> playNote(int noteNumber, {required int at}) => deliver(
    InputTemporalNoteOnEvent(
      timestampMs: at,
      noteNumber: noteNumber,
      velocity: 100,
    ),
  );

  void record() => container
      .read(attemptTranscriptProvider.notifier)
      .start(TechnicalMaterial('C', ScaleForm.major));

  AttemptCapture capture() => container.read(attemptTranscriptProvider);

  // Once continuity has broken the capture is closed to further input: the
  // notes on either side are not one observation, so a later note-on must not
  // quietly reopen the attempt that was interrupted.
  test('an interrupted capture cannot resume', () async {
    record();
    await playNote(60, at: 1000);
    await deliver(
      InputTemporalResetEvent(
        timestampMs: 1001,
        snapshot: InputTemporalSnapshot.silent,
      ),
    );

    final interrupted = capture();
    expect(interrupted.length, 1);
    expect(interrupted.isInterrupted, isTrue);

    await playNote(62, at: 1002);

    expect(
      capture().transcript,
      same(interrupted.transcript),
      reason: 'a note after the break belongs to no attempt',
    );
    expect(capture().isInterrupted, isTrue);
  });

  // The nastiest of the reported failures: an AsyncError retains the previous
  // value, so reading `.value` past a failure wrote the last note in twice.
  test(
    'a stream failure interrupts rather than repeating the last note',
    () async {
      record();
      await playNote(60, at: 1000);
      await fail(StateError('the instrument went away'));

      expect(capture().length, 1, reason: 'no note was played twice');
      expect(capture().isInterrupted, isTrue);
      expect(capture().fault, InputIntegrityFault.sourceFailure);

      await playNote(62, at: 1100);

      expect(capture().length, 1);
      expect(capture().isInterrupted, isTrue);
    },
  );

  test('an integrity fault interrupts and keeps its reason', () async {
    record();
    await playNote(60, at: 1000);
    await deliver(
      InputTemporalFaultEvent(
        timestampMs: 1001,
        fault: InputIntegrityFault.observationGap,
      ),
    );

    expect(capture().length, 1);
    expect(capture().isInterrupted, isTrue);
    expect(capture().fault, InputIntegrityFault.observationGap);
  });

  // A timestamp going backward is evidence the observation is unreliable, not
  // bad data to drop: dropping it let an input fault read as a missing note.
  test('a backward timestamp interrupts instead of losing a note', () async {
    record();
    await playNote(60, at: 100);
    await playNote(62, at: 90);

    expect(capture().length, 1);
    expect(capture().isInterrupted, isTrue);
    expect(capture().fault, InputIntegrityFault.timestampRegression);

    await playNote(64, at: 200);

    expect(capture().length, 1);
  });

  test('a fresh attempt starts from an uninterrupted capture', () async {
    record();
    await playNote(60, at: 100);
    await fail(StateError('the instrument went away'));
    record();

    expect(capture().isEmpty, isTrue);
    expect(capture().isInterrupted, isFalse);
    expect(capture().fault, isNull);

    await playNote(62, at: 200);

    expect(capture().length, 1);
  });

  test('input outside an attempt cannot interrupt anything', () async {
    await playNote(60, at: 100);
    await fail(StateError('the instrument went away'));

    expect(capture().isInterrupted, isFalse);
  });
}
