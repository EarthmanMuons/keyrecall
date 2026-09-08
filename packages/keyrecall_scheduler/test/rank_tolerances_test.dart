import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// What a tolerance may and may not do to the ordering.
void main() {
  RankKey key({
    EligibilityTier tier = EligibilityTier.fullyEligible,
    bool transition = false,
    double retention = 0,
    double information = 0,
    double diversity = 0,
    double goals = 0,
    RealizationRank realization = RealizationRank.unmeasured,
    double realizationFit = 0,
  }) => RankKey(
    tier: tier,
    coordinationTransition: transition,
    retention: retention,
    information: information,
    diversity: diversity,
    goals: goals,
    realization: realization,
    realizationFit: realizationFit,
  );

  group('the default changes nothing', () {
    test('exact tolerances are the dictionary ordering', () {
      final pairs = [
        (key(retention: 0.000122), key(retention: 0.000101)),
        (key(information: 2), key(information: 2.000001)),
        (key(diversity: -1), key(diversity: -2)),
        (key(realizationFit: -1), key(realizationFit: 0)),
        (key(), key()),
      ];

      for (final (a, b) in pairs) {
        expect(RankTolerances.exact.compare(a, b), a.compareTo(b));
        expect(RankTolerances.exact.compare(b, a), b.compareTo(a));
      }
    });

    test('the V1 policy carries no tolerance it has not justified', () {
      final tolerances = v1SchedulerConfig.rankTolerances;

      expect(tolerances.retention, 0);
      expect(tolerances.information, 0);
      expect(tolerances.diversity, 0);
      expect(tolerances.goals, 0);
      expect(tolerances.realizationFit, 0);
    });
  });

  group('a term too close to decide passes the question on', () {
    const tolerance = RankTolerances(retention: 1e-4);

    test('below the tolerance, the next term decides', () {
      // The device shape: a fifth of nothing in retention, against a
      // realization the learner has outgrown.
      final surpassed = key(
        retention: 0.000122,
        realization: RealizationRank.surpassed,
      );
      final advancing = key(
        retention: 0.000101,
        realization: RealizationRank.advancing,
      );

      expect(surpassed.compareTo(advancing), greaterThan(0));
      expect(tolerance.compare(surpassed, advancing), lessThan(0));
    });

    test('at the tolerance exactly, the term still ties', () {
      expect(tolerance.compare(key(retention: 3e-4), key(retention: 2e-4)), 0);
    });

    test('a hair past it, the term decides again', () {
      expect(
        tolerance.compare(key(retention: 3.001e-4), key(retention: 2e-4)),
        greaterThan(0),
      );
    });

    test('a decisive margin is untouched', () {
      expect(
        tolerance.compare(
          key(retention: 0.5, realization: RealizationRank.surpassed),
          key(retention: 0.001, realization: RealizationRank.advancing),
        ),
        greaterThan(0),
      );
    });

    test('the ordering stays antisymmetric across the boundary', () {
      for (final gap in [0.0, 5e-5, 1e-4, 1.5e-4, 1.0]) {
        final a = key(retention: gap);
        final b = key();

        expect(tolerance.compare(a, b), -tolerance.compare(b, a));
      }
    });
  });

  group('what a tolerance may never do', () {
    const generous = RankTolerances(
      retention: 1,
      information: 1,
      diversity: 1,
      goals: 1,
      realizationFit: 1,
    );

    test('a tier is a different claim, not a margin', () {
      expect(
        generous.compare(
          key(tier: EligibilityTier.fullyEligible),
          key(
            tier: EligibilityTier.provisionallyEligible,
            retention: 1,
            information: 1,
          ),
        ),
        greaterThan(0),
      );
    });

    test('so is a coordination transition', () {
      expect(
        generous.compare(key(transition: true), key(retention: 1)),
        greaterThan(0),
      );
    });

    test('so is the realization rank', () {
      expect(
        generous.compare(
          key(realization: RealizationRank.advancing),
          key(realization: RealizationRank.surpassed),
        ),
        greaterThan(0),
      );
    });

    test('a tolerance is a distance', () {
      expect(() => RankTolerances(retention: -1), throwsA(isA<Error>()));
    });
  });
}
