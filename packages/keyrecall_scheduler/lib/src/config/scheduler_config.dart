import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// Thresholds for the `REQUIRES` prerequisite gate.
@immutable
class EligibilityConfig {
  /// Both hand-execution means must reach this before hands-together work is
  /// fully eligible rather than provisionally eligible.
  final double handTogetherCompetencyThreshold;

  /// Single-hand execution each admission band asks for, in the logit scale
  /// competency means use, where placement puts a self-reported beginner at
  /// -1 and someone with some experience at 0.
  ///
  /// A prior rather than a measurement, and the place to revise it. The bands
  /// stand in for the fingering-family axis, which no competency measures, so
  /// these floors are how a learner earns material whose hand pattern may be
  /// new to them.
  final double earlyTransferExecutionFloor;
  final double intermediateExecutionFloor;
  final double advancedExecutionFloor;

  /// Familiarity with some minor topology before a minor form is fully
  /// eligible, and with a different minor form before fixed-form melodic
  /// minor is.
  final double minorTopologyFloor;

  /// How many distinct major and natural-minor materials must have been
  /// retrieved before harmonic minor is fully eligible, and before melodic
  /// minor is.
  ///
  /// Breadth rather than proficiency. The question a learner meeting harmonic
  /// minor for the first time faces is not whether they can play it but
  /// whether "minor" is a settled enough idea to take an alteration; a broad
  /// base of ordinary scales is what settles it. Counting retrievals rather
  /// than presentations is the difference between having seen a scale and
  /// having it.
  ///
  /// Halfway through the twenty-four core materials, and two thirds for
  /// melodic minor, which changes two degrees rather than one and in a fixed
  /// form the classical convention does not use. Both are first guesses to
  /// revise against real sittings, not measurements.
  final int harmonicMinorCoreRetrievals;
  final int melodicMinorCoreRetrievals;

  /// How many admission bands those retrievals must span.
  ///
  /// Twelve retrievals all in the easiest keys is a narrower base than the
  /// count suggests, and the point is breadth.
  final int coreRetrievalBands;

  /// Single-hand execution at which the breadth requirement is already met.
  ///
  /// Someone who arrived able to play scales should not have to demonstrate
  /// half a curriculum they already know before meeting harmonic minor. Set
  /// above where placement puts an experienced learner and at where it puts an
  /// advanced one, so it admits the second and not the first.
  final double fluentExecutionFloor;

  const EligibilityConfig({
    required this.handTogetherCompetencyThreshold,
    required this.earlyTransferExecutionFloor,
    required this.intermediateExecutionFloor,
    required this.advancedExecutionFloor,
    required this.minorTopologyFloor,
    required this.harmonicMinorCoreRetrievals,
    required this.melodicMinorCoreRetrievals,
    required this.coreRetrievalBands,
    required this.fluentExecutionFloor,
  });

  /// The execution floor [band] asks for.
  double executionFloorFor(AdmissionBand band) => switch (band) {
    AdmissionBand.foundation => double.negativeInfinity,
    AdmissionBand.earlyTransfer => earlyTransferExecutionFloor,
    AdmissionBand.intermediateKeyboard => intermediateExecutionFloor,
    AdmissionBand.advancedKeyboard => advancedExecutionFloor,
  };
}

/// Limits on how much work one session may present.
@immutable
class SafetyConfig {
  /// Attempt slots allowed per session before every candidate is suppressed.
  final int maxSessionAttempts;

  const SafetyConfig({required this.maxSessionAttempts})
    : assert(
        maxSessionAttempts > 0,
        'a session that allows no attempts can never present anything',
      );
}

/// The probability band ordinary candidates must land in.
@immutable
class ChallengeConfig {
  /// Lower edge of the ordinary admission band.
  final double pMin;

  /// Upper edge of the ordinary admission band.
  final double pMax;

  /// Floor a never-practiced material's predicted success must clear.
  ///
  /// More forgiving than steady-state practice, but still learner-sensitive:
  /// a too-hard realization of new material is rejected rather than waved
  /// through.
  final double pIntroductionMin;

  const ChallengeConfig({
    required this.pMin,
    required this.pMax,
    required this.pIntroductionMin,
  }) : assert(
         pMin >= 0 && pMin <= pMax && pMax <= 1,
         'the band must be an orderable pair of probabilities',
       ),
       assert(
         pIntroductionMin >= 0 && pIntroductionMin <= 1,
         'the introduction floor is a probability',
       );
}

/// How much repetition the scheduler tolerates.
@immutable
class DiversityConfig {
  /// How many recent selections the diversity term counts over.
  final int recentWindow;

  /// Consecutive selections of one material before the repetition guard
  /// excludes it, as long as another admitted material exists.
  ///
  /// Kept below [recentWindow] so a run is caught before it outgrows the
  /// tracked history.
  final int maxConsecutiveMaterialAttempts;

