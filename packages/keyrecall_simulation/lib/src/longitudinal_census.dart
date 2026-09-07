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

  /// Slots that met a material this run had not seen before.
  final int introductions;

  /// Slots on material the run already knew, that moved no frontier.
  final int reacquiring;

  /// Slots asking for less independence than that material had already shown,
  /// with no retrieval failure since.
  ///
  /// What falling back into support looks like from outside: the ladder is
  /// meant to climb, so work reappearing below where it stood is either
  /// forgetting being answered or the scheduler forgetting.
  final int supported;

  /// Reacquiring slots where something that would have moved the learner on
  /// was selectable and lost.
  ///
  /// Split from [noProgressionSelectable] because the two say opposite things
  /// about where to look. Both are descriptive: neither says the scheduler
  /// chose wrongly, only whether it had the choice.
  final int progressionPassedOver;

  /// Reacquiring slots where nothing that would have moved the learner on
  /// survived to the selectable set.
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
    required this.reacquiring,
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
LongitudinalCensus censusOfRun(Trajectory trajectory) {
  final summaries = <SittingSummary>[];
  final seen = <String>{};
  final reached = <Milestone>{};
  // The independence each material has shown, cleared by a retrieval failure
  // the way [guidance_regression] clears it: support after a failure is the
  // ladder working rather than sliding.
  final independence = <String, int>{};

  for (var index = 0; index < trajectory.sittings.length; index++) {
    final slots = trajectory.slotsOf(index).toList();
    if (slots.isEmpty) continue;
    final previous = index == 0
        ? null
        : trajectory.slotsOf(index - 1).lastOrNull;

    var advancing = 0;
    var introductions = 0;
    var reacquiring = 0;
    var supported = 0;
    var progressionPassedOver = 0;
    var noProgressionSelectable = 0;
    var probesOpened = 0;
    var probesAnswered = 0;
    final firsts = <Milestone>{};

    for (final slot in slots) {
      final materialId = slot.chosen.material.materialId;
      final known = seen.contains(materialId);
      if (!known) introductions++;
      if (slot.frontierAdvanced) {
        advancing++;
      } else if (known) {
        reacquiring++;
        if (slot.alternatives.any((trace) => _progresses(trace, seen))) {
          progressionPassedOver++;
        } else {
          noProgressionSelectable++;
        }
      }

      final shown = independence[materialId];
      final asked = slot.chosen.guidance.independence;
      if (shown != null && asked < shown) supported++;
      if (slot.outcome.retrieval == FactualRetrieval.failed) {
        independence.remove(materialId);
      } else if (slot.outcome.retrieval == FactualRetrieval.succeeded &&
          (shown == null || asked > shown)) {
        independence[materialId] = asked;
      }

      if (slot.probe.opened) probesOpened++;
      if (slot.answeredProbe) probesAnswered++;
      for (final milestone in Milestone.values) {
        if (reached.contains(milestone) || !milestone.reachedBy(slot)) continue;
        reached.add(milestone);
        firsts.add(milestone);
      }
      seen.add(materialId);
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
        advancing: advancing,
        introductions: introductions,
        reacquiring: reacquiring,
        supported: supported,
        progressionPassedOver: progressionPassedOver,
        noProgressionSelectable: noProgressionSelectable,
        probesOpened: probesOpened,
        probesAnswered: probesAnswered,
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
