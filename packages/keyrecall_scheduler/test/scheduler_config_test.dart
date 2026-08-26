import 'package:test/test.dart';

import 'package:keyrecall_scheduler/keyrecall_scheduler.dart';

import 'support/registry_toml.dart';

void main() {
  group('v1PrototypeSchedulerConfig', () {
    const config = v1PrototypeSchedulerConfig;

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
        registry['']!['model_version'],
        reason:
            'the version names the prototype this was derived from, and '
            'changing the Dart values means naming a new version rather than '
            'editing the archived one',
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
