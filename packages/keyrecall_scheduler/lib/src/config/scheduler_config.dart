import 'package:meta/meta.dart';

/// Thresholds for the `REQUIRES` prerequisite gate.
@immutable
class EligibilityConfig {
  /// Both hand-execution means must reach this before hands-together work is
  /// fully eligible rather than provisionally eligible.
  final double handTogetherCompetencyThreshold;

  const EligibilityConfig({required this.handTogetherCompetencyThreshold});
}

/// Limits on how much work one session may present.
@immutable
class SafetyConfig {
  /// Attempt slots allowed per session before every candidate is suppressed.
  final int maxSessionAttempts;

  const SafetyConfig({required this.maxSessionAttempts});
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
  });
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
  });
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

  const ProbeConfig({required this.minDaysSinceLastRetrieval});
}

/// One versioned set of scheduler policy constants.
///
/// Every value is a deliberately simple placeholder, not a tuned policy
/// decision. `analysis/scheduler/config.toml` is the authoritative registry;
/// [v1PrototypeSchedulerConfig] mirrors it, and a test reconciles the two.
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

/// The provisional V1 scheduler policy constants.
///
/// Mirrors `analysis/scheduler/config.toml` at registry version
/// `v1-prototype-0`. The stage structure and information boundaries these
/// values sit in are frozen for initial production; the numbers are starting
/// points for calibration against real practice data.
const SchedulerConfig v1PrototypeSchedulerConfig = SchedulerConfig(
  modelVersion: 'v1-prototype-0',
  eligibility: EligibilityConfig(handTogetherCompetencyThreshold: 0.0),
  safety: SafetyConfig(maxSessionAttempts: 40),
  challenge: ChallengeConfig(pMin: 0.60, pMax: 0.90, pIntroductionMin: 0.15),
  diversity: DiversityConfig(
    recentWindow: 10,
    maxConsecutiveMaterialAttempts: 5,
  ),
  probe: ProbeConfig(minDaysSinceLastRetrieval: 5.0),
);
