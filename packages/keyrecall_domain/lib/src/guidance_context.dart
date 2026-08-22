import 'package:meta/meta.dart';

/// The cues shown to the learner before or during an attempt.
///
/// Guidance sits on a three-rung support ladder, from [unguided] through
/// [notesPreviewed] to [concurrentPitchCues]. It changes how much independent
/// production an attempt demands, and whether independent retrieval is tested
/// at all; it never changes how hard the physical task is.
@immutable
class GuidanceContext {
  /// Whether the notes were shown before the attempt and then hidden.
  final bool notesPreviewed;

  /// Whether pitch cues remain visible throughout the attempt.
  final bool concurrentPitchCues;

  const GuidanceContext({
    this.notesPreviewed = false,
    this.concurrentPitchCues = false,
  });

  /// No cues at all: the strongest independent retrieval test.
  static const GuidanceContext unguided = GuidanceContext();

  /// Notes shown before the attempt, then hidden: a real but lower-demand
  /// retrieval test.
  static const GuidanceContext notesPreviewedOnly = GuidanceContext(
    notesPreviewed: true,
  );

  /// Pitch cues visible throughout: the material is supplied outright, so
  /// retrieval is never tested.
  static const GuidanceContext continuouslyCued = GuidanceContext(
    concurrentPitchCues: true,
  );

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
