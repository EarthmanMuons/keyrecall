/// Synthetic learners and the harness that drives KeyRecall over simulated
/// practice.
///
/// A [SyntheticProfile] builds a hidden learner whose true ability the
/// simulation knows; [PracticeSimulation] runs it through repeated attempts
/// against the real [LearnerModel], producing an [AttemptTrace] per attempt.
/// Plugging a [SchedulerAgent] in as the chooser turns a learner-model run
/// into a scheduler run, driven by the real pipeline.
///
/// Randomness comes from [PythonCompatibleRandom], which reproduces the Python
/// prototype's draw sequence exactly, so a run here can be compared attempt by
/// attempt against the reference implementation under `analysis/`.
library;

export 'src/attempt_trace.dart';
export 'src/practice_simulation.dart';
export 'src/python_compatible_random.dart';
export 'src/scheduler_agent.dart';
export 'src/synthetic_learner.dart';
export 'src/trace_json.dart';
