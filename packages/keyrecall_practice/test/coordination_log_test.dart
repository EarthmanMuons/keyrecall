import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:test/test.dart';

import 'package:keyrecall_practice/keyrecall_practice.dart';

CoordinationSample sampleFor(
  String attemptId, {
  List<({int position, int asynchronyMs})> moments = const [
    (position: 0, asynchronyMs: 12),
    (position: 1, asynchronyMs: -48),
    (position: 2, asynchronyMs: 64),
  ],
}) => CoordinationSample(
  profileId: 'learner',
  attemptId: attemptId,
  observedAt: DateTime.utc(2026, 9, 5),
  materialId: 'C_MAJOR',
  familyId: 'SCALE',
  hands: 'TOGETHER',
  handMotion: 'PARALLEL',
  direction: 'UP_DOWN',
  octaves: 1,
  tempoBpm: 60,
  achievedTempoRatio: 1.05,
  guidanceIndependence: 2,
  coordinationScore: 0.86,
  synchronizedAsynchronyMs: 30,
  reportedAsFault: true,
  moments: moments,
);

void main() {
  test('a sample keeps the series rather than a summary of it', () {
    final sample = sampleFor('a');

    expect(sample.moments, hasLength(3));
    expect(
      sample.moments.map((moment) => moment.asynchronyMs),
      contains(-48),
      reason: 'which hand led is a question the log has to be able to answer',
    );
    expect(sample.medianAbsoluteMs, 48);
    expect(sample.p90AbsoluteMs, 64);
    expect(sample.looseMoments, 2);
  });

  test('a sample survives being written and read back', () {
    final read = CoordinationSample.fromJson(sampleFor('a').toJson());

    expect(read.attemptId, 'a');
    expect(read.synchronizedAsynchronyMs, 30);
    expect(read.reportedAsFault, isTrue);
    expect(read.moments, sampleFor('a').moments);
  });

  test('a sample from a later build is refused rather than guessed at', () {
    final json = sampleFor('a').toJson()
      ..['schema_version'] = coordinationLogSchemaVersion + 1;

    expect(
      () => CoordinationSample.fromJson(json),
      throwsA(isA<JournalFormatException>()),
    );
  });

  test('an attempt observes its hands once', () async {
    final store = InMemoryPracticeStore();

    await store.appendCoordinationSample(sampleFor('a'));
    await store.appendCoordinationSample(sampleFor('a'));
    await store.appendCoordinationSample(sampleFor('b'));

    expect(await store.loadCoordinationSamples('learner'), hasLength(2));
  });

  test('erasing a profile takes the log with it', () async {
    final store = InMemoryPracticeStore();
    await store.appendCoordinationSample(sampleFor('a'));

    await store.erase('learner');

    expect(await store.loadCoordinationSamples('learner'), isEmpty);
  });
}
