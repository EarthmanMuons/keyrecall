import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/registry_toml.dart';

void main() {
  group('v1PrototypeSchedulerConfig', () {
    const config = v1PrototypeSchedulerConfig;

    test('agrees with the authoritative TOML registry', () {
      final registry = readRegistry('analysis/scheduler/config.toml');
      if (registry == null) {
        markTestSkipped('analysis/scheduler/config.toml is not available');
        return;
      }

      expect(config.modelVersion, registry['']!['model_version']);
      expect(
        config.eligibility.handTogetherCompetencyThreshold,
        registry['eligibility']!['hand_together_competency_threshold'],
      );
      expect(
        config.safety.maxSessionAttempts,
        registry['safety']!['max_session_attempts'],
      );
      expect(config.challenge.pMin, registry['challenge']!['p_min']);
      expect(config.challenge.pMax, registry['challenge']!['p_max']);
      expect(
        config.challenge.pIntroductionMin,
        registry['challenge']!['p_introduction_min'],
      );
      expect(
        config.diversity.recentWindow,
        registry['diversity']!['recent_window'],
      );
      expect(
        config.diversity.maxConsecutiveMaterialAttempts,
        registry['diversity']!['max_consecutive_material_attempts'],
      );
      expect(
        config.probe.minDaysSinceLastRetrieval,
        registry['guidance_probe']!['min_days_since_last_retrieval'],
      );
    });

    test('keeps the challenge band and introduction floor orderable', () {
      expect(config.challenge.pMin, lessThan(config.challenge.pMax));
      expect(
        config.challenge.pIntroductionMin,
        lessThan(config.challenge.pMin),
        reason: 'new material should be admitted more forgivingly',
      );
      expect(config.challenge.pMax, lessThanOrEqualTo(1.0));
      expect(config.challenge.pIntroductionMin, greaterThan(0.0));
    });

    test('catches a repetition run before it outgrows the tracked history', () {
      expect(
        config.diversity.maxConsecutiveMaterialAttempts,
        lessThan(config.diversity.recentWindow),
      );
    });
  });
}
