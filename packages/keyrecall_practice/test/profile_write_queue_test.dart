import 'dart:async';

import 'package:test/test.dart';

import 'package:keyrecall_practice/src/profile_write_queue.dart';

void main() {
  test('one profile runs one operation at a time', () async {
    final queue = ProfileWriteQueue();
    final order = <String>[];
    final first = Completer<void>();

    final running = [
      queue.run('alice', () async {
        order.add('alice-1 in');
        await first.future;
        order.add('alice-1 out');
      }),
      queue.run('alice', () async => order.add('alice-2')),
    ];

    await Future<void>.delayed(Duration.zero);
    expect(order, ['alice-1 in'], reason: 'the second must not have started');

    first.complete();
    await Future.wait(running);

    expect(order, ['alice-1 in', 'alice-1 out', 'alice-2']);
  });

  test('separate profiles do not wait for each other', () async {
    final queue = ProfileWriteQueue();
    final blocked = Completer<void>();
    final held = queue.run('alice', () => blocked.future);

    await queue.run('bob', () async {});

    blocked.complete();
    await held;
  });

  test('a failed operation still releases the queue', () async {
    final queue = ProfileWriteQueue();

    await expectLater(
      queue.run('alice', () async => throw StateError('no')),
      throwsStateError,
    );

    expect(await queue.run('alice', () async => 'after'), 'after');
  });
}
