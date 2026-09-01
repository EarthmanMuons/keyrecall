import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/registry_toml.dart';

void main() {
  group('v1SchedulerConfig', () {
    const config = v1SchedulerConfig;

    test('records where its values came from, without tracking them', () {
      // The prototype's registry is provenance now, not a source to stay in
      // step with: the Dart configuration is canonical and may move without
      // it. See analysis/README.md.
      final registry = readRegistry('analysis/scheduler/config.toml');
      if (registry == null) {
        markTestSkipped('analysis/scheduler/config.toml is not available');
        return;
      }

      expect(
        config.modelVersion,
        isNot(registry['']!['model_version']),
        reason:
            'the live policy has moved past the prototype, so it names its '
            'own version rather than borrowing the archived one',
      );

      // What did come from the prototype still has to match it. Divergence is
      // a decision, and this is what keeps it from also being an accident.
      expect(
        config.safety.maxSessionAttempts,
        isNull,
        reason:
            'the prototype bounded a sitting at '
            '${registry['safety']!['max_session_attempts']} attempts, which was '
            'a guard against a runaway decision loop rather than a statement '
            'about how long somebody practices; a sitting now ends when the '
            'player stops',
      );
      expect(config.challenge.pMin, registry['challenge']!['p_min']);
      expect(config.challenge.pMax, registry['challenge']!['p_max']);
      expect(
        config.challenge.pIntroductionMin,
        registry['challenge']!['p_introduction_min'],
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

    test('paces realization families behind the readiness gate', () {
      final pacing = config.pacing;
      expect(pacing, isNotNull);
      expect(
        pacing!.requireReadyAlternative,
        isTrue,
        reason:
            'relief toward a generally less prepared strand regressed every '
            'cohort measured; see docs/design/realization-family-pacing.md',
      );
    });

    test('catches a repetition run before it outgrows the tracked history', () {
      expect(
        config.diversity.maxConsecutiveMaterialAttempts,
        lessThan(config.diversity.recentWindow),
      );
    });
  });
}
