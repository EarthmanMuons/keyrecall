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
        TempoDelivery(requestedBeats: 4, deliveredBeats: 2).delivery,
        ChannelDelivery.partial,
      );
    });

    test('is derived from the counts rather than asserted beside them', () {
      expect(
        () => TempoDelivery(requestedBeats: 4, deliveredBeats: 5),
        throwsArgumentError,
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
}
