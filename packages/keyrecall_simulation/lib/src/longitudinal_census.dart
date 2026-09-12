import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'trajectory.dart';

/// Milestones a run reaches once, tracked by when they first appear.
///
/// The long-term progression questions in one vocabulary: whether coordination
/// work, contrary motion, a second octave and unsupported retrieval are
/// reached at all, and what a break does to the sitting they arrive in.
enum Milestone {
  handsTogether('hands_together'),
  contraryMotion('contrary_motion'),
  twoOctaves('two_octaves'),
  unguided('unguided');

  const Milestone(this.id);

  final String id;

  /// Whether [slot] is an instance of this milestone.
  bool reachedBy(TrajectorySlot slot) {
    final conditions = slot.chosen.conditions;
    return switch (this) {
      Milestone.handsTogether => conditions.hands == HandConfiguration.together,
      Milestone.contraryMotion => conditions.handMotion == HandMotion.contrary,
      Milestone.twoOctaves => conditions.octaves >= 2,
      Milestone.unguided => slot.chosen.guidance == GuidanceContext.unguided,
    };
  }
}

/// What one slot of a sitting did, relative to the frontier it was asked
/// against.
///
/// Exclusive, and ordered by what the slot achieved rather than by what it
/// asked for. The distinction that matters most is [preFrontier] against
/// [reacquiring]: work on a material nothing has ever been demonstrated on is
/// acquisition, however many times the learner has seen it, and counting it as
/// reacquisition makes every weak learner look like one who keeps losing
/// ground.
enum SlotWork {
  /// Moved a demonstrated frontier.
  advancing('advancing'),

  /// Met a material this run had not seen, without moving a frontier.
  introducing('introducing'),

  /// Known material with nothing yet demonstrated for this hand.
  preFrontier('pre_frontier'),

  /// Below a frontier this hand has demonstrated.
  reacquiring('reacquiring'),

  /// At or past the frontier, and nothing moved.
  consolidating('consolidating');

  const SlotWork(this.id);

  final String id;
}

/// How [slot] relates to the frontier, given whether its material is [known].
SlotWork workOf(TrajectorySlot slot, {required bool known}) {
  if (slot.frontierAdvanced) return SlotWork.advancing;
  if (!known) return SlotWork.introducing;
  if (slot.frontierBefore.isEmpty) return SlotWork.preFrontier;
  return slot.realization == RealizationRank.surpassed
      ? SlotWork.reacquiring
      : SlotWork.consolidating;
}

/// What one sitting of a run did.
///
/// Counted in slots rather than proportions, so a short sitting and a long one
/// can be added together and the reader decides what to divide by.
class SittingSummary {
  final int index;
  final DateTime at;

  /// Time since the last attempt of the previous sitting, or zero for the
  /// first.
  final Duration away;

  final int slots;

  /// Slots that moved a demonstrated frontier.
  final int advancing;

  /// Slots that met a material this run had not seen before, without moving a
  /// frontier.
  final int introductions;

  /// Slots on known material with no frontier yet demonstrated for that hand.
  final int preFrontier;

  /// Slots below a frontier this hand had already demonstrated.
  final int reacquiring;

  /// Slots at or past the frontier that moved nothing.
  final int consolidating;

  /// Slots asking for less independence than that material had already shown,
  /// with no retrieval failure since.
  ///
  /// What falling back into support looks like from outside: the ladder is
  /// meant to climb, so work reappearing below where it stood is either
  /// forgetting being answered or the scheduler forgetting.
  final int supported;

  /// Slots that moved nothing, where something that would have moved the
  /// learner on was selectable and lost.
  ///
  /// Split from [noProgressionSelectable] because the two say opposite things
  /// about where to look. Both are descriptive: neither says the scheduler
  /// chose wrongly, only whether it had the choice.
  final int progressionPassedOver;

  /// Slots that moved nothing, where nothing that would have moved the learner
  /// on survived to the selectable set.
  final int noProgressionSelectable;

  final int probesOpened;
  final int probesAnswered;

  /// Whether the sitting ended with a probe that had already cleared its
  /// defer, which does not survive the break.
  final bool probeStranded;

  /// Whether a slot in this sitting admitted nothing.
  final bool ranDry;

  /// Distinct materials the run has met by the end of this sitting.
  final int coverage;

  /// Milestones first reached in this sitting.
  final Set<Milestone> firsts;

  const SittingSummary({
    required this.index,
    required this.at,
    required this.away,
    required this.slots,
    required this.advancing,
    required this.introductions,
    required this.preFrontier,
    required this.reacquiring,
    required this.consolidating,
    required this.supported,
    required this.progressionPassedOver,
    required this.noProgressionSelectable,
    required this.probesOpened,
    required this.probesAnswered,
    required this.probeStranded,
    required this.ranDry,
    required this.coverage,
    required this.firsts,
  });

  /// Whether the sitting moved anything forward.
  bool get progressed => advancing > 0 || introductions > 0;

