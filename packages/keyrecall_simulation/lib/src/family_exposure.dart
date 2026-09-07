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

  /// Slots into a returning sitting before the family is attempted again, at
  /// the median, or null where it never was.
  ///
  /// Where time relaxation shows up. A contraction carried across a break is
  /// evidence about a learner who has not touched the family in weeks, and
  /// what ages is how far into the sitting they get before being asked again.
  final int? returnDelay;

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
    required this.returnDelay,
    required this.setAsides,
  });
}

/// Every family [trajectory] touched, as an exposure.
///
/// [window] is how many slots after an unproductive run count as its response,
/// and [streakLength] how long a run has to be to ask for one. [returning] is
/// the gap that makes a sitting a return. [setAsides] counts what pacing did,
/// which only a run that observed it can supply.
List<FamilyExposure> familyExposures(
  Trajectory trajectory, {
  int window = 10,
  int streakLength = 5,
  Duration returning = const Duration(days: 2),
  Map<String, int> setAsides = const {},
  RealizationFamilyResolver families = handMotionFamilies,
}) {
  final slots = trajectory.slots;
  final returns = _returningSittings(trajectory, returning);
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
        returnDelay: _returnDelay(slots, returns, held),
        setAsides: setAsides[entry.key] ?? 0,
      ),
    );
  }
  exposures.sort((a, b) => a.family.compareTo(b.family));
  return exposures;
}

/// The positions each returning sitting starts at, oldest first.
List<int> _returningSittings(Trajectory trajectory, Duration returning) {
  final starts = <int>[];
  for (var sitting = 1; sitting < trajectory.sittings.length; sitting++) {
    final slots = trajectory.slotsOf(sitting).toList();
    final previous = trajectory.slotsOf(sitting - 1).lastOrNull;
    if (slots.isEmpty || previous == null) continue;
    if (slots.first.at.difference(previous.at) < returning) continue;
    starts.add(trajectory.slots.indexOf(slots.first));
  }
  return starts;
}

/// Slots into a returning sitting before a family held one, at the median.
int? _returnDelay(
  List<TrajectorySlot> slots,
  List<int> returns,
  List<int> held,
) {
  final delays = <int>[];
  for (final start in returns) {
    final sitting = slots[start].sitting;
    final next = held.firstWhere(
      (position) => position >= start && slots[position].sitting == sitting,
      orElse: () => -1,
    );
    if (next >= 0) delays.add(next - start);
  }
  if (delays.isEmpty) return null;
  delays.sort();
  return delays[delays.length ~/ 2];
}

/// Whether a failing family ever accumulated enough evidence to be contracted.
enum DoseReachability {
  /// It became contractible, and [DoseLatency] says how long that took.
  reached('reached'),

  /// It produced managed execution before it got there, so contraction was
  /// never warranted.
  recoveredFirst('recovered_first'),

  /// It kept failing and never held enough of the window at once.
  ///
  /// The failure mode a high evidence minimum buys: a family that is a small
  /// minority of every sitting can fail indefinitely without ever holding
  /// `minAttempts` of the last `window` selections, so the mechanism is not
  /// slow to answer, it is structurally unable to.
  neverEnoughEvidence('never_enough_evidence'),

  /// It never failed for long enough to ask the question.
  neverFailed('never_failed');

  const DoseReachability(this.id);

  final String id;
}

/// How long a family's failing run took to become contractible.
class DoseLatency {
  final String family;
  final DoseReachability reachability;

  /// Family attempts from the start of the failing run to the answer.
  final int? attempts;

  /// Slots of any kind over the same stretch.
  final int? slots;

  /// The family's share of the window when the run began.
  ///
  /// A family holding much of a sitting reaches the minimum in a few attempts;
  /// one holding a little may need several sittings, which is the coupling
  /// between the minimum and the window.
  final double shareAtOnset;

  const DoseLatency({
    required this.family,
    required this.reachability,
    required this.attempts,
    required this.slots,
    required this.shareAtOnset,
  });
}

/// What each family's first sustained failing run did, under [config].
///
/// Answers the question a parity column cannot: whether an evidence minimum is
/// merely slow for a low-frequency family or blind to it. Read against a
/// baseline run as readily as a dosed one, since it asks what the policy would
/// have been able to say rather than what it did.
///
/// The window is reconstructed the way the scheduler holds it: the last
/// [DoseConfig.window] selections, which carry across a sitting boundary
/// exactly as `SessionState.resuming` carries them.
List<DoseLatency> doseLatencies(
  Trajectory trajectory, {
  DoseConfig config = const DoseConfig(),
  int failingRun = 3,
  RealizationFamilyResolver families = handMotionFamilies,
}) {
  final slots = trajectory.slots;
  final window = <FamilyObservation>[];
  final onset = <String, int>{};
  final unproductive = <String, int>{};
  final attemptsSinceOnset = <String, int>{};
  final shareAtOnset = <String, double>{};
  final answered = <String, DoseLatency>{};
  final touched = <String>{};

  for (final (position, slot) in slots.indexed) {
    // Asked before the slot is recorded, because that is the window the
    // decision was made against.
    for (final family in {...onset.keys}) {
      if (answered.containsKey(family)) continue;
      if (familyDose(family, window: window, config: config, at: slot.at) <=
          0) {
        continue;
      }
      answered[family] = DoseLatency(
        family: family,
        reachability: DoseReachability.reached,
        attempts: attemptsSinceOnset[family],
        slots: position - onset[family]!,
        shareAtOnset: shareAtOnset[family] ?? 0,
      );
    }

    for (final family in families(slot.chosen)) {
      touched.add(family);
      if (slot.managedExecution) {
        if (onset.containsKey(family) && !answered.containsKey(family)) {
          answered[family] = DoseLatency(
            family: family,
            reachability: DoseReachability.recoveredFirst,
            attempts: attemptsSinceOnset[family],
            slots: position - onset[family]!,
            shareAtOnset: shareAtOnset[family] ?? 0,
          );
        }
        unproductive[family] = 0;
        onset.remove(family);
        attemptsSinceOnset.remove(family);
        continue;
      }
      unproductive[family] = (unproductive[family] ?? 0) + 1;
      attemptsSinceOnset[family] = (attemptsSinceOnset[family] ?? 0) + 1;
      // A run counts as failing once it is long enough to be more than one bad
      // attempt, and the clock starts where the run started rather than where
      // it became interesting.
      if (unproductive[family] == failingRun && !onset.containsKey(family)) {
        onset[family] = position - failingRun + 1;
        attemptsSinceOnset[family] = failingRun;
        shareAtOnset[family] = window.isEmpty
            ? 0
            : window
                      .where(
                        (observation) => observation.families.contains(family),
                      )
                      .length /
                  window.length;
      }
    }

    window.add(
      FamilyObservation(
        families: families(slot.chosen),
        productive: slot.managedExecution,
        at: slot.at,
      ),
    );
    while (window.length > config.window) {
      window.removeAt(0);
    }
  }

  return [
    for (final family in touched.toList()..sort())
      answered[family] ??
          DoseLatency(
            family: family,
            reachability: onset.containsKey(family)
                ? DoseReachability.neverEnoughEvidence
                : DoseReachability.neverFailed,
            attempts: attemptsSinceOnset[family],
            slots: onset.containsKey(family)
                ? slots.length - onset[family]!
                : null,
            shareAtOnset: shareAtOnset[family] ?? 0,
          ),
  ];
}
