import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:meta/meta.dart';

/// Thresholds for the `REQUIRES` prerequisite gate.
@immutable
class EligibilityConfig {
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

  /// Single-hand execution a traversal of more than one octave asks for.
  ///
  /// The one condition on the execution axis with unanimous curriculum
  /// support: no source teaches two octaves before one. It needs a floor
  /// because the information term prefers the untried condition, and a span
  /// nobody has attempted is where the uncertainty is.
  ///
  /// Generic rather than per-material, and not read off multi-octave
  /// continuation itself, which would be self-referential. Halfway between
  /// where placement puts a self-reported beginner and someone with some
  /// experience, so it is earned by ordinary one-octave work and never asked of
  /// a learner who arrived able to play.
  final double multiOctaveExecutionFloor;

  /// The tempo at or below which an exercise counts as gently presented.
  ///
  /// Part of what makes a key reachable a band earlier than its floor would
  /// otherwise allow. The slow end of ordinary practice rather than the
  /// slowest the generator can produce: this says a scale is being met
  /// unhurried, and it should not move when the tempo ladder underneath it
  /// grows.
  final double gentleTempoBpm;

  /// Familiarity with some minor topology before a minor form is fully
  /// eligible, and with a different minor form before fixed-form melodic
  /// minor is.
  final double minorTopologyFloor;

  /// How many distinct major and natural-minor materials each hand must have
  /// played and had retrieved before harmonic minor is fully eligible, and
  /// before melodic minor is.
  ///
  /// Breadth rather than proficiency. What a learner meeting harmonic minor
  /// faces is not whether they can play it but whether "minor" is a settled
  /// enough idea to take an alteration, and a broad base of ordinary scales is
  /// what settles it. Counting retrievals rather than presentations is the
  /// difference between having seen a scale and having it.
  ///
  /// A quarter of the twenty-four core materials per hand, and a third for
  /// melodic minor, which alters two degrees rather than one. Asked of each
  /// hand rather than of the profile. Both are first guesses to revise against
  /// real sittings rather than measurements.
  final int harmonicMinorCoreRetrievals;
  final int melodicMinorCoreRetrievals;

  /// How many admission bands those retrievals must span.
  ///
  /// Twelve retrievals all in the easiest keys is a narrower base than the
  /// count suggests, and the point is breadth.
  final int coreRetrievalBands;

  /// Hands-together coordination at which the ordinary-form foundation counts
  /// as already behind the learner.
  ///
  /// The escape hatch from the curriculum phase. It reads the coordination
  /// channel rather than a hand's execution because that is the phase's own
  /// defining marker, and one fluent hand is deliberately not enough.
  ///
  /// Set where placement puts an advanced learner, which is also why the mean
  /// is never enough on its own: placement seeds it there from what somebody
  /// said about themselves. It is paired with a requirement that the channel
  /// has actually been observed, which a real attempt satisfies and an
  /// onboarding answer never does.
  final double fluentHandsTogetherFloor;

  const EligibilityConfig({
    required this.multiOctaveExecutionFloor,
    required this.gentleTempoBpm,
    required this.earlyTransferExecutionFloor,
    required this.intermediateExecutionFloor,
    required this.advancedExecutionFloor,
    required this.minorTopologyFloor,
    required this.harmonicMinorCoreRetrievals,
    required this.melodicMinorCoreRetrievals,
    required this.coreRetrievalBands,
    required this.fluentHandsTogetherFloor,
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
  /// Attempt slots allowed per session before every candidate is suppressed,
  /// or null for a sitting the scheduler never ends.
  ///
  /// Null in production. A sitting ends when the player stops, which is the
  /// whole shape of the product: open it, play, leave. A constant that stopped
  /// somebody at forty was a guard against a runaway `decide` loop that had
  /// quietly become the length of a practice session, and it read to the
  /// player as having run out of material while a hundred and fifty candidates
  /// were still admissible.
  ///
  /// Kept as a knob because bounded sittings are still worth writing tests
  /// about, and because a simulation wants to say how long one runs.
  final int? maxSessionAttempts;

  const SafetyConfig({this.maxSessionAttempts})
    : assert(
        maxSessionAttempts == null || maxSessionAttempts > 0,
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

  /// How long a rung has to have been the established one before the learner
  /// is asked for the next one up, in days.
  ///
  /// A different question from [minDaysSinceLastRetrieval] and so a different
  /// clock. That one asks whether enough time has passed for retrieval to mean
  /// something; this asks whether the learner has settled at a level of
  /// support. Producing a scale seconds after being shown it proves little, so
  /// this is not zero, but proving durable retention is not what removing a
  /// preview is for either, so it is much shorter.
  ///
  /// A stand-in for the rule actually wanted, which is that other material
  /// should have intervened. Roughly a quarter of an hour, which at a scale a
  /// minute or two is about that.
  final double minDaysSinceSupportEstablished;

  /// How many selection opportunities may pass with an independence probe
  /// ranked and losing before one is chosen anyway.
  ///
  /// Not a rule that the probe should usually win. Exploration legitimately
  /// dominates a capable learner's first sittings, since new material
  /// establishes breadth and tempo probes find speed. What this rules out is
  /// that dominance being indefinite.
  final int maxUnservedGuidanceProbes;

  /// How many attempts in a row may go by under support before a
  /// retrieval-observing one is asked for regardless of predicted success.
  ///
  /// Support raises predicted success, so as memory weakens the ordinary band
  /// comes to prefer continuous cueing, which observes no retrieval, which
  /// leaves nothing to say whether the support is still needed.
  ///
  /// Counted rather than timed, because what it guards against is
  /// informational: a whole sitting producing no retrieval evidence at all.
  final int supportedAttemptsBeforeObservation;

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
    required this.minDaysSinceSupportEstablished,
    required this.supportedAttemptsBeforeObservation,
    required this.maxUnservedGuidanceProbes,
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
///
/// A calibrated constant rather than loaded configuration, so its sections
/// hold their invariants by assertion; see
/// `docs/domain-model/validation-boundaries.md`.
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
const SchedulerConfig v1SchedulerConfig = SchedulerConfig(
  modelVersion: 'v1-2',
  eligibility: EligibilityConfig(
    multiOctaveExecutionFloor: -0.5,
    gentleTempoBpm: 60,
    earlyTransferExecutionFloor: 0.0,
    intermediateExecutionFloor: 0.4,
    advancedExecutionFloor: 0.8,
    minorTopologyFloor: 0.0,
    harmonicMinorCoreRetrievals: 6,
    melodicMinorCoreRetrievals: 8,
    coreRetrievalBands: 2,
    fluentHandsTogetherFloor: 1.0,
  ),
  safety: SafetyConfig(),
  challenge: ChallengeConfig(pMin: 0.60, pMax: 0.90, pIntroductionMin: 0.15),
  diversity: DiversityConfig(
    recentWindow: 10,
    maxConsecutiveMaterialAttempts: 5,
  ),
  probe: ProbeConfig(
    minDaysSinceLastRetrieval: 5.0,
    minDaysSinceSupportEstablished: 0.01,
    supportedAttemptsBeforeObservation: 3,
    maxUnservedGuidanceProbes: 4,
    underchallengeTempoRatio: 1.2,
    underchallengePitchIntegrity: 0.95,
    underchallengeContinuity: 0.9,
    underchallengeTemporalStability: 0.7,
  ),
);
