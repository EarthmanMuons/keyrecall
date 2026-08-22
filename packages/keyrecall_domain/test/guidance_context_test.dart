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

    test('cues win when both kinds of support are present', () {
      const both = GuidanceContext(
        notesPreviewed: true,
        concurrentPitchCues: true,
      );
      expect(both.isRetrievalObserved, isFalse);
      expect(
        both.retrievalDemand,
        GuidanceContext.continuouslyCued.retrievalDemand,
      );
      expect(both.independence, 0);
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

  test('equality is by value', () {
    expect(const GuidanceContext(), GuidanceContext.unguided);
    expect(
      const GuidanceContext(notesPreviewed: true),
      GuidanceContext.notesPreviewedOnly,
    );
    expect(
      const GuidanceContext(notesPreviewed: true).hashCode,
      GuidanceContext.notesPreviewedOnly.hashCode,
    );
    expect(GuidanceContext.unguided, isNot(GuidanceContext.continuouslyCued));
  });

  group('instrument profile', () {
    test('gates octave span by key count', () {
      const upright = InstrumentProfile(keyCount: 88);
      const compact = InstrumentProfile(keyCount: 25);

      expect(upright.supportsOctaveSpan(2), isTrue);
      expect(upright.supportsOctaveSpan(7), isTrue);
      expect(compact.supportsOctaveSpan(2), isTrue);
      expect(compact.supportsOctaveSpan(3), isFalse);
    });
  });
}
