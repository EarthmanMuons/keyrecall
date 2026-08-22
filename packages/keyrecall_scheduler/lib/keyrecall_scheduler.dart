/// The KeyRecall V1 scheduler.
///
/// [generateCandidates] enumerates what the instrument and catalog allow, and
/// [SchedulerPipeline] carries each candidate through eligibility, safety,
/// challenge admission, and priority ranking, recording a [CandidateTrace] for
/// every one. Each stage reads only what its information boundary permits, and
/// [SchedulerPipeline.selectChoice] returns the one exercise to present.
library;

export 'src/candidate_generation.dart';
export 'src/candidate_trace.dart';
export 'src/config/scheduler_config.dart';
export 'src/priority.dart';
export 'src/recovery.dart';
export 'src/scheduler_pipeline.dart';
export 'src/session_state.dart';
