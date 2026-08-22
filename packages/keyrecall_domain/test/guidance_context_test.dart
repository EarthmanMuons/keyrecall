import 'package:test/test.dart';

import 'package:keyrecall_domain/keyrecall_domain.dart';

void main() {
  group('retrieval demand', () {
    test('falls as support rises', () {
      final demands = [
        for (final guidance in GuidanceContext.ladder) guidance.retrievalDemand,
      ];
      expect(demands.first, 1.0);
      expect(demands[1], lessThan(demands[0]));
      expect(demands[2], lessThan(demands[1]));
      for (final demand in demands) {
        expect(demand, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('retrieval observability', () {
    test('is a separate question from how low the bar was', () {
      expect(GuidanceContext.unguided.isRetrievalObserved, isTrue);
      expect(GuidanceContext.notesPreviewedOnly.isRetrievalObserved, isTrue);
      expect(GuidanceContext.continuouslyCued.isRetrievalObserved, isFalse);

      // Continuous cues have the lowest demand and are still not a test,
      // which is exactly the distinction the model depends on.
      expect(
        GuidanceContext.continuouslyCued.retrievalDemand,
        greaterThan(0.0),
      );
    });

    test('has no fourth value for previewed-and-cued', () {
      // Cues left visible supply the material whether or not the notes were
      // also shown first, so that combination is the same condition as
      // continuous cueing. Only the three rungs are constructible, which is
      // what keeps a duplicate from comparing and hashing differently inside
      // exercise identity, cache keys, and persisted records.
      expect(GuidanceContext.ladder, hasLength(3));
      expect(
        GuidanceContext.ladder.map((guidance) => guidance.independence).toSet(),
        {0, 1, 2},
      );
      expect(
        GuidanceContext.ladder
            .where((guidance) => !guidance.isRetrievalObserved)
            .toList(),
        [GuidanceContext.continuouslyCued],
      );
    });
  });

  group('the support ladder', () {
    test('is ordered from independent to fully supported', () {
      expect(GuidanceContext.ladder.map((guidance) => guidance.independence), [
        2,
        1,
        0,
      ]);
    });

    test('steps one rung at a time in each direction', () {
      expect(
        GuidanceContext.unguided.oneStepMoreSupportive,
        GuidanceContext.notesPreviewedOnly,
      );
      expect(
        GuidanceContext.notesPreviewedOnly.oneStepMoreSupportive,
        GuidanceContext.continuouslyCued,
      );
      expect(GuidanceContext.continuouslyCued.oneStepMoreSupportive, isNull);

      expect(
        GuidanceContext.continuouslyCued.oneStepLessSupportive,
        GuidanceContext.notesPreviewedOnly,
      );
      expect(
        GuidanceContext.notesPreviewedOnly.oneStepLessSupportive,
        GuidanceContext.unguided,
      );
      expect(GuidanceContext.unguided.oneStepLessSupportive, isNull);
    });
  });

  group('identity', () {
    test('each rung is one value, equal only to itself', () {
      for (final guidance in GuidanceContext.ladder) {
        expect(
          GuidanceContext.ofIndependence(guidance.independence),
          same(guidance),
        );
        for (final other in GuidanceContext.ladder) {
          if (identical(guidance, other)) continue;
          expect(guidance, isNot(other));
        }
      }
    });

    test('reads a rung back from a recorded independence level', () {
      expect(
        GuidanceContext.ofIndependence(0),
        GuidanceContext.continuouslyCued,
      );
      expect(
        GuidanceContext.ofIndependence(1),
        GuidanceContext.notesPreviewedOnly,
      );
      expect(GuidanceContext.ofIndependence(2), GuidanceContext.unguided);
      expect(() => GuidanceContext.ofIndependence(3), throwsArgumentError);
      expect(() => GuidanceContext.ofIndependence(-1), throwsArgumentError);
    });
  });

  group('instrument profile', () {
    test('gates octave span by key count', () {
      final upright = InstrumentProfile(keyCount: 88);
      final compact = InstrumentProfile(keyCount: 25);

      expect(upright.supportsOctaveSpan(2), isTrue);
      expect(upright.supportsOctaveSpan(7), isTrue);
      expect(compact.supportsOctaveSpan(2), isTrue);
      expect(compact.supportsOctaveSpan(3), isFalse);
    });

    test('rejects an instrument with no keys', () {
      expect(() => InstrumentProfile(keyCount: 0), throwsArgumentError);
      expect(() => InstrumentProfile(keyCount: -88), throwsArgumentError);
    });
  });
}
