import 'trajectory.dart';

/// What a sitting spends before the learner answers anything.
///
/// A calibration discrepancy is a number about the model. This is the product
/// consequence of one: a person who sat down after a break, and the attempts
/// they spent before the scheduler found work they could do.
class ReturnCost {
  /// Which sitting of the run this describes.
  final int sitting;

  /// Attempts that never started, before the first one that did.
  final int falseStarts;

  /// Rungs of guidance the sitting descended before an attempt started.
  ///
  /// The difference in independence between what was offered first and what
  /// was eventually answered. Zero when the first thing offered started, and
  /// zero for a sitting that never started anything, which [answered] is what
  /// distinguishes.
  final int supportDescended;

  /// Attempts played before the first demonstrated execution, or null when
  /// the sitting produced none.
  ///
  /// Zero when the first attempt was managed, so it counts what came before
  /// rather than numbering the attempt that did it.
  final int? slotsBeforeManaged;

  /// Whether anything in the sitting started at all.
  final bool answered;

  const ReturnCost({
    required this.sitting,
    required this.falseStarts,
    required this.supportDescended,
    required this.answered,
    this.slotsBeforeManaged,
  });

  @override
  String toString() =>
      'sitting $sitting: false starts $falseStarts, support descended '
      '$supportDescended, managed after ${slotsBeforeManaged ?? 'never'}';
}

/// What sitting [index] of [trajectory] spent getting started.
ReturnCost returnCostOf(Trajectory trajectory, int index) {
  final slots = trajectory.slotsOf(index).toList();
  if (slots.isEmpty) {
    return ReturnCost(
      sitting: index,
      falseStarts: 0,
      supportDescended: 0,
      answered: false,
    );
  }
  final started = slots.indexWhere((slot) => slot.outcome.started);
  final managed = slots.indexWhere((slot) => slot.managedExecution);
  return ReturnCost(
    sitting: index,
    falseStarts: started < 0 ? slots.length : started,
    supportDescended: started < 0
        ? 0
        : slots.first.chosen.guidance.independence -
              slots[started].chosen.guidance.independence,
    answered: started >= 0,
    slotsBeforeManaged: managed < 0 ? null : managed,
  );
}
