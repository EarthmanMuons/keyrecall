import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  final profiles = PlausibilityCohort.profiles;

  test('puts one player in every stratum of every dimension', () {
    expect(profiles, hasLength(PlausibilityCohort.size));
    for (var d = 0; d < PlausibilityCohort.dimensions.length; d++) {
      expect({
        for (final p in profiles) (p.unit[d] * PlausibilityCohort.size).floor(),
      }, hasLength(PlausibilityCohort.size));
    }
  });

  test('stays within the documented ranges', () {
    for (final CohortProfile(:player) in profiles) {
      expect(player.rightHandAbility, inInclusiveRange(-0.3, 0.7));
      expect(player.leftHandAbility, lessThan(player.rightHandAbility));
      expect(player.familyAbility.values.first.abs(), lessThanOrEqualTo(0.3));
      expect(player.noise, inInclusiveRange(0.07, 0.14));
      expect(player.familiarityHalfLifeDays, inInclusiveRange(60, 720));
      expect(player.learningRate, inInclusiveRange(0.005, 0.02));
      expect(player.tempoCompliance, inInclusiveRange(0.55, 0.85));
    }
  });

  test('is frozen', () {
    final table = [
      for (final CohortProfile(:player) in profiles)
        [
          player.id,
          player.rightHandAbility,
          player.leftHandAbility,
          player.handsTogetherAbility,
          player.familyAbility.values.toList(),
          player.familiarity,
          player.noise,
          player.familiarityHalfLifeDays,
          player.retentionHalfLifeDays,
          player.learningRate,
          player.naturalTempoRightBpm,
          player.naturalTempoLeftBpm,
          player.tempoCompliance,
        ],
    ];
    expect(
      sha256.convert(utf8.encode(jsonEncode(table))).toString(),
      '61b3c756c057d9d74982b9adae8487d0071cbfa1f7c3cc396c0af636fb144dad',
    );
  });
}
