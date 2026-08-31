import 'dart:io';

import 'player_archetypes.dart';
import 'synthetic_player.dart';

/// One trajectory to run: which archetype, and at which seed.
///
/// The archetype travels as its id rather than as a [SyntheticPlayer] so a job
/// can cross an isolate boundary; [playerOf] resolves it on the far side.
class TrajectoryJob {
  final String archetypeId;
  final int seed;

  const TrajectoryJob({required this.archetypeId, required this.seed});
}

/// Every archetype at every seed below [seeds], dealt into one bucket per
/// processor.
///
/// Round robin rather than one bucket per archetype: a true beginner's sitting
/// costs a fraction of an advanced one, so grouping by archetype leaves the
/// slowest one gating the whole run.
List<List<TrajectoryJob>> dealTrajectoryJobs(int seeds) {
  final buckets = List.generate(
    Platform.numberOfProcessors,
    (_) => <TrajectoryJob>[],
  );
  var next = 0;
  for (final player in PlayerArchetypes.all) {
    for (var seed = 0; seed < seeds; seed++) {
      buckets[next++ % buckets.length].add(
        TrajectoryJob(archetypeId: player.id, seed: seed),
      );
    }
  }
  return [
    for (final bucket in buckets)
      if (bucket.isNotEmpty) bucket,
  ];
}

/// The archetype [id] names.
///
/// Throws [ArgumentError] when no archetype matches.
SyntheticPlayer playerOf(String id) => PlayerArchetypes.all.firstWhere(
  (player) => player.id == id,
  orElse: () => throw ArgumentError.value(id, 'id', 'unknown archetype'),
);
