import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// The pacing families whose allocation [exercise] consumes.
///
/// Families are declared keys rather than an enum so a realization the
/// scheduler does not know about can join the same allocation accounting by
/// naming the strands it belongs to.
typedef RealizationFamilyResolver = Set<String> Function(Exercise);

/// Hand configuration, plus motion as its own strand for hands together.
///
/// Two keys rather than one for hands together, so rotating between parallel
/// and contrary still accumulates pressure on the shared strand while each
/// motion is paced separately.
Set<String> handMotionFamilies(Exercise exercise) =>
    switch (exercise.conditions.hands) {
      HandConfiguration.right => {'hands:right'},
      HandConfiguration.left => {'hands:left'},
      HandConfiguration.together => {
        'hands:together',
        'motion:${exercise.conditions.handMotion.name}',
      },
    };

/// Simulation constants for [RealizationFamilyPacing].
///
/// Chosen to make a measurable allocation failure visible in a paired
/// experiment. They are not a proposed production policy.
class RealizationFamilyPacingConfig {
  /// How many recent selections allocation is read over.
  final int window;

  /// The share of the window a family may hold before pressure can build.
  final double shareFloor;

  /// Attempts a family needs in the window before it can be paced at all.
  final int minFamilyAttempts;

  /// The pressure at which a family's candidates are set aside.
  final double setAsideAt;

  /// Whether relief requires an alternative at least as ready as the
  /// candidate it would displace.
  ///
  /// Without it, pressure assumes that poor yield means the learner should be
  /// working on something else. For a learner failing everything, poor yield
  /// instead means the foundational work is not finished, and every other
  /// family is a worse use of the slot.
  final bool requireReadyAlternative;

  const RealizationFamilyPacingConfig({
    this.window = 12,
    this.shareFloor = 0.5,
    this.minFamilyAttempts = 4,
    this.setAsideAt = 0.15,
    this.requireReadyAlternative = false,
  });
}

/// Rolling allocation and yield per realization family.
///
/// Pressure rises when a family holds much of the recent window and little of
/// that work was productive; it falls as the family produces managed
/// execution or as the window fills with other families.
class RealizationFamilyPacing {
  final RealizationFamilyResolver resolver;
  final RealizationFamilyPacingConfig config;

  final List<_Observation> _observations = [];

  RealizationFamilyPacing({
    this.resolver = handMotionFamilies,
    this.config = const RealizationFamilyPacingConfig(),
  });

  /// Records one completed selection and whether it was productive.
  void record(Exercise exercise, {required bool productive}) {
    _observations.add(_Observation(resolver(exercise), productive));
    while (_observations.length > config.window) {
      _observations.removeAt(0);
    }
  }

  /// `share above the floor x unproductive fraction`, in `[0, 1]`.
  double pressure(String family) {
    if (_observations.length < config.window) return 0;
    final held = _observations.where((o) => o.families.contains(family));
    if (held.length < config.minFamilyAttempts) return 0;
    final share = held.length / _observations.length;
    final excess = share - config.shareFloor;
    if (excess <= 0) return 0;
    final yield = held.where((o) => o.productive).length / held.length;
    return excess * (1 - yield);
  }

  /// Every family currently over [RealizationFamilyPacingConfig.setAsideAt].
  Set<String> pressuredFamilies() {
    final families = {for (final o in _observations) ...o.families};
    return families.where((f) => pressure(f) >= config.setAsideAt).toSet();
  }

  bool isPressured(Exercise exercise, Set<String> pressured) =>
      resolver(exercise).any(pressured.contains);
}

/// One slot where pressure removed candidates and others survived.
///
/// Both sides of the substitution the filter made: the best candidate it
/// removed and the best candidate that replaced it, so a diagnostic can ask
/// how much better prepared the relieving family actually was.
class FamilySetAside {
  final int slot;
  final Set<String> pressuredFamilies;
  final CandidateTrace pressured;
  final CandidateTrace relieving;

  const FamilySetAside({
    required this.slot,
    required this.pressuredFamilies,
    required this.pressured,
    required this.relieving,
  });

  /// Whether the relieving family is a credible substitute.
  ///
  /// Predicted success alone, which is the scheduler's existing generic
  /// readiness measure. A richer comparison would read the ranking facts, but
  /// this is enough to ask whether readiness separates a family that should
  /// yield the slot from one whose alternatives are all less prepared.
  bool get isRelievable =>
      relieving.prediction.overallP >= pressured.prediction.overallP;
}

/// The V1 pipeline with realization-family pressure applied at selection.
///
/// A selection-stage filter beside the repetition guard, not an admission
/// rule: a pressured candidate stays eligible and ranked, and wins the slot
/// whenever nothing from another family is admitted. Under lexicographic
/// ranking a penalty term could only break exact ties, so pressure has to act
/// on the available set to act at all.
class FamilyPacedPipeline extends SchedulerPipeline {
  final RealizationFamilyPacing pacing;

  /// Slots where pressure removed candidates and others survived.
  final List<FamilySetAside> setAsides = [];

  /// Slots where every admitted candidate was pressured and none was removed.
  int unrelievedSlots = 0;

  /// Slots where pressure held because no alternative family was ready.
  int unreadySlots = 0;

  FamilyPacedPipeline({
    required super.learner,
    super.config,
    RealizationFamilyPacing? pacing,
  }) : pacing = pacing ?? RealizationFamilyPacing();

  @override
  List<CandidateTrace> selectable(
    List<CandidateTrace> traces,
    SessionState session,
  ) {
    final guarded = super.selectable(traces, session);
    final pressured = pacing.pressuredFamilies();
    if (pressured.isEmpty) return guarded;
    final relieved = guarded
        .where((trace) => !pacing.isPressured(trace.exercise, pressured))
        .toList();
    if (relieved.isEmpty) {
      unrelievedSlots++;
      return guarded;
    }
    if (relieved.length == guarded.length) return relieved;

    final removed = guarded
        .where((trace) => pacing.isPressured(trace.exercise, pressured))
        .toList();
    final setAside = FamilySetAside(
      slot: session.attemptsThisSession,
      pressuredFamilies: pressured,
      pressured: selectBest(removed)!,
      relieving: selectBest(relieved)!,
    );
    if (pacing.config.requireReadyAlternative && !setAside.isRelievable) {
      unreadySlots++;
      return guarded;
    }
    setAsides.add(setAside);
    return relieved;
  }

  @override
  void recordOutcome(
    SessionState session,
    Exercise exercise,
    Outcome? outcome,
  ) {
    super.recordOutcome(session, exercise, outcome);
    pacing.record(
      exercise,
      productive: outcome != null && learner.executionWasManaged(outcome),
    );
  }
}

class _Observation {
  final Set<String> families;
  final bool productive;

  const _Observation(this.families, this.productive);
}
