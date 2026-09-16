import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_input/keyrecall_input.dart';

import 'package:keyrecall/features/input/input.dart';
import 'package:keyrecall/features/practice/attempt_transcript.dart';

/// A source that is observing.
const live = (isLive: true, observationId: 'test-1', fault: null);

/// A source whose observation has ended.
const dead = (
  isLive: false,
  observationId: null,
  fault: InputIntegrityFault.sourceClosed,
);

void main() {
  late StreamController<InputTemporalEvent> events;
  late ProviderContainer container;
  late InputObservationState observation;

  setUp(() {
    events = StreamController<InputTemporalEvent>();
    observation = live;
    container = ProviderContainer(
      overrides: [
        inputTemporalEventsProvider.overrideWith((ref) => events.stream),
        // The stream is faked, so its lifecycle has to be faked with it.
        inputObservationProvider.overrideWith((ref) => observation),
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

  /// Opens an observation, the way a source does when its stream is
  /// subscribed. Nothing can be recorded until one is open.
  Future<void> observe() => deliver(
    InputTemporalResetEvent(
      timestampMs: 0,
      snapshot: InputTemporalSnapshot.silent,
    ),
  );

  Future<void> fail(Object error) async {
    events.addError(error);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> playNote(
    int noteNumber, {
    required int at,
    PerformanceTiming? timing,
  }) => deliver(
    InputTemporalNoteOnEvent(
      timestampMs: at,
      noteNumber: noteNumber,
      velocity: 100,
      timing: timing,
    ),
  );

  void record() => container
      .read(attemptTranscriptProvider.notifier)
      .start(TechnicalMaterial('C', ScaleForm.major));

  AttemptCapture capture() => container.read(attemptTranscriptProvider);

  // The instrument's clock reaches the transcript unchanged, and the arrival
  // clock never stands in for it. A note nothing could time stays untimed
  // rather than borrowing the timestamp that orders it.
  test('a note carries the performance time it was given, or none', () async {
    await observe();
    record();
    await playNote(60, at: 1000, timing: const TimingAvailable(250000));
    await playNote(62, at: 1400);
    await playNote(
      64,
      at: 1800,
      timing: const TimingUnavailable(TimingUnavailableReason.continuityLost),
    );

    expect(capture().notes.map((note) => note.performanceTimeUs), [
      250000,
      null,
      null,
    ]);
    expect(capture().notes.map((note) => note.timestampMs), [1000, 1400, 1800]);
  });

  // The transcript keeps no reason, so the capture keeps the one that matters
  // for explaining an attempt with no timing: why its latest hole is a hole.
  test(
    'the capture keeps why its most recent untimed note was untimed',
    () async {
      await observe();
      record();
      await playNote(
        60,
        at: 1000,
        timing: const TimingUnavailable(TimingUnavailableReason.detecting),
      );
      await playNote(62, at: 1400, timing: const TimingAvailable(0));
      expect(capture().lastUntimed, TimingUnavailableReason.detecting);

      await playNote(
        64,
        at: 1800,
        timing: const TimingUnavailable(TimingUnavailableReason.continuityLost),
      );
      expect(capture().lastUntimed, TimingUnavailableReason.continuityLost);
    },
  );

  // Once continuity has broken the capture is closed to further input: the
  // notes on either side are not one observation, so a later note-on must not
  // quietly reopen the attempt that was interrupted.
  test('an interrupted capture cannot resume', () async {
    await observe();
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
      await observe();
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
    await observe();
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
    await observe();
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
    await observe();
    record();
    await playNote(60, at: 100);
    await fail(StateError('the instrument went away'));
    await observe();
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

  group('a capture belongs to the attempt that recorded it', () {
    // The screen for the next exercise is built before anything of its own is
    // recorded, while the last attempt's capture is still here. Reading it
    // showed its notes and acted on the interruption that ended it, which
    // finished the new attempt before a note was played and then recorded it
    // as one nobody played.
    test('the next attempt reads nothing of the interrupted one', () async {
      final notifier = container.read(attemptTranscriptProvider.notifier);
      final first = notifier.start(TechnicalMaterial('C', ScaleForm.major));
      await playNote(60, at: 100);
      await deliver(
        InputTemporalFaultEvent(
          timestampMs: 101,
          fault: InputIntegrityFault.observationGap,
        ),
      );

      final interrupted = capture();
      expect(interrupted.belongsTo(first), isTrue);
      expect(interrupted.isInterrupted, isTrue);

      // The next screen, which has not opened its window yet.
      expect(
        interrupted.belongsTo(null),
        isFalse,
        reason: 'an attempt that has recorded nothing owns no capture',
      );

      final second = notifier.start(TechnicalMaterial('G', ScaleForm.major));
      expect(second, isNot(first));
      expect(interrupted.belongsTo(second), isFalse);

      // Nothing has been observed since the fault, so there is no observation
      // for this recording to belong to.
      expect(capture().isInterrupted, isTrue);

      await observe();
      final third = notifier.start(TechnicalMaterial('G', ScaleForm.major));

      expect(capture().belongsTo(third), isTrue);
      expect(capture().isInterrupted, isFalse);
    });

    // The capture is not always the first consumer. The shared stream hands a
    // late subscriber whatever it last delivered, which may be a note, and a
    // note says nothing about the lifecycle: every attempt after that read the
    // healthy observation as a dead one and threw its notes away.
    test('attaching to an observation that has already played', () async {
      // Nothing has opened an observation as far as this notifier heard: the
      // only event is a note, the way a late subscriber sees one.
      await deliver(
        InputTemporalNoteOnEvent(
          timestampMs: 50,
          noteNumber: 60,
          velocity: 100,
        ),
      );

      final notifier = container.read(attemptTranscriptProvider.notifier);
      expect(notifier.isObservationLive, isTrue);

      final recording = notifier.start(TechnicalMaterial('C', ScaleForm.major));
      await playNote(62, at: 100);

      expect(capture().belongsTo(recording), isTrue);
      expect(capture().isInterrupted, isFalse);
      expect(capture().notes.map((note) => note.midiNote), [62]);
    });

    test('and to one the source says has ended', () async {
      observation = dead;
      container
        ..invalidate(inputObservationProvider)
        ..invalidate(attemptTranscriptProvider);

      final notifier = container.read(attemptTranscriptProvider.notifier);
      expect(notifier.isObservationLive, isFalse);

      notifier.start(TechnicalMaterial('C', ScaleForm.major));

      expect(capture().isInterrupted, isTrue);
      expect(capture().fault, InputIntegrityFault.sourceClosed);
    });

    // A recording belongs to the observation it started in. A reset opens the
    // next one, and what was played on either side of it is not one
    // performance however healthy the input looks at both ends.
    test('a recording cannot cross into the observation after it', () async {
      await observe();
      record();
      await playNote(60, at: 100);

      await observe();
      await playNote(62, at: 200);

      expect(capture().isInterrupted, isTrue);
      expect(capture().notes.map((note) => note.midiNote), [60]);
      expect(
        capture().notes.length,
        1,
        reason: 'the note after the boundary belongs to no attempt',
      );
    });

    // A fault that arrives between attempts reaches nobody's capture, so
    // nothing was going to arrive later to correct the next one. It recorded
    // no notes and Done closed it as ordinary playing.
    test(
      'a recording started against a dead observation is interrupted',
      () async {
        final notifier = container.read(attemptTranscriptProvider.notifier);
        await observe();
        await deliver(
          InputTemporalFaultEvent(
            timestampMs: 10,
            fault: InputIntegrityFault.sourceClosed,
          ),
        );

        expect(notifier.isObservationLive, isFalse);
        final recording = notifier.start(
          TechnicalMaterial('C', ScaleForm.major),
        );

        expect(capture().belongsTo(recording), isTrue);
        expect(capture().isInterrupted, isTrue);
        expect(capture().fault, InputIntegrityFault.sourceClosed);

        // And it stays closed: a note arriving after it cannot make it look
        // like an attempt somebody played.
        await playNote(60, at: 20);
        expect(capture().isEmpty, isTrue);
      },
    );

    test('a discarded capture belongs to nobody', () {
      final notifier = container.read(attemptTranscriptProvider.notifier);
      final recording = notifier.start(TechnicalMaterial('C', ScaleForm.major));
      notifier.discard();

      expect(capture().belongsTo(recording), isFalse);
      expect(AttemptCapture.none.belongsTo(0), isFalse);
    });

    test(
      'notes and interruption keep the recording that produced them',
      () async {
        final recording = container
            .read(attemptTranscriptProvider.notifier)
            .start(TechnicalMaterial('C', ScaleForm.major));
        await playNote(60, at: 100);
        expect(capture().belongsTo(recording), isTrue);

        await fail(StateError('gone'));
        expect(capture().belongsTo(recording), isTrue);
      },
    );
  });
}
