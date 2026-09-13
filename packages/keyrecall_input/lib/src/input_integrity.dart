/// Why KeyRecall stopped being able to prove what it was observing.
///
/// A fault is not a bad note. It says the captured event stream can no longer
/// be shown to be one continuous observation of one instrument, which makes
/// anything measured across it a fiction. Every value here is terminal for the
/// observation interval it ends.
enum InputIntegrityFault {
  /// The source stream reported an error.
  sourceFailure,

  /// The source stream ended while it was still supposed to be observing.
  sourceClosed,

  /// A payload no instrument can produce.
  ///
  /// Clamping it into range would turn transport corruption into credible
  /// playing, so it ends the observation instead.
  malformedInput,

  /// Time ran backward within one observation.
  timestampRegression,

  /// Observation was suspended, so continuity across the gap is unknown.
  observationGap,
}
