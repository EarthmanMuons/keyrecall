/// Relates an observed performance to the notes an exercise asked for.
///
/// [align] answers one question: which played note corresponds to which
/// expected one, and what is left over on either side. It is the only place a
/// correctness judgment is allowed to be made, and everything evaluative that
/// a learner eventually sees is a rendering of its result.
///
/// [groupObservations] runs before it, pricing what timing suggests about
/// which observations arrived together. It proposes and alignment disposes:
/// both readings of every gap stay affordable.
///
/// Deliberately narrow for now: [align] takes one hand, pitch only, no
/// evidence, and no knowledge of scheduling or presentation. See
/// `docs/domain-model/alignment-contract.md` for what is settled and what is
/// still open.
library;

export 'src/align.dart';
export 'src/alignment_policy.dart';
export 'src/alignment_reading.dart';
export 'src/edit_operation.dart';
export 'src/observation_grouping.dart';
