import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// Final-state scalars a recorded run produced.
///
/// Every number here is downstream of every prediction, evidence weight, and
/// memory transition in the run, so any divergence anywhere shows up as a
/// mismatch. They began as the evidence that the Dart model reproduced the
/// Python prototype it was designed in, and are a regression pin against this
/// implementation now that the prototype is retired: a mismatch means this
/// implementation changed, which may be intended, and the values are then
/// regenerated from a Dart run. See `analysis/README.md`.
class ReferenceRun {
  final SyntheticProfile profile;
  final int seed;
  final int attempts;
  final Map<Competency, (double mean, double variance)> competencies;
  final Map<String, (double current, double consolidated, double coldStart)>
  memory;
  final int executionContexts;
  final double lastAttemptDays;

  const ReferenceRun({
    required this.profile,
    required this.seed,
    required this.attempts,
    required this.competencies,
    required this.memory,
    required this.executionContexts,
    required this.lastAttemptDays,
  });
}

const List<ReferenceRun> referenceRuns = [
  ReferenceRun(
    profile: SyntheticProfile.advanced,
    seed: 0,
    attempts: 40,
    competencies: {
      Competency.majorScaleTopology: (1.0610992384560378, 0.4343164008030369),
      Competency.naturalMinorTopology: (1.0381823276772506, 0.4948173424999995),
      Competency.harmonicMinorTopology: (
        1.0738231491970518,
        0.46590839599999984,
      ),
      Competency.melodicMinorTopology: (1.0293357487026649, 0.9907999999999975),
      Competency.rhScaleExecution: (1.0649363392509306, 0.07450000000000002),
      Competency.lhScaleExecution: (1.050050643717411, 0.07600000000000001),
      Competency.scalarCrossing: (1.0852602516215701, 0.065),
      Competency.multiOctaveContinuation: (
        1.0225045292670116,
        0.16305005329999994,
      ),
      Competency.directionReversal: (1.0469678890475376, 0.13259649237965004),
      Competency.handsTogetherCoordination: (1.0, 1.6999999999999957),
    },
    memory: {
      'A_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.274762587746675,
      ),
      'C_MAJOR': (3.0384872665863947, 5.205190724901335, 0.274762587746675),
      'D_HARMONIC_MINOR': (
        6.539535760278373,
        20.4878793249271,
        0.3476318328103355,
      ),
      'D_NATURAL_MINOR': (3.395098621129957, 5.080114386378568, 0.4),
      'E_MELODIC_MINOR': (
        2.5130025205221727,
        3.026245231906966,
        0.3476318328103355,
      ),
      'E_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.30678799551944613,
      ),
      'F#_HARMONIC_MINOR': (
        3.0119717837287756,
        4.2298922205342855,
        0.30678799551944613,
      ),
      'F#_NATURAL_MINOR': (2.8225190237860436, 2.853666179257013, 0.4),
      'F_MAJOR': (3.028517837407892, 4.898217257451602, 0.36043765430315966),
      'G_MAJOR': (3.322886877107088, 5.237467868924253, 0.4),
    },
    executionContexts: 15,
    lastAttemptDays: 20.0,
  ),
  ReferenceRun(
    profile: SyntheticProfile.beginner,
    seed: 3,
    attempts: 40,
    competencies: {
      Competency.majorScaleTopology: (-1.0526119635090772, 1.030257640156034),
      Competency.naturalMinorTopology: (
        -1.0590634933942107,
        0.5408930001899416,
      ),
      Competency.harmonicMinorTopology: (
        -1.014379582253998,
        0.9768393537535981,
      ),
      Competency.melodicMinorTopology: (
        -1.0488563089237433,
        0.8547064830156794,
      ),
      Competency.rhScaleExecution: (-1.0342814959112332, 0.0914668498136596),
      Competency.lhScaleExecution: (-1.023548572627834, 0.20909470477964953),
      Competency.scalarCrossing: (-1.040854739808013, 0.06451660165275376),
      Competency.multiOctaveContinuation: (
        -1.018672531607301,
        0.22054146877550632,
      ),
      Competency.directionReversal: (-1.0140011953205872, 0.27736044063830706),
      Competency.handsTogetherCoordination: (-1.0, 1.6999999999999957),
    },
    memory: {
      'A_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.3476318328103355,
      ),
      'C_MAJOR': (3.504433454494158, 5.309959618149721, 0.4),
      'D_HARMONIC_MINOR': (3.0964492851579717, 5.060192386509298, 0.4),
      'D_NATURAL_MINOR': (
        4.447589609623096,
        11.37354345820299,
        0.3760694786754726,
      ),
      'E_MELODIC_MINOR': (5.405129345234407, 10.647968569664613, 0.4),
      'E_NATURAL_MINOR': (5.077901313374479, 12.066726059343537, 0.4),
      'F#_HARMONIC_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.3760694786754726,
      ),
      'F#_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.274762587746675,
      ),
      'F_MAJOR': (2.870582732723068, 3.0000000000000004, 0.4),
      'G_MAJOR': (4.239163985805156, 8.998733627339197, 0.4),
    },
    executionContexts: 20,
    lastAttemptDays: 20.0,
  ),
  ReferenceRun(
    profile: SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 1,
    attempts: 40,
    competencies: {
      Competency.majorScaleTopology: (1.016152295436367, 1.376371594999996),
      Competency.naturalMinorTopology: (0.9979413433387289, 0.994745899999998),
      Competency.harmonicMinorTopology: (0.9963123007283098, 1.425499999999996),
      Competency.melodicMinorTopology: (1.0049782908925955, 1.4065999999999963),
      Competency.rhScaleExecution: (1.023232132939448, 0.36475219999999986),
      Competency.lhScaleExecution: (1.0445671488603414, 0.16319842459999997),
      Competency.scalarCrossing: (1.0445671488603414, 0.16319842459999997),
      Competency.multiOctaveContinuation: (
        1.0304869433355777,
        0.2843845399999999,
      ),
      Competency.directionReversal: (1.0115599448921426, 0.9088999999999988),
      Competency.handsTogetherCoordination: (1.0, 1.6999999999999957),
    },
    memory: {
      'A_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.19901445739428403,
      ),
      'C_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.30678799551944613),
      'D_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.274762587746675,
      ),
      'E_MELODIC_MINOR': (
        2.5761313658623797,
        3.0190881368338562,
        0.3476318328103355,
      ),
      'E_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.22905444336610398,
      ),
      'F#_HARMONIC_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.23409496807286131,
      ),
      'F#_NATURAL_MINOR': (
        3.027556454830099,
        4.865946962746508,
        0.2826004726574231,
      ),
      'F_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.30678799551944613),
      'G_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.23407755465102126),
    },
    executionContexts: 8,
    lastAttemptDays: 20.0,
  ),
];

