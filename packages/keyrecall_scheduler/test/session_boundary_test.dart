import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/fixtures.dart';

/// What a new sitting inherits from the one before it, and what it does not.
void main() {
  final first = exerciseFor(materials.first);
  final second = exerciseFor(materials[1]);

  test('the recency window carries over', () {
    final resumed = SessionState.resuming([
      PriorSelection(first, productive: true),
      PriorSelection(second, productive: false),
    ], config: config);

    expect(resumed.recentMaterialIds, [
      first.material.materialId,
      second.material.materialId,
    ]);
  });

  test('the window keeps only its last entries', () {
    final window = config.diversity.recentWindow;
    final resumed = SessionState.resuming([
      for (var i = 0; i < window + 3; i++)
        PriorSelection(first, productive: true),
      PriorSelection(second, productive: true),
    ], config: config);

    expect(resumed.recentMaterialIds.length, window);
    expect(resumed.recentMaterialIds.last, second.material.materialId);
  });

  test('pacing pressure carries over with its yield', () {
    if (config.pacing == null) return;
    final resumed = SessionState.resuming([
      PriorSelection(first, productive: false),
    ], config: config);

    expect(resumed.recentFamilies.single.productive, isFalse);
  });

  test('nothing the last sitting was in the middle of survives', () {
    final resumed = SessionState.resuming([
      PriorSelection(first, productive: true),
      PriorSelection(second, productive: true),
    ], config: config);

    expect(resumed.attemptsThisSession, 0);
    expect(resumed.isRecovering, isFalse);
    expect(resumed.tempoProbe, isNull);
    expect(resumed.tempoProbeIsFresh, isFalse);
    expect(resumed.supportedAttemptsSinceObservation, 0);
    expect(resumed.unservedGuidanceProbeSelections, 0);
  });
}
