import 'package:meta/meta.dart';

/// The cues shown to the learner before or during an attempt.
///
/// Guidance sits on a three-rung support ladder, from [unguided] through
/// [notesPreviewedOnly] to [continuouslyCued]. It changes how much independent
/// production an attempt demands, and whether independent retrieval is tested
/// at all; it never changes how hard the physical task is.
///
/// Exactly those three values exist. The constructor is private because a
/// fourth combination, notes previewed *and* cues left visible, would describe
/// the same pedagogical condition as [continuouslyCued] while comparing and
/// hashing differently, and guidance is part of exercise identity, cache
/// keys, recovery matching, and persisted records. Widen this deliberately if
/// guidance ever gains a second dimension.
@immutable
class GuidanceContext {
  /// Whether the notes were shown before the attempt and then hidden.
  final bool notesPreviewed;

  /// Whether pitch cues remain visible throughout the attempt.
  final bool concurrentPitchCues;

  const GuidanceContext._({
    this.notesPreviewed = false,
    this.concurrentPitchCues = false,
  });

  /// No cues at all: the strongest independent retrieval test.
  static const GuidanceContext unguided = GuidanceContext._();

  /// Notes shown before the attempt, then hidden: a real but lower-demand
  /// retrieval test.
  static const GuidanceContext notesPreviewedOnly = GuidanceContext._(
    notesPreviewed: true,
  );

  /// Pitch cues visible throughout: the material is supplied outright, so
  /// retrieval is never tested.
  static const GuidanceContext continuouslyCued = GuidanceContext._(
    concurrentPitchCues: true,
  );

  /// The rung [independence] names, for reading a level back from a trace or
  /// a persisted record.
  ///
  /// Throws [ArgumentError] for anything outside `0` through `2`.
  static GuidanceContext ofIndependence(int independence) =>
      switch (independence) {
        0 => continuouslyCued,
        1 => notesPreviewedOnly,
        2 => unguided,
        _ => throw ArgumentError.value(
          independence,
          'independence',
          'must be 0, 1, or 2',
        ),
      };

  /// The support ladder, most independent first.
  static const List<GuidanceContext> ladder = [
    unguided,
    notesPreviewedOnly,
    continuouslyCued,
  ];

  /// How much independent, unassisted production this guidance level demands,
  /// in `[0, 1]`.
  ///
  /// A heuristic V1 mapping, not a research-established coefficient.
  double get retrievalDemand {
    if (concurrentPitchCues) return 0.05;
    if (notesPreviewed) return 0.6;
    return 1.0;
  }

  /// Whether the material is supplied at any point, before the attempt or
  /// throughout it.
  ///
  /// True at both supported rungs and false only when unguided. What the
  /// presentation layer keys on to decide whether there is anything to show at
  /// all, as distinct from [isRetrievalObserved], which asks whether what was
  /// shown left a retrieval test intact.
  bool get isMaterialSupplied => notesPreviewed || concurrentPitchCues;

  /// Whether this attempt can serve as an independent-retrieval observation
  /// at all.
  ///
  /// Concurrent pitch cues supply the material continuously, so independent
  /// retrieval is never actually tested, however low [retrievalDemand] says
  /// the bar was.
  bool get isRetrievalObserved => !concurrentPitchCues;

  /// How independent this guidance level is, from `0` (continuously cued) to
  /// `2` (unguided). Higher means less support.
  int get independence {
    if (concurrentPitchCues) return 0;
    if (notesPreviewed) return 1;
    return 2;
  }

  /// The next rung toward more support, or null when already at maximum.
  ///
  /// Maximum support is unreachable as a recovery target in practice: a cued
  /// attempt never observes retrieval, so it is never an observed failure to
  /// recover from.
  GuidanceContext? get oneStepMoreSupportive {
    if (concurrentPitchCues) return null;
    if (notesPreviewed) return continuouslyCued;
    return notesPreviewedOnly;
  }

  /// The next rung toward independence, or null when already unguided.
  GuidanceContext? get oneStepLessSupportive {
    if (concurrentPitchCues) return notesPreviewedOnly;
    if (notesPreviewed) return unguided;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is GuidanceContext &&
      other.notesPreviewed == notesPreviewed &&
      other.concurrentPitchCues == concurrentPitchCues;

  @override
  int get hashCode => Object.hash(notesPreviewed, concurrentPitchCues);

  @override
  String toString() => switch (independence) {
    0 => 'GuidanceContext(continuously cued)',
    1 => 'GuidanceContext(notes previewed)',
    _ => 'GuidanceContext(unguided)',
  };
}
