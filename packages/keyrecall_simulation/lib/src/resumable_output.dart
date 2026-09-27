import 'dart:convert';
import 'dart:io';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:keyrecall_learner/keyrecall_learner.dart';

/// An experiment's results file, which knows what experiment it holds.
///
/// Its first line is the configuration the results were produced under, and
/// every result carries the same configuration, so a file read on its own
/// still says what it answers. Resuming is refused when the configuration
/// differs: results from another scope, preference, horizon, or model version
/// are not the rest of this experiment, and mixing them in would be silent.
class ResumableOutput {
  final File file;

  /// What produced these results. Anything that changes what a result means
  /// belongs here; a count of seeds does not, since more seeds extend the
  /// same experiment.
  final Map<String, Object?> configuration;

  ResumableOutput(this.file, this.configuration);

  /// The results an earlier run of this same configuration left, in order.
  ///
  /// Starts the file with its header when there is none yet. Throws
  /// [IncompatibleResume] when the file was written by another configuration,
  /// or by a runner that recorded none.
  List<Map<String, Object?>> resume() {
    final lines = file.existsSync()
        ? [
            for (final line in file.readAsLinesSync())
              if (line.trim().isNotEmpty) line,
          ]
        : const <String>[];
    if (lines.isEmpty) {
      file.writeAsStringSync(
        '${jsonEncode({'configuration': configuration})}\n',
        flush: true,
      );
      return const [];
    }
    final header = jsonDecode(lines.first) as Map<String, Object?>;
    final recorded = header['configuration'];
    if (header.length != 1 ||
        recorded == null ||
        canonicalJson(recorded) != canonicalJson(configuration)) {
      throw IncompatibleResume(
        file: file.path,
        recorded: recorded,
        requested: configuration,
      );
    }
    return [
      for (final line in lines.skip(1))
        jsonDecode(line) as Map<String, Object?>,
    ];
  }

  /// Appends [result], stamped with the configuration.
  void append(Map<String, Object?> result) => file.writeAsStringSync(
    '${jsonEncode({...result, 'configuration': configuration})}\n',
    mode: FileMode.append,
    flush: true,
  );
}

/// A results file written under a configuration other than the one asked
/// for.
class IncompatibleResume implements Exception {
  final String file;
  final Object? recorded;
  final Map<String, Object?> requested;

  const IncompatibleResume({
    required this.file,
    required this.recorded,
    required this.requested,
  });

  @override
  String toString() =>
      'IncompatibleResume: $file was written under ${jsonEncode(recorded)}, '
      'not ${jsonEncode(requested)}; use another --out or remove it';
}

/// What every experiment's configuration names about the models it ran.
Map<String, Object?> modelConfiguration({
  required String schedulerModelVersion,
  LearnerModel learner = const LearnerModel(),
}) => {
  'learner_model_version': learner.params.modelVersion,
  'scheduler_model_version': schedulerModelVersion,
};
