import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('the scheduler has no arpeggio-specific policy', () {
    final source = _schedulerSourceDirectory()
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source.toLowerCase(), isNot(contains('arpeggio')));
  });
}

Directory _schedulerSourceDirectory() {
  var directory = Directory.current;
  while (true) {
    final source = Directory(
      '${directory.path}/packages/keyrecall_scheduler/lib/src',
    );
    if (source.existsSync()) return source;
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('could not locate the scheduler package');
    }
    directory = parent;
  }
}
