import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  group('tempo delivery', () {
    test('a pulse nothing was asked of is complete', () {
      expect(TempoDelivery.notRequested().delivery, ChannelDelivery.complete);
    });

    test('every requested beat is a complete count-in', () {
      expect(TempoDelivery.complete(4).delivery, ChannelDelivery.complete);
    });

    test('a silent count-in is not one the learner heard', () {
      final silent = TempoDelivery.silent(4, reason: 'no audio engine');

      expect(silent.delivery, ChannelDelivery.unavailable);
      expect(silent.delivery.fellShort, isTrue);
      expect(silent.failureReason, 'no audio engine');
    });

    test('beats dropped by a late start read as a partial count-in', () {
      expect(
        TempoDelivery(
          countInBeats: 4,
          continuingBeats: 0,
          deliveredCountInBeats: 2,
          deliveredContinuingBeats: 0,
        ).delivery,
        ChannelDelivery.partial,
      );
    });

    test('is derived from the counts rather than asserted beside them', () {
      expect(
        () => TempoDelivery(
          countInBeats: 4,
          continuingBeats: 0,
          deliveredCountInBeats: 5,
          deliveredContinuingBeats: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TempoDelivery(
          countInBeats: 4,
          continuingBeats: 8,
          deliveredCountInBeats: 4,
          deliveredContinuingBeats: 9,
        ),
        throwsArgumentError,
      );
    });
  });

  group('a pulse supplied during the attempt', () {
    test('is never supplied by a count-in alone', () {
      expect(TempoDelivery.complete(4).suppliedDuringAttempt, isFalse);
    });

    test('is supplied by a metronome that sounded', () {
      expect(
        TempoDelivery.complete(4, continuingBeats: 12).suppliedDuringAttempt,
        isTrue,
      );
    });

    test('is supplied by a metronome that started late, however partial', () {
      final late = TempoDelivery(
        countInBeats: 4,
        continuingBeats: 12,
        deliveredCountInBeats: 0,
        deliveredContinuingBeats: 1,
      );

      expect(late.delivery, ChannelDelivery.partial);
      expect(late.suppliedDuringAttempt, isTrue);
    });

    test('is not supplied by a metronome that failed before the downbeat', () {
      final cutOff = TempoDelivery(
        countInBeats: 4,
        continuingBeats: 12,
        deliveredCountInBeats: 3,
        deliveredContinuingBeats: 0,
      );

      expect(cutOff.delivery, ChannelDelivery.partial);
      expect(cutOff.suppliedDuringAttempt, isFalse);
    });

    test('is not supplied by a metronome that never sounded', () {
      expect(
        TempoDelivery.silent(4, continuingBeats: 12).suppliedDuringAttempt,
        isFalse,
      );
    });
  });

  test('a delivery falls short when any channel does', () {
    expect(
      PresentationDelivery(tempo: TempoDelivery.complete(4)).fellShort,
      isFalse,
    );
    expect(
      PresentationDelivery(tempo: TempoDelivery.silent(4)).fellShort,
      isTrue,
    );
  });

  group('a pulse supplied by either channel', () {
    final metronome = TempoDelivery.complete(4, continuingBeats: 12);
    final silent = TempoDelivery.silent(4, continuingBeats: 12);
    final partial = TempoDelivery(
      countInBeats: 4,
      continuingBeats: 12,
      deliveredCountInBeats: 0,
      deliveredContinuingBeats: 5,
    );

    test('is supplied when only the beat on screen reached the learner', () {
      final delivery = PresentationDelivery(
        tempo: silent,
        shownContinuingBeats: 12,
      );

      expect(delivery.suppliedPulseDuringAttempt, isTrue);
      expect(delivery.fellShort, isTrue);
    });

    test('is supplied when the click was partial and the screen complete', () {
      expect(
        PresentationDelivery(
          tempo: partial,
          shownContinuingBeats: 12,
        ).suppliedPulseDuringAttempt,
        isTrue,
      );
    });

    test('is supplied by the click alone', () {
      expect(
        PresentationDelivery(tempo: metronome).suppliedPulseDuringAttempt,
        isTrue,
      );
    });

    test('is not supplied when neither sounded nor showed', () {
      expect(
        PresentationDelivery(tempo: silent).suppliedPulseDuringAttempt,
        isFalse,
      );
    });
  });
}