  const DiversityConfig({
    required this.recentWindow,
    required this.maxConsecutiveMaterialAttempts,
  }) : assert(recentWindow > 0, 'the window must hold at least one selection'),
       assert(
         maxConsecutiveMaterialAttempts > 0,
         'a cap of zero would exclude every material immediately',
       ),
       assert(
         maxConsecutiveMaterialAttempts <= recentWindow,
         'a run must be catchable before it outgrows the tracked history',
       );
}

/// How long the probes wait before testing retrieval again.
@immutable
class ProbeConfig {
  /// Days that must pass before a one-step-less-guided variant becomes
  /// probe-eligible.
  ///
  /// The two probes measure this interval from different clocks: the guidance
  /// probe from the last confirmed success, the bootstrap probe from the last
  /// factual attempt of any kind.
  final double minDaysSinceLastRetrieval;

  /// What an attempt has to look like before the next one may jump straight
  /// to the tempo it was played at.
  ///
  /// All of them together, because playing faster than asked is ambiguous on
  /// its own: rushing and finding it trivial look the same on the tempo axis
  /// alone and differ on every other one. Deliberately strict, since a false
  /// positive asks for something too hard while a false negative costs only
  /// the ordinary progression the learner would have had anyway.
  final double underchallengeTempoRatio;
  final double underchallengePitchIntegrity;
  final double underchallengeContinuity;
  final double underchallengeTemporalStability;

  const ProbeConfig({
    required this.minDaysSinceLastRetrieval,
    required this.underchallengeTempoRatio,
    required this.underchallengePitchIntegrity,
    required this.underchallengeContinuity,
    required this.underchallengeTemporalStability,
  }) : assert(
         minDaysSinceLastRetrieval >= 0,
         'a probe cannot become eligible before the event it waits on',
       ),
       assert(
         underchallengeTempoRatio > 1.0,
         'a tempo probe answers playing faster than asked, so the ratio that '
         'triggers it has to be above the tempo that was asked',
       );
}

/// One versioned set of scheduler policy constants.
///
/// Every value is a deliberately simple placeholder, not a tuned policy
/// decision. `analysis/scheduler/config.toml` is the authoritative registry;
/// [v1SchedulerConfig] mirrors it, and a test reconciles the two.
@immutable
class SchedulerConfig {
  /// Identifier of this configuration, recorded with every decision.
  final String modelVersion;

  /// Prerequisite thresholds.
  final EligibilityConfig eligibility;

  /// Session workload limits.
  final SafetyConfig safety;

  /// Challenge admission band and introduction floor.
  final ChallengeConfig challenge;

  /// Repetition limits.
  final DiversityConfig diversity;

  /// Probe intervals.
  final ProbeConfig probe;

  const SchedulerConfig({
    required this.modelVersion,
    required this.eligibility,
    required this.safety,
    required this.challenge,
    required this.diversity,
    required this.probe,
  });
}

/// The V1 scheduler policy constants.
///
/// The canonical registry. `analysis/scheduler/config.toml` records what the
/// Python prototype carried at version `v1-prototype-0` and is provenance
/// rather than a source to stay in step with; see `analysis/README.md`.
///
/// The stage structure and information boundaries these values sit in are
/// frozen for initial production; the numbers are starting points for
/// calibration against real practice data.
///
/// It carried the prototype's name until it stopped carrying only the
/// prototype's values. The form-introduction thresholds came from curriculum
/// evidence and a piano, not from the port, so the lineage moved into the
/// paragraph above and the name says what this is.
const SchedulerConfig v1SchedulerConfig = SchedulerConfig(
  modelVersion: 'v1-1',
  eligibility: EligibilityConfig(
    handTogetherCompetencyThreshold: 0.0,
    earlyTransferExecutionFloor: 0.0,
    intermediateExecutionFloor: 0.4,
    advancedExecutionFloor: 0.8,
    minorTopologyFloor: 0.0,
    harmonicMinorCoreRetrievals: 12,
    melodicMinorCoreRetrievals: 16,
    coreRetrievalBands: 2,
    fluentExecutionFloor: 1.0,
  ),
  safety: SafetyConfig(maxSessionAttempts: 40),
  challenge: ChallengeConfig(pMin: 0.60, pMax: 0.90, pIntroductionMin: 0.15),
  diversity: DiversityConfig(
    recentWindow: 10,
    maxConsecutiveMaterialAttempts: 5,
  ),
  probe: ProbeConfig(
    minDaysSinceLastRetrieval: 5.0,
    underchallengeTempoRatio: 1.2,
    underchallengePitchIntegrity: 0.95,
    underchallengeContinuity: 0.9,
    underchallengeTemporalStability: 0.7,
  ),
);
