/// Relates an observed performance to the notes an exercise asked for.
///
/// [align] answers one question: which played note corresponds to which
/// expected one, and what is left over on either side. Everything evaluative a
/// learner sees is a rendering of its result.
///
/// [groupObservations] runs first, pricing what timing suggests about which
/// observations arrived together. Alignment is free to read those gaps either
/// way.
///
/// Pitch and grouping only, with no evidence and no knowledge of scheduling or
/// presentation. See `docs/system/observation.md`.
library;

export 'src/align.dart';
export 'src/alignment_policy.dart';
export 'src/alignment_reading.dart';
export 'src/edit_operation.dart';
export 'src/observation_grouping.dart';