  double get reacquisitionShare => slots == 0 ? 0 : reacquiring / slots;
}

/// What happened on the way back from one break.
///
/// The shape the incidence of a reacquisition finding cannot answer: whether a
/// learner reacquires for a sitting and resumes, or whether every break leaves
/// them there. [sittingsToProgress] is zero when the returning sitting itself
/// advanced something, and null when nothing in the rest of the run did.
class GapRecovery {
  final int sitting;
  final Duration away;
  final double reacquisitionShare;
  final int? sittingsToProgress;

  const GapRecovery({
    required this.sitting,
    required this.away,
    required this.reacquisitionShare,
    required this.sittingsToProgress,
  });
}

/// A run summarized one sitting at a time.
class LongitudinalCensus {
  final String playerId;
  final int seed;
  final List<SittingSummary> sittings;

  const LongitudinalCensus({
    required this.playerId,
    required this.seed,
    required this.sittings,
  });

  /// The recoveries from every break of at least [away].
  ///
  /// Two days by default, which is the shortest gap the learner model can
  /// decay across enough for returning to mean anything.
  Iterable<GapRecovery> recoveries({
    Duration away = const Duration(days: 2),
  }) sync* {
    for (final sitting in sittings) {
      if (sitting.index == 0 || sitting.away < away) continue;
      int? toProgress;
      for (var next = sitting.index; next < sittings.length; next++) {
        if (!sittings[next].progressed) continue;
        toProgress = next - sitting.index;
        break;
      }
      yield GapRecovery(
        sitting: sitting.index,
        away: sitting.away,
        reacquisitionShare: sitting.reacquisitionShare,
        sittingsToProgress: toProgress,
      );
    }
  }

  /// Which sitting each milestone was first reached in.
  Map<Milestone, int> get milestones {
    final first = <Milestone, int>{};
    for (final sitting in sittings) {
      for (final milestone in sitting.firsts) {
        first[milestone] = sitting.index;
      }
    }
    return first;
  }
}

/// Summarizes [trajectory] one sitting at a time.
/// What one slot was, read in the order the run happened.
///
/// Held as its own reading because the answers depend on everything before the
/// slot and nothing after it, so anything wanting a window of a run reads the
/// same classification the census reports rather than recomputing it from a
/// slice that starts in the middle.
class SlotReading {
  final SlotWork work;

  /// Whether it asked for less independence than this material had shown, with
  /// no retrieval failure since.
  final bool supported;

  /// Whether something progressing was selectable, for a slot that moved
  /// nothing. Null when the slot moved something.
  final bool? progressionPassedOver;

  const SlotReading({
    required this.work,
    required this.supported,
    required this.progressionPassedOver,
  });

  bool get movedNothing =>
      work != SlotWork.advancing && work != SlotWork.introducing;
}

/// Every slot of [trajectory], classified in order.
///
/// Positional, so it lines up with `trajectory.slots` rather than with slot
/// indices: a sitting that ran dry consumed an index nothing was recorded at.
List<SlotReading> readRun(Trajectory trajectory) {
  final seen = <String>{};
  // The independence each material has shown, cleared by a retrieval failure
  // the way `guidance_regression` clears it: support after a failure is the
  // ladder working rather than sliding.
  final independence = <String, int>{};
  final readings = <SlotReading>[];

  for (final slot in trajectory.slots) {
    final materialId = slot.chosen.material.materialId;
    final work = workOf(slot, known: seen.contains(materialId));
    final shown = independence[materialId];
    final asked = slot.chosen.guidance.independence;
    readings.add(
      SlotReading(
        work: work,
        supported: shown != null && asked < shown,
        progressionPassedOver:
            work == SlotWork.advancing || work == SlotWork.introducing
            ? null
            : slot.alternatives.any((trace) => _progresses(trace, seen)),
      ),
    );

    if (slot.outcome.retrieval == FactualRetrieval.failed) {
      independence.remove(materialId);
    } else if (slot.outcome.retrieval == FactualRetrieval.succeeded &&
        (shown == null || asked > shown)) {
      independence[materialId] = asked;
    }
    seen.add(materialId);
  }
  return readings;
}

