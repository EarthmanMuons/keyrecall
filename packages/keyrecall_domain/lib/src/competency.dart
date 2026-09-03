/// A transferable capability the V1 learner model estimates.
///
/// Practice of any material that creates an opportunity for a competency can
/// update it, which is how transfer across the repertoire emerges. The values
/// split into topology, motor, and coordination prediction channels that never
/// update each other.
enum Competency {
  majorScaleTopology('MAJOR_SCALE_TOPOLOGY'),
  naturalMinorTopology('NATURAL_MINOR_TOPOLOGY'),
  harmonicMinorTopology('HARMONIC_MINOR_TOPOLOGY'),
  melodicMinorTopology('MELODIC_MINOR_TOPOLOGY'),
  majorArpeggioTopology('MAJOR_ARPEGGIO_TOPOLOGY'),
  minorArpeggioTopology('MINOR_ARPEGGIO_TOPOLOGY'),
  rhScaleExecution('RH_SCALE_EXECUTION'),
  lhScaleExecution('LH_SCALE_EXECUTION'),
  rhArpeggioExecution('RH_ARPEGGIO_EXECUTION'),
  lhArpeggioExecution('LH_ARPEGGIO_EXECUTION'),
  scalarCrossing('SCALAR_CROSSING'),
  arpeggioTransition('ARPEGGIO_TRANSITION'),
  multiOctaveContinuation('MULTI_OCTAVE_CONTINUATION'),
  directionReversal('DIRECTION_REVERSAL'),
  handsTogetherCoordination('HANDS_TOGETHER_COORDINATION');

  const Competency(this.id);

  /// Stable identifier used in persisted state and traces.
  ///
  /// Serialization uses this rather than [name] or [index] so renaming or
  /// reordering the enum cannot silently reinterpret a stored journal.
  final String id;

  /// The competency with the given [id].
  ///
  /// Throws [ArgumentError] when no competency matches.
  static Competency fromId(String id) => values.firstWhere(
    (competency) => competency.id == id,
    orElse: () => throw ArgumentError.value(id, 'id', 'unknown competency'),
  );

  /// Whether this competency describes pitch/form knowledge.
  bool get isTopology => topologyCompetencies.contains(this);

  /// Whether this competency describes physical execution.
  bool get isMotor => motorCompetencies.contains(this);

  /// Whether this competency describes keeping the hands together.
  bool get isCoordination => coordinationCompetencies.contains(this);

  /// The opposite hand's execution competency, or null when there is none.
  ///
  /// Used for the prediction-only hand-transfer adjustment; it never licenses
  /// writing one hand's evidence into the other's stored state.
  Competency? get pairedHand => switch (this) {
    Competency.rhScaleExecution => Competency.lhScaleExecution,
    Competency.lhScaleExecution => Competency.rhScaleExecution,
    Competency.rhArpeggioExecution => Competency.lhArpeggioExecution,
    Competency.lhArpeggioExecution => Competency.rhArpeggioExecution,
    _ => null,
  };

  /// The established competency that informs this new family, if any.
  Competency? get familyTransferSource => switch (this) {
    Competency.rhArpeggioExecution => Competency.rhScaleExecution,
    Competency.lhArpeggioExecution => Competency.lhScaleExecution,
    _ => null,
  };
}

/// Competencies scored by the topology prediction channel.
const Set<Competency> topologyCompetencies = {
  Competency.majorScaleTopology,
  Competency.naturalMinorTopology,
  Competency.harmonicMinorTopology,
  Competency.melodicMinorTopology,
  Competency.majorArpeggioTopology,
  Competency.minorArpeggioTopology,
};

/// Competencies scored by the motor prediction channel.
///
/// A cued attempt is barely informative about topology but can still be strong
/// motor evidence.
const Set<Competency> motorCompetencies = {
  Competency.rhScaleExecution,
  Competency.lhScaleExecution,
  Competency.rhArpeggioExecution,
  Competency.lhArpeggioExecution,
  Competency.scalarCrossing,
  Competency.arpeggioTransition,
  Competency.multiOctaveContinuation,
  Competency.directionReversal,
};

/// Competencies scored by the coordination channel.
///
/// How together the hands were is measured directly, so it learns from that
/// rather than from how the playing sat in time. Continuity and steadiness say
/// nothing about whether two hands arrived together.
const Set<Competency> coordinationCompetencies = {
  Competency.handsTogetherCoordination,
};
