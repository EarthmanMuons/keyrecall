import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

/// State a reference run under `analysis/learner-model/` produced.
///
/// Recorded from the Python prototype, which is the reference implementation
/// of the V1 model, by running the same profile, seed, and attempt count. Every
/// number here is downstream of every prediction, evidence weight, and memory
/// transition in the run, so any divergence anywhere shows up as a mismatch.
///
/// Regenerate with, and only with, a matching reference run:
///
/// ```console
/// python3 analysis/learner-model/simulate.py \
///     --profile advanced --attempts 40 --seed 0 --out reference.jsonl
/// ```
///
/// A mismatch means this port and the prototype disagree. That is a defect in
/// one of them to reconcile, not a number to update.
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
      Competency.majorScaleTopology: (1.0457254166117278, 0.24147077640295164),
      Competency.naturalMinorTopology: (1.0125020473110806, 1.3975999999999966),
      Competency.harmonicMinorTopology: (
        1.0106449562236035,
        0.3111390936652999,
      ),
      Competency.melodicMinorTopology: (0.9990417432818954, 0.7007472512749983),
      Competency.rhScaleExecution: (1.0588157013773878, 0.055),
      Competency.lhScaleExecution: (1.086277348282719, 0.05),
      Competency.scalarCrossing: (1.1113454990138236, 0.05),
      Competency.multiOctaveContinuation: (1.0584937894311077, 0.05),
      Competency.directionReversal: (1.058440771217241, 0.05),
      Competency.handsTogetherCoordination: (1.0337475506462832, 0.055),
    },
    memory: {
      'A_NATURAL_MINOR': (
        3.024422398322306,
        4.756635997588373,
        0.3476318328103355,
      ),
      'C_MAJOR': (5.618371293609872, 18.799456960625314, 0.274762587746675),
      'D_HARMONIC_MINOR': (8.306538433072916, 26.158732709765665, 0.4),
      'E_MELODIC_MINOR': (
        4.427954051451002,
        10.528349297839949,
        0.30678799551944613,
      ),
      'F#_HARMONIC_MINOR': (2.2115103158282756, 2.351539116285737, 0.4),
      'F_MAJOR': (3.0198864293996253, 4.585134175596055, 0.3476318328103355),
      'G_MAJOR': (2.5881677356718216, 3.040249752324981, 0.3476318328103355),
    },
    executionContexts: 14,
    lastAttemptDays: 20.0,
  ),
  ReferenceRun(
    profile: SyntheticProfile.beginner,
    seed: 3,
    attempts: 40,
    competencies: {
      Competency.majorScaleTopology: (-1.0548242993742578, 0.753751265127892),
      Competency.naturalMinorTopology: (
        -1.0004872339400517,
        1.6709185127599957,
      ),
      Competency.harmonicMinorTopology: (
        -1.047023860981423,
        0.9044111301692066,
      ),
      Competency.melodicMinorTopology: (
        -1.0038710770715353,
        1.4924215999999961,
      ),
      Competency.rhScaleExecution: (-1.025592894988373, 0.2042594604041182),
      Competency.lhScaleExecution: (-1.0153934720576074, 0.3137372455860814),
      Competency.scalarCrossing: (-1.0326412199664061, 0.11078659067456027),
      Competency.multiOctaveContinuation: (
        -1.0190041119113267,
        0.2703194904714861,
      ),
      Competency.directionReversal: (-1.0142078917286632, 0.43143447554754094),
      Competency.handsTogetherCoordination: (
        -1.0083451470795743,
        0.6695399989857808,
      ),
    },
    memory: {
      'A_NATURAL_MINOR': (3.0000000000000004, 3.0000000000000004, 0.4),
      'C_MAJOR': (2.984538350736177, 7.159521489853896, 0.4),
      'D_HARMONIC_MINOR': (2.8817950708141917, 4.987470625412445, 0.4),
      'E_MELODIC_MINOR': (
        2.3376838876241592,
        3.0000000000000004,
        0.274762587746675,
      ),
      'F#_HARMONIC_MINOR': (
        2.756548508450929,
        3.3927046683804845,
        0.30678799551944613,
      ),
      'F_MAJOR': (3.02404448272332, 4.178221218022571, 0.3289733703999744),
      'G_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.30678799551944613),
    },
    executionContexts: 18,
    lastAttemptDays: 20.0,
  ),
  ReferenceRun(
    profile: SyntheticProfile.techniqueStrongMemoryWeak,
    seed: 1,
    attempts: 40,
    competencies: {
      Competency.majorScaleTopology: (1.0380832815531071, 0.8273618541649986),
      Competency.naturalMinorTopology: (0.9963123007283098, 1.425499999999996),
      Competency.harmonicMinorTopology: (1.0282181641763752, 1.321547864630184),
      Competency.melodicMinorTopology: (1.000822192034568, 1.6544397499999957),
      Competency.rhScaleExecution: (1.0433710067110837, 0.17231188459999994),
      Competency.lhScaleExecution: (1.0225463681882736, 0.19043447749999987),
      Competency.scalarCrossing: (1.0586551824905455, 0.07),
      Competency.multiOctaveContinuation: (
        1.0197636746796621,
        0.16505188459999995,
      ),
      Competency.directionReversal: (1.0427564094632626, 0.21055524799999986),
      Competency.handsTogetherCoordination: (
        1.0072621924088119,
        0.9132499999999992,
      ),
    },
    memory: {
      'A_NATURAL_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.21666130460922806,
      ),
      'C_MAJOR': (1.8010760162517458, 1.8010760162517458, 0.3476318328103355),
      'D_HARMONIC_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.22905444336610398,
      ),
      'E_MELODIC_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.30678799551944613,
      ),
      'F#_HARMONIC_MINOR': (
        3.0000000000000004,
        3.0000000000000004,
        0.28257214818952864,
      ),
      'F_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.2493927381157098),
      'G_MAJOR': (3.0000000000000004, 3.0000000000000004, 0.21660650745421575),
    },
    executionContexts: 10,
    lastAttemptDays: 20.0,
  ),
];

/// Summation order differs between the two implementations in a few places, so
/// agreement is to floating-point tolerance rather than bit for bit.
const double tolerance = 1e-9;

void main() {
  group('a Dart run reproduces the reference implementation', () {
    for (final reference in referenceRuns) {
      test('${reference.profile.id}, seed ${reference.seed}', () {
        final simulation = PracticeSimulation.of(
          reference.profile,
          seed: reference.seed,
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
