import 'dart:convert';

import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  test('a synthetic history folds every event it holds, at practice size', () {
    final history = syntheticAllocationHistory(attempts: 1000);
    final folded = AllocationHistory.of(history.attempts, history.acquisition);
    final evidenceBytes =
        history.attempts.records
            .map((record) => jsonEncode(record.allocation.toJson()).length)
            .reduce((a, b) => a + b) /
        history.attempts.length;

    expect(history.acquisition.attempts, hasLength(2));
    expect(folded.observed, 1002);
    expect(folded.staleDecisions, 0);
    expect(folded.gaps, isEmpty);
    expect(evidenceBytes, inInclusiveRange(500, 1500));
    expect(timeSyntheticFold(history, runs: 3), hasLength(3));
  });
}
