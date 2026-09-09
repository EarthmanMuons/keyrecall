import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';
import 'package:meta/meta.dart';

import 'python_compatible_random.dart';
import 'synthetic_performance.dart';
import 'synthetic_player.dart';

/// What one sitting did with supported work.
///
/// Descriptive only. Nothing here is a target, a threshold or a score: it
/// counts what happened so that a policy question has something other than one
/// device sitting to answer from. Reading a preference into any of these
/// numbers before device distributions exist is how a provisional constant
/// becomes a permanent one.
@immutable
class AcquisitionCensus {
  /// Which kind of player this was.
  final String playerId;

  /// How many decision opportunities the sitting had.
  final int opportunities;

  /// Ordinary attempts presented.
  final int ordinaryAttempts;

  /// Supported attempts presented.
  final int acquisitionAttempts;

  /// Ordinary attempts at a declared floor, which is what a floor check asks
  /// for and what acquisition then reads.
  final int floorAttempts;

  /// Probes of a parent that acquisition earned, as they were served.
  final int probesServed;

  /// Supported attempts by what they produced.
  final Map<AcquisitionCompletion, int> completions;

  /// Slots between consecutive supported attempts at the same parent.
  final List<int> sameParentGaps;

  /// The longest run of supported attempts with nothing between them.
  final int longestAcquisitionRun;

  /// Slots from the first ordinary attempt at a context to the floor being
  /// asked for there, per context that got one.
  final List<int> slotsToFloorCheck;

  /// Slots from a floor attempt to the first supported attempt on it.
  final List<int> slotsToAcquisition;

  /// Slots from a supported attempt earning a probe to that probe being asked.
  final List<int> slotsToProbe;

  /// What ordinary work an offer displaced, by material and hand.
  ///
  /// The cost of supported work stated as what it was chosen instead of, which
  /// is the only honest way to state it: a slot spent on a scaffold is a slot
  /// not spent on the thing that would otherwise have ranked highest.
  final Map<String, int> divertedFrom;

  const AcquisitionCensus({
    required this.playerId,
    required this.opportunities,
    required this.ordinaryAttempts,
    required this.acquisitionAttempts,
    required this.floorAttempts,
    required this.probesServed,
    required this.completions,
    required this.sameParentGaps,
    required this.longestAcquisitionRun,
    required this.slotsToFloorCheck,
    required this.slotsToAcquisition,
    required this.slotsToProbe,
    required this.divertedFrom,
  });

  /// Whether the sitting ever reached supported work.
  bool get everAcquired => acquisitionAttempts > 0;

  /// Whether the declared floor was ever asked for.
  bool get everCheckedFloor => floorAttempts > 0;

  /// Supported attempts as a share of opportunities.
  double get acquisitionShare =>
      opportunities == 0 ? 0 : acquisitionAttempts / opportunities;

  @override
  String toString() =>
      'AcquisitionCensus($playerId, $acquisitionAttempts/$opportunities '
      'supported, $probesServed probes)';
}

/// Runs one sitting of [slots] and counts what supported work did in it.
///
/// The player answers both paths from the same latent ability: ordinary
/// attempts through an outcome, supported ones through a transcript that is
/// read back by the same observation path device MIDI takes. Nothing here
/// decides anything; it drives the production decision loop and watches.
Future<AcquisitionCensus> censusOfSitting({
  required PracticeSession session,
  required SyntheticPlayer player,
  required int seed,
  int slots = 40,
  DateTime? from,
}) async {
  final playing = player.begin();
  final random = PythonCompatibleRandom(seed);
  final at0 = from ?? session.profile.createdAt.add(const Duration(hours: 1));

  var ordinary = 0;
  var supported = 0;
  var floors = 0;
  var served = 0;
  var run = 0;
  var longestRun = 0;
  final completions = <AcquisitionCompletion, int>{};
  final sameParentGaps = <int>[];
  final toFloorCheck = <int>[];
  final toAcquisition = <int>[];
  final toProbe = <int>[];
  final diverted = <String, int>{};

  // Where each thing first happened, so a latency is a difference rather than
  // a guess. Keyed the way the rules that produce them are keyed.
  final firstOrdinaryAt = <(String, HandConfiguration), int>{};
  final floorAttemptAt = <Exercise, int>{};
  final lastAcquisitionAt = <Exercise, int>{};
  final earnedAt = <Exercise, int>{};
  var slot = 0;

  for (; slot < slots; slot++) {
    final at = at0.add(Duration(minutes: slot + 1));
    final decision = await session.decideOutcome(at: at);

    switch (decision) {
      case PresentedAttempt(:final exercise, :final decision):
        ordinary++;
        run = 0;
        final context = (
          exercise.material.materialId,
          exercise.conditions.hands,
        );
        firstOrdinaryAt.putIfAbsent(context, () => slot);
        if (scaleAcquisitionFloor([exercise]).entries.isNotEmpty) {
          floors++;
          floorAttemptAt.putIfAbsent(exercise, () => slot);
          if (firstOrdinaryAt[context] case final first?) {
            if (first < slot) toFloorCheck.add(slot - first);
          }
        }
        if (decision.decision.challengeBypass ==
            ChallengeBypass.acquisitionProbe) {
          served++;
          if (earnedAt.remove(exercise) case final earned?) {
            toProbe.add(slot - earned);
          }
        }
        await session.acknowledgePresentation(decision.attemptId);
        await session.closeWithOutcome(
          playing.play(exercise, random),
          observedWallTime: at,
        );

      case PresentedAcquisition(:final task, :final displaced):
        supported++;
        run++;
        if (run > longestRun) longestRun = run;
        if (lastAcquisitionAt[task.parent] case final previous?) {
          sameParentGaps.add(slot - previous);
        } else if (floorAttemptAt[task.parent] case final attempted?) {
          toAcquisition.add(slot - attempted);
        }
        lastAcquisitionAt[task.parent] = slot;
        // What it was chosen instead of, as the decision itself reported it.
        if (displaced case final displaced?) {
          final label =
              '${displaced.material.materialId}/'
              '${displaced.conditions.hands.id}';
          diverted.update(label, (count) => count + 1, ifAbsent: () => 1);
        }
        final record = await session.closeAcquisition(
          performAcquisition(state: playing, task: task, rng: random),
          at: at,
        );
        completions.update(
          record.completion,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
        if (record.earnedProbe) earnedAt[task.parent] = slot;

      case PracticeCaughtUp():
      case PracticeBlocked():
      case PracticeSuperseded():
      case PracticeInvalidScope():
        run = 0;
    }
  }

  return AcquisitionCensus(
    playerId: player.id,
    opportunities: slot,
    ordinaryAttempts: ordinary,
    acquisitionAttempts: supported,
    floorAttempts: floors,
    probesServed: served,
    completions: completions,
    sameParentGaps: sameParentGaps,
    longestAcquisitionRun: longestRun,
    slotsToFloorCheck: toFloorCheck,
    slotsToAcquisition: toAcquisition,
    slotsToProbe: toProbe,
    divertedFrom: diverted,
  );
}
