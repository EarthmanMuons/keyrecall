import 'dart:async';
import 'dart:io';

import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  late Directory staging;
  late Directory root;

  setUp(() {
    final parent = Directory.systemTemp.createTempSync('demo_profile_test');
    staging = Directory('${parent.path}/staging');
    root = Directory('${parent.path}/root');
  });

  tearDown(() => staging.parent.deleteSync(recursive: true));

  final sessions = demoSessions(
    from: demoHistoryStart,
    until: demoHistoryStart.add(const Duration(days: 6)),
  );

  test('a published profile reopens with the history it was given', () async {
    final prepared = await prepareDemoProfile(
      staging,
      sessions: sessions,
      presentationHint: 'teal',
    );
    expect(await FileProfileRepository(root).list(), isEmpty);

    await publishDemoProfile(prepared, staging: staging, root: root);

    expect(await FileProfileRepository(root).list(), [prepared]);
    final session = await PracticeSession.open(
      store: FilePracticeStore(root),
      profile: prepared,
      materials: allPracticeMaterials,
    );
    expect(session.journal.records, isNotEmpty);
    expect(Directory('${staging.path}/${prepared.id}').existsSync(), isFalse);
  });

  test('a run that fails leaves the live root untouched', () async {
    await expectLater(
      prepareDemoProfile(
        staging,
        sessions: sessions,
        onSession: (completed, _) {
          if (completed == 1) throw StateError('interrupted');
        },
      ),
      throwsStateError,
    );

    expect(root.existsSync(), isFalse);
  });

  test('refuses to publish over a profile already there', () async {
    final prepared = await prepareDemoProfile(staging, sessions: sessions);
    Directory('${root.path}/${prepared.id}').createSync(recursive: true);

    await expectLater(
      publishDemoProfile(prepared, staging: staging, root: root),
      throwsStateError,
    );
  });

  group('staging', () {
    test(
      'is refused to a second run without touching the first one\'s',
      () async {
        final holding = Completer<void>();
        final marker = File('${staging.path}/in-progress');
        final first = withDemoStaging(staging, () async {
          marker.createSync(recursive: true);
          await holding.future;
          return marker.existsSync();
        });

        await expectLater(
          withDemoStaging(staging, () async => fail('the second run started')),
          throwsStateError,
        );
        expect(marker.existsSync(), isTrue);

        holding.complete();
        expect(await first, isTrue);
        expect(staging.existsSync(), isFalse);
      },
    );

    test('is cleared before a run and released after one fails', () async {
      File('${staging.path}/left-behind').createSync(recursive: true);

      await expectLater(
        withDemoStaging(staging, () async {
          expect(staging.existsSync(), isFalse);
          throw StateError('interrupted');
        }),
        throwsStateError,
      );

      expect(await withDemoStaging(staging, () async => 'next'), 'next');
    });
  });
}
