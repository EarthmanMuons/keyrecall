import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// Rank terms computed through floating-point sums, compared as the values
/// they mean rather than the bits they happened to land on.
void main() {
  RankKey key({double information = 0, double shapeProgression = 0}) => RankKey(
    tier: EligibilityTier.fullyEligible,
    retention: 0.36,
    information: information,
    diversity: 0,
    goals: 0,
    shapeProgression: shapeProgression,
  );

  test('a difference below the resolution leaves the next term to decide', () {
    // The two values one and two octaves of a new scale reached, 4e-16 apart.
    final oneOctave = key(information: canonicalRankValue(3.500000020749259));
    final twoOctaves = key(
      information: canonicalRankValue(3.5000000207492596),
      shapeProgression: -2,
    );

    expect(oneOctave.information, twoOctaves.information);
    expect(oneOctave.compareTo(twoOctaves), greaterThan(0));
  });

  test('a difference above it still decides at its own term', () {
    final more = key(
      information: canonicalRankValue(3.5 + 3 * rankTermResolution),
      shapeProgression: -2,
    );
    final less = key(information: canonicalRankValue(3.5));

    expect(more.compareTo(less), greaterThan(0));
  });

  test('ordering stays transitive across a grid boundary', () {
    final boundary = 2.0 + 0.5 * rankTermResolution;
    final raw = [
      boundary - 0.02 * rankTermResolution,
      boundary - 0.01 * rankTermResolution,
      boundary + 0.01 * rankTermResolution,
      boundary + 0.02 * rankTermResolution,
    ];
    final keys = [
      for (final value in raw) key(information: canonicalRankValue(value)),
    ];

    for (final a in keys) {
      for (final b in keys) {
        for (final c in keys) {
          if (a.compareTo(b) <= 0 && b.compareTo(c) <= 0) {
            expect(a.compareTo(c), lessThanOrEqualTo(0));
          }
        }
      }
    }
  });

  group('a learner placed moments ago', () {
    const model = LearnerModel();
    const pipeline = SchedulerPipeline(learner: model);
    final placed = DateTime.utc(2026, 9, 30, 12);
    final candidates = generateCandidates(
      InstrumentProfile(),
      inIntroductionOrder(allScales),
    );

    /// The placed state as a practice session decides from it: propagated to
    /// the moment of the decision.
    LearnerState placedAgo(Duration elapsed) {
      final state = model.placementState(
        PlacementTier.someExperience,
        at: placed,
      );
      model.propagate(state, placed.add(elapsed));
      return state;
    }

    CandidateTrace firstSlot(Duration elapsed) {
      final result = pipeline.decide(
        state: placedAgo(elapsed),
        session: SessionState(),
        candidates: candidates,
        at: placed.add(elapsed),
      );
      return (result as CandidateSelected).candidate;
    }

    test('is first offered one octave, however long the decision took', () {
      // Unrounded, two octaves came out ahead in their last bits at 3, 6, 7,
      // 11, 15, and 85 milliseconds.
      for (final milliseconds in [1, 3, 6, 7, 11, 15, 85, 500, 1000]) {
        expect(
          firstSlot(
            Duration(milliseconds: milliseconds),
          ).exercise.conditions.octaves,
          1,
          reason: '$milliseconds ms after placement',
        );
      }
    });

    test('records the rounded values it compared', () {
      final result = pipeline
          .evaluateSlot(
            state: placedAgo(const Duration(milliseconds: 3)),
            session: SessionState(),
            candidates: candidates,
            at: placed.add(const Duration(milliseconds: 3)),
          )
          .result;

      for (final trace in result.traces) {
        if (trace.rankKey case final rankKey?) {
          expect(rankKey.retention, canonicalRankValue(rankKey.retention));
          expect(rankKey.information, canonicalRankValue(rankKey.information));
        }
      }
    });
  });
}
