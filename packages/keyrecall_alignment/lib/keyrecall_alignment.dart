/// Relates an observed performance to the notes an exercise asked for.
///
/// [align] answers one question: which played note corresponds to which
/// expected one, and what is left over on either side. It is the only place a
/// correctness judgment is allowed to be made, and everything evaluative that
/// a learner eventually sees is a rendering of its result.
///
/// Deliberately narrow for now: one hand, pitch only, no timing, no evidence,
/// and no knowledge of scheduling or presentation. See
/// `docs/domain-model/alignment-contract.md` for what is settled, what is
/// still open, and why grouping hands-together observations is not attempted
/// here.
library;

export 'src/align.dart';
export 'src/alignment_policy.dart';
export 'src/alignment_reading.dart';
export 'src/edit_operation.dart';
