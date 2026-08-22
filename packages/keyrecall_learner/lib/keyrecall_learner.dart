/// The KeyRecall V1 learner model.
///
/// [LearnerState] holds three layers of belief about one learner: transferable
/// [CompetencyState], exact-material [MaterialMemoryState], and per-context
/// [MaterialExecutionState]. [LearnerModel] turns those beliefs into a
/// four-channel [Prediction] for an upcoming exercise, and folds an [Outcome]
/// back in through [evidenceWeightsFor], updating only the channels the
/// attempt genuinely observed.
library;

export 'src/elapsed_days.dart';
export 'src/model/evidence_weights.dart';
export 'src/model/learner_model.dart';
export 'src/model/loadings.dart';
export 'src/model/memory_update_diagnostics.dart';
export 'src/model/outcome.dart';
export 'src/model/prediction.dart';
export 'src/model/retained_consolidation.dart';
export 'src/params/learner_params.dart';
export 'src/state/competency_state.dart';
export 'src/state/learner_state.dart';
export 'src/state/material_execution_state.dart';
export 'src/state/material_memory_state.dart';
