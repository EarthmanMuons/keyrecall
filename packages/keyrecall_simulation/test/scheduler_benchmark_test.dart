import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  group('reported statistics', () {
    // The census convention: a quantile names a measured decision rather than
    // interpolating between two, so an even count takes the upper middle.
    test('quantiles read the measured decisions', () {
      final run = _runOf([10, 20, 30, 40, 50, 60, 70, 80, 90, 100]);

      expect(run.medianDecide, const Duration(milliseconds: 60));
      expect(run.p95Decide, const Duration(milliseconds: 100));
      expect(run.maxDecide, const Duration(milliseconds: 100));
    });

    test('an unmeasured case reports zero rather than throwing', () {
      final run = _runOf(const []);

      expect(run.medianDecide, Duration.zero);
      expect(run.p95Decide, Duration.zero);
      expect(run.generated, 0);
    });

    test('counts describe the last measured decision', () {
      final run = SchedulerBenchmarkRun(
        caseName: 'mature',
        catalogMaterials: 72,
        decisions: [
          _decision(0, 10, generated: 9864, ranked: 1),
          _decision(1, 20, generated: 9864, ranked: 8245),
        ],
      );

      expect(run.ranked, 8245);
    });
  });
}

SchedulerBenchmarkRun _runOf(List<int> milliseconds) => SchedulerBenchmarkRun(
  caseName: 'case',
  catalogMaterials: 72,
  decisions: [
    for (final (index, value) in milliseconds.indexed) _decision(index, value),
  ],
);

BenchmarkDecision _decision(
  int slot,
  int milliseconds, {
  int generated = 0,
  int ranked = 0,
}) => BenchmarkDecision(
  slot: slot,
  decide: Duration(milliseconds: milliseconds),
  wall: Duration(milliseconds: milliseconds + 1),
  generated: generated,
  evaluated: generated,
  ranked: ranked,
);
