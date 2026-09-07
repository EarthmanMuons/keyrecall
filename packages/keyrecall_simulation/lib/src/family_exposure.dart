import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'trajectory.dart';

/// What one realization family did after it first appeared.
///
/// The question is dose rather than difficulty: whether the share of a sitting
/// a family holds responds to that family repeatedly failing to yield managed
/// execution. A family that keeps its cadence through a long unproductive run
/// is the scheduler asking the same hard question at the same rate, whatever
/// the answer keeps being.
///
/// Family level rather than material level on purpose. A learner who cannot
/// coordinate two hands is telling you about the family, not about C major.
class FamilyExposure {
  final String family;

  /// The slot the family first appeared in.
  final int firstSlot;

  /// Attempts in the family, and their share of the slots since [firstSlot].
  final int attempts;
  final double share;

  /// The fraction of those attempts production accepted as managed execution.
  final double managedYield;

  /// The longest run of consecutive family attempts that yielded none.
  final int longestUnproductiveStreak;

  /// Unproductive runs at or over the streak length asked about.
  final int streaks;

  /// The family's share of the slots following those runs.
  ///
  /// Read against [share]: lower means the allocation contracted after the
  /// family kept failing, equal means the cadence did not respond at all.
  final double shareAfterStreaks;

  /// Slots from the end of such a run to the family's next managed execution,
  /// at the median, or null where none followed.
  final int? slotsToNextManaged;

  /// Times realization-family pacing actually set this family aside.
  final int setAsides;

  const FamilyExposure({
    required this.family,
    required this.firstSlot,
    required this.attempts,
    required this.share,
    required this.managedYield,
    required this.longestUnproductiveStreak,
    required this.streaks,
    required this.shareAfterStreaks,
    required this.slotsToNextManaged,
    required this.setAsides,
  });
}

/// Every family [trajectory] touched, as an exposure.
///
/// [window] is how many slots after an unproductive run count as its response,
/// and [streakLength] how long a run has to be to ask for one. [setAsides]
/// counts what pacing did, which only a run that observed it can supply.
List<FamilyExposure> familyExposures(
  Trajectory trajectory, {
  int window = 10,
  int streakLength = 5,
  Map<String, int> setAsides = const {},
  RealizationFamilyResolver families = handMotionFamilies,
}) {
  final slots = trajectory.slots;
  final positions = <String, List<int>>{};
  for (final (position, slot) in slots.indexed) {
    for (final family in families(slot.chosen)) {
      (positions[family] ??= []).add(position);
    }
  }

  final exposures = <FamilyExposure>[];
  for (final entry in positions.entries) {
    final held = entry.value;
    final first = held.first;
    final since = slots.length - first;
    var streak = 0;
    var longest = 0;
    final endings = <int>[];
    for (final position in held) {
      if (slots[position].managedExecution) {
        streak = 0;
        continue;
      }
      streak++;
      if (streak > longest) longest = streak;
      // The response window opens at the attempt that completed the run, and
      // a longer run asks the question once rather than at every attempt past
      // the length.
      if (streak == streakLength) endings.add(position);
    }

    var following = 0;
    var followingHeld = 0;
    final recoveries = <int>[];
    for (final ending in endings) {
      final upto = (ending + 1 + window).clamp(0, slots.length);
      following += upto - ending - 1;
      followingHeld += held
          .where((position) => position > ending && position < upto)
          .length;
      final managed = held.firstWhere(
        (position) => position > ending && slots[position].managedExecution,
        orElse: () => -1,
      );
      if (managed >= 0) recoveries.add(managed - ending);
    }
    recoveries.sort();

    exposures.add(
      FamilyExposure(
        family: entry.key,
        firstSlot: first,
        attempts: held.length,
        share: since == 0 ? 0 : held.length / since,
        managedYield: held.isEmpty
            ? 0
            : held.where((p) => slots[p].managedExecution).length / held.length,
        longestUnproductiveStreak: longest,
        streaks: endings.length,
        shareAfterStreaks: following == 0 ? 0 : followingHeld / following,
        slotsToNextManaged: recoveries.isEmpty
            ? null
            : recoveries[recoveries.length ~/ 2],
        setAsides: setAsides[entry.key] ?? 0,
      ),
    );
  }
  exposures.sort((a, b) => a.family.compareTo(b.family));
  return exposures;
}