/// Summarizes [trajectory] one sitting at a time.
LongitudinalCensus censusOfRun(Trajectory trajectory) {
  final read = readRun(trajectory);
  final readings = {
    for (final (position, slot) in trajectory.slots.indexed)
      slot.index: read[position],
  };
  final summaries = <SittingSummary>[];
  final seen = <String>{};
  final reached = <Milestone>{};

  for (var index = 0; index < trajectory.sittings.length; index++) {
    final slots = trajectory.slotsOf(index).toList();
    if (slots.isEmpty) continue;
    final previous = index == 0
        ? null
        : trajectory.slotsOf(index - 1).lastOrNull;
    final firsts = <Milestone>{};

    int counting(bool Function(SlotReading reading) matches) =>
        slots.where((slot) => matches(readings[slot.index]!)).length;

    for (final slot in slots) {
      seen.add(slot.chosen.material.materialId);
      for (final milestone in Milestone.values) {
        if (reached.contains(milestone) || !milestone.reachedBy(slot)) continue;
        reached.add(milestone);
        firsts.add(milestone);
      }
    }

    final last = slots.last;
    summaries.add(
      SittingSummary(
        index: index,
        at: trajectory.sittings[index].at,
        away: previous == null
            ? Duration.zero
            : slots.first.at.difference(previous.at),
        slots: slots.length,
        advancing: counting((r) => r.work == SlotWork.advancing),
        introductions: counting((r) => r.work == SlotWork.introducing),
        preFrontier: counting((r) => r.work == SlotWork.preFrontier),
        reacquiring: counting((r) => r.work == SlotWork.reacquiring),
        consolidating: counting((r) => r.work == SlotWork.consolidating),
        supported: counting((r) => r.supported),
        progressionPassedOver: counting((r) => r.progressionPassedOver == true),
        noProgressionSelectable: counting(
          (r) => r.progressionPassedOver == false,
        ),
        probesOpened: slots.where((slot) => slot.probe.opened).length,
        probesAnswered: slots.where((slot) => slot.answeredProbe).length,
        probeStranded:
            last.probe.pendingAfter != null && !last.probe.freshAfter,
        ranDry: trajectory.terminals.any(
          (terminal) => terminal.sitting == index,
        ),
        coverage: seen.length,
        firsts: firsts,
      ),
    );
  }

  return LongitudinalCensus(
    playerId: trajectory.playerId,
    seed: trajectory.seed,
    sittings: summaries,
  );
}

/// Whether [trace] would have moved the learner on.
///
/// Either an unseen material or a realization past the frontier. Read off the
/// selectable set, so a false answer means nothing progressing survived
/// admission and the repetition guard, and cannot say which of those refused
/// it: that question is asked of the traces, which a slot does not retain.
bool _progresses(CandidateTrace trace, Set<String> seen) =>
    !seen.contains(trace.exercise.material.materialId) ||
    trace.rankKey?.realization == RealizationRank.advancing;

/// What arriving at a milestone did to execution quality.
///
/// A new motor demand should cost something; the question is how much and for
/// how long. Compared over equal windows either side of the slot a milestone
/// first appears, across every attempt rather than only the milestone's own,
/// because what a sitting feels like is the whole of it.
///
/// Characterization, not a warning. A dip that recovers is desirable
/// difficulty, and one that does not is a scheduler asking for something the
/// learner cannot yet do; the numbers say which without a threshold deciding
/// in advance.
class MilestoneShock {
  final Milestone milestone;

  /// The slot the milestone first appeared in.
  final int slot;

  /// Median motor score over the window before, and the window after.
  final double before;
  final double after;

  /// Slots until a window of that length reaches [before] again, or null when
  /// the run ends first.
  final int? recoveredAfter;

  const MilestoneShock({
    required this.milestone,
    required this.slot,
    required this.before,
    required this.after,
    required this.recoveredAfter,
  });

  double get delta => after - before;
}

/// The shock at each milestone [trajectory] reached, over [window] slots.
///
/// Milestones without a full window either side are skipped: half a window
/// compared against a full one measures the run's edges. So is a milestone
/// whose windows measured no timing on either side, since a comparison needs
/// two motor scores and neither an absent one nor a zero standing in for it is
/// one.
List<MilestoneShock> milestoneShocks(Trajectory trajectory, {int window = 15}) {
  final slots = trajectory.slots;
  final shocks = <MilestoneShock>[];
  for (final milestone in Milestone.values) {
    final at = slots.indexWhere(milestone.reachedBy);
    if (at < window || at + window >= slots.length) continue;
    final before = _medianMotor(slots, at - window, window);
    final after = _medianMotor(slots, at, window);
    if (before == null || after == null) continue;
    int? recovered;
    for (var start = at + 1; start + window <= slots.length; start++) {
      // A window that measured nothing has not reached the old level; it has
      // not said anything about it.
      if (_medianMotor(slots, start, window) case final median?
          when median >= before) {
        recovered = start - at;
        break;
      }
    }
    shocks.add(
      MilestoneShock(
        milestone: milestone,
        slot: at,
        before: before,
        after: after,
        recoveredAfter: recovered,
      ),
    );
  }
  return shocks;
}

/// The median motor score over a window, or null when none of it was timed.
double? _medianMotor(List<TrajectorySlot> slots, int from, int count) {
  final scores = [
    for (final slot in slots.skip(from).take(count)) ?slot.outcome.motorScore,
  ]..sort();
  if (scores.isEmpty) return null;
  final middle = scores.length ~/ 2;
  return scores.length.isOdd
      ? scores[middle]
      : (scores[middle - 1] + scores[middle]) / 2;
}
