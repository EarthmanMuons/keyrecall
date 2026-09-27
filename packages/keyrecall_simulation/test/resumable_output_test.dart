import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:keyrecall_simulation/keyrecall_simulation.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('resumable');
    file = File('${directory.path}/results.jsonl');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  const configuration = {'experiment': 'x', 'scope': 'general', 'sittings': 30};

  test('a fresh file starts with what produced it', () {
    final out = ResumableOutput(file, configuration);

    expect(out.resume(), isEmpty);
    expect(jsonDecode(file.readAsLinesSync().single), {
      'configuration': configuration,
    });
  });

  test('the same configuration resumes, however its keys are ordered', () {
    ResumableOutput(file, configuration)
      ..resume()
      ..append({'identity': 'a/0'});

    final resumed = ResumableOutput(file, {
      'sittings': 30,
      'scope': 'general',
      'experiment': 'x',
    }).resume();

    expect(resumed.single['identity'], 'a/0');
    expect(resumed.single['configuration'], configuration);
  });

  test('another configuration is refused rather than mixed in', () {
    ResumableOutput(file, configuration)
      ..resume()
      ..append({'identity': 'a/0'});

    expect(
      () => ResumableOutput(file, {
        ...configuration,
        'scope': 'keyFluency',
      }).resume(),
      throwsA(isA<IncompatibleResume>()),
    );
  });

  test('a file that recorded no configuration is refused too', () {
    file.writeAsStringSync('${jsonEncode({'identity': 'a/0'})}\n');

    expect(
      () => ResumableOutput(file, configuration).resume(),
      throwsA(isA<IncompatibleResume>()),
    );
  });
}
