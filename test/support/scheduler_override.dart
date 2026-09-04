import 'package:keyrecall_learner/keyrecall_learner.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'package:keyrecall/features/practice/practice_providers.dart';

/// Decides on the calling isolate.
///
/// The app schedules on a worker so the isolate that draws stays free, which a
/// widget test wants no part of: it would spawn an isolate per test to prove
/// something about placement that host-level tests already prove.
final inProcessScheduling = schedulerHostProvider.overrideWith(
  (ref) => InProcessScheduler(const SchedulerPipeline(learner: LearnerModel())),
);