/// Agreement is to floating-point tolerance rather than bit for bit.
///
/// Measured worst-case divergence over these runs is about `2e-11` relative.
/// Most of it traces to the activation anchor: supported practice moves it
/// partway toward the present, and this implementation stores a real
/// `DateTime` rounded to the microsecond while the prototype carries an
/// unbounded float day count. That difference, well under a millisecond
/// against a multi-day half-life, then propagates into retrievability and into
/// the sampled observations. Summation order accounts for the rest.
///
/// This tolerance sits comfortably above that noise without pretending the two
/// compute identically. Keeping real timestamps matters more than matching the
/// prototype's arithmetic digit for digit, and `trace_digest_test.dart` covers
/// what can be compared exactly.
const double tolerance = 1e-9;

void main() {
  group('a Dart run reproduces the reference implementation', () {
    for (final reference in referenceRuns) {
      test('${reference.profile.id}, seed ${reference.seed}', () {
        final simulation = PracticeSimulation.of(
          reference.profile,
          seed: reference.seed,
          attemptSpacing: const Duration(hours: 12),
          learner: const LearnerModel.v1Prototype(),
        );
        final traces = simulation.run(reference.attempts);
        final state = simulation.state;

        expect(traces, hasLength(reference.attempts));
        expect(
          simulation.epoch.daysUntil(traces.last.at),
          closeTo(reference.lastAttemptDays, tolerance),
        );

        for (final entry in reference.competencies.entries) {
          final belief = state.competency(entry.key);
          expect(
            belief.mean,
            closeTo(entry.value.$1, tolerance),
            reason: '${entry.key.id} mean',
          );
          expect(
            belief.variance,
            closeTo(entry.value.$2, tolerance),
            reason: '${entry.key.id} variance',
          );
        }

        expect(
          state.materialMemory.keys.toSet(),
          reference.memory.keys.toSet(),
        );
        for (final entry in reference.memory.entries) {
          final memory = state.materialMemory[entry.key]!;
          expect(
            memory.currentHalfLifeDays,
            closeTo(entry.value.$1, tolerance),
            reason: '${entry.key} current durability',
          );
          expect(
            memory.consolidatedHalfLifeDays,
            closeTo(entry.value.$2, tolerance),
            reason: '${entry.key} consolidation',
          );
          expect(
            memory.coldStartEstimate,
            closeTo(entry.value.$3, tolerance),
            reason: '${entry.key} cold-start belief',
          );
        }

        expect(state.materialExecution, hasLength(reference.executionContexts));
      });
    }
  });

  group('determinism', () {
    test('the same profile and seed reproduce the same run', () {
      List<Map<String, Object?>> traceOf() {
        final simulation = PracticeSimulation.of(
          SyntheticProfile.beginner,
          seed: 7,
          attemptSpacing: const Duration(hours: 12),
          learner: const LearnerModel.v1Prototype(),
        );
        return simulation
            .run(60)
            .map((trace) => attemptTraceToJson(trace, epoch: simulation.epoch))
            .toList();
      }

      expect(traceOf().toString(), traceOf().toString());
    });

    test('running in batches matches one longer run', () {
      final exercise = Exercise.linear(
        material: v1ScaleCatalog.first,
        hands: HandConfiguration.right,
      );

      List<Map<String, Object?>> traceOf(List<int> batches) {
        final simulation = PracticeSimulation.of(
          SyntheticProfile.advanced,
          seed: 11,
          attemptSpacing: const Duration(hours: 12),
          learner: const LearnerModel.v1Prototype(),
        );
        return [
          for (final batch in batches)
            ...simulation
                .run(batch, chooser: fixedExercise(exercise))
                .map(
                  (trace) => attemptTraceToJson(trace, epoch: simulation.epoch),
                ),
        ];
      }

      expect(
        traceOf([10, 10, 10, 10]).toString(),
        traceOf([40]).toString(),
        reason: 'checkpointing partway must not perturb the sequence',
      );
    });
  });
}
