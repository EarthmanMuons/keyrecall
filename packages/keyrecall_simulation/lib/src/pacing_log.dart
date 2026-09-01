import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

/// What realization-family pacing did over one trajectory.
///
/// The scheduler decides per slot and keeps nothing; a diagnostic asking how
/// often pressure fired, and what it substituted for what, has to accumulate
/// the decisions as they go past.
class PacingLog {
  final List<FamilySetAside> setAsides = [];

  /// Slots where every admitted candidate was pressured and none was removed.
  int unrelievedSlots = 0;

  /// Slots where pressure held because no alternative family was ready.
  int unreadySlots = 0;

  void record(PacingDecision decision) {
    switch (decision.disposition) {
      case PacingDisposition.inactive:
        break;
      case PacingDisposition.unrelieved:
        unrelievedSlots++;
      case PacingDisposition.unready:
        unreadySlots++;
      case PacingDisposition.relieved:
        setAsides.add(decision.setAside!);
    }
  }
}
