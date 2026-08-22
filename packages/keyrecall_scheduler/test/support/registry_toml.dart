import 'dart:io';

/// Reads one of the authoritative TOML parameter registries under
/// `analysis/`, or returns null when it cannot be found.
///
/// The registries are the source of truth for every numeric constant, and the
/// Dart parameter sets mirror them. A disagreement between the two is a defect
/// to reconcile, which is what the tests using this check for.
///
/// Returns null rather than throwing when the file is missing, so this package
/// still tests cleanly outside the monorepo.
Map<String, Map<String, Object>>? readRegistry(String repoRelativePath) {
  final file = _findUpward(repoRelativePath);
  return file == null ? null : parseFlatToml(file.readAsStringSync());
}

File? _findUpward(String repoRelativePath) {
  var directory = Directory.current.absolute;
  while (true) {
    final candidate = File('${directory.path}/$repoRelativePath');
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) return null;
    directory = parent;
  }
}

/// Parses the flat `[section]` and `key = value` subset of TOML the parameter
/// registries use.
///
/// Deliberately not a general TOML parser. Values are returned as `double`,
/// `int`, or `String`, and top-level keys land under the empty-string section.
Map<String, Map<String, Object>> parseFlatToml(String source) {
  final sections = <String, Map<String, Object>>{'': {}};
  var section = '';

  for (final raw in source.split('\n')) {
    final line = raw.split('#').first.trim();
    if (line.isEmpty) continue;

    if (line.startsWith('[') && line.endsWith(']')) {
      section = line.substring(1, line.length - 1);
      sections.putIfAbsent(section, () => {});
      continue;
    }

    final separator = line.indexOf('=');
    if (separator < 0) continue;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    sections[section]![key] = _parseValue(value);
  }
  return sections;
}

Object _parseValue(String value) {
  if (value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return int.tryParse(value) ?? double.parse(value);
}
