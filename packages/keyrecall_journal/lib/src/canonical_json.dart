import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'schema.dart';

/// Encodes [value] so the same content always produces the same bytes.
///
/// Map keys are sorted recursively, so a hash cannot drift because a builder
/// happened to insert fields in a different order. Doubles encode through
/// Dart's shortest round-tripping form, which is specified behavior.
///
/// Throws [JournalFormatException] for a non-finite number, which JSON cannot
/// represent. Reaching that means a NaN or infinity got into state, and the
/// right response is to fail rather than to write a record that cannot be read
/// back.
String canonicalJson(Object? value) => jsonEncode(_canonicalize(value));

/// A content hash over the canonical encoding of [value].
///
/// Used to detect divergence between a recorded state and a replayed one, and
/// to give every checkpoint an identity that depends only on its content.
String contentHash(Object? value) =>
    sha256.convert(utf8.encode(canonicalJson(value))).toString();

Object? _canonicalize(Object? value) {
  if (value == null || value is String || value is bool) return value;
  if (value is num) {
    if (!value.isFinite) {
      throw JournalFormatException(
        'cannot serialize a non-finite number: $value',
      );
    }
    return value;
  }
  if (value is Map) {
    final keys = value.keys.map((key) {
      if (key is String) return key;
      throw JournalFormatException('map keys must be strings, got $key');
    }).toList()..sort();
    return {for (final key in keys) key: _canonicalize(value[key])};
  }
  if (value is Iterable) return value.map(_canonicalize).toList();
  throw JournalFormatException('cannot serialize a ${value.runtimeType}');
}

/// Reads [key] from [json] as a map, or fails with a located error.
Map<String, Object?> requireMap(
  Map<String, Object?> json,
  String key, {
  String? location,
}) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  throw JournalFormatException(
    'expected an object at "$key", got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [key] from [json] as a string, or fails with a located error.
String requireString(
  Map<String, Object?> json,
  String key, {
  String? location,
}) {
  final value = json[key];
  if (value is String) return value;
  throw JournalFormatException(
    'expected a string at "$key", got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [key] from [json] as an int, or fails with a located error.
int requireInt(Map<String, Object?> json, String key, {String? location}) {
  final value = json[key];
  if (value is int) return value;
  throw JournalFormatException(
    'expected an integer at "$key", got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [key] from [json] as a finite double, or fails with a located error.
double requireDouble(
  Map<String, Object?> json,
  String key, {
  String? location,
}) {
  final value = json[key];
  if (value is num && value.isFinite) return value.toDouble();
  throw JournalFormatException(
    'expected a finite number at "$key", got $value',
    location: location,
  );
}

/// Reads [key] from [json] as a bool, or fails with a located error.
bool requireBool(Map<String, Object?> json, String key, {String? location}) {
  final value = json[key];
  if (value is bool) return value;
  throw JournalFormatException(
    'expected a boolean at "$key", got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [key] from [json] as a UTC timestamp, or fails with a located error.
///
/// Timestamps are written as ISO-8601 in UTC, keeping the precision the
/// platform recorded, so interval arithmetic replays exactly.
///
/// Strict on both counts the platform parser is not. An offset is required,
/// because a timestamp without one means whatever the machine reading it
/// decides. And the calendar components must be the ones written: the platform
/// parser accepts `2026-02-31` and hands back March 3, which repairs an
/// impossible date into a plausible one that nothing else will ever notice.
DateTime requireTime(
  Map<String, Object?> json,
  String key, {
  String? location,
}) {
  final value = json[key];
  if (value is String) {
    final parsed = parseTime(value);
    if (parsed != null) return parsed;
  }
  throw JournalFormatException(
    'expected an ISO-8601 timestamp with an offset at "$key", got $value',
    location: location,
  );
}

final RegExp _iso8601 = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})[Tt]'
  r'(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?'
  r'([Zz]|[+-]\d{2}:?\d{2})$',
);

/// Parses [value] as a UTC timestamp, or returns null when it is not one.
///
/// Rejects a missing offset and any calendar component that does not survive
/// the round trip, rather than normalizing either into something readable.
DateTime? parseTime(String value) {
  final match = _iso8601.firstMatch(value);
  if (match == null) return null;

  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final hour = int.parse(match[4]!);
  final minute = int.parse(match[5]!);
  final second = int.parse(match[6]!);

  final calendar = DateTime.utc(year, month, day, hour, minute, second);
  if (calendar.year != year ||
      calendar.month != month ||
      calendar.day != day ||
      calendar.hour != hour ||
      calendar.minute != minute ||
      calendar.second != second) {
    return null;
  }

  return DateTime.tryParse(value)?.toUtc();
}

/// Reads an optional timestamp, distinguishing absent from malformed.
DateTime? readOptionalTime(
  Map<String, Object?> json,
  String key, {
  String? location,
}) => json[key] == null ? null : requireTime(json, key, location: location);

/// Writes [at] as ISO-8601 in UTC.
String encodeTime(DateTime at) => at.toUtc().toIso8601String();

/// Writes an optional timestamp, preserving absence as null.
String? encodeOptionalTime(DateTime? at) => at == null ? null : encodeTime(at);

/// Runs [decode], reporting an expected failure as a located error.
///
/// The storage boundary promises exactly one failure type, and the pieces
/// behind it do not: an unrecognized enum id throws [ArgumentError], a
/// numeric key throws [FormatException], and a cast throws [TypeError]. Those
/// all mean the same thing here, which is that persisted data cannot be read,
/// so they are said the same way.
///
/// A [JournalFormatException] raised inside keeps whatever field location the
/// decoder that raised it knew, and is given this one when it knew none. A
/// nested boundary is the common case: the innermost reader names the field,
/// and the outermost names the line it was on.
T located<T>(T Function() decode, String what, {String? location}) {
  try {
    return decode();
  } on JournalFormatException catch (error) {
    if (error.location != null || location == null) rethrow;
    throw JournalFormatException(error.message, location: location);
  } on ArgumentError catch (error) {
    throw JournalFormatException(
      '$what: ${error.message ?? error}',
      location: location,
    );
  } on FormatException catch (error) {
    throw JournalFormatException('$what: ${error.message}', location: location);
  } on TypeError catch (error) {
    throw JournalFormatException('$what: $error', location: location);
  }
}

/// Reads [value] as a map, or fails with a located error.
///
/// The `as` cast these replace throws [TypeError], which escapes the uniform
/// failure contract: a caller reading an untrusted journal should have to catch
/// exactly one kind of thing.
Map<String, Object?> asMap(Object? value, String what, {String? location}) {
  if (value is Map<String, Object?>) return value;
  throw JournalFormatException(
    'expected an object for $what, got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [value] as a string, or fails with a located error.
String asString(Object? value, String what, {String? location}) {
  if (value is String) return value;
  throw JournalFormatException(
    'expected a string for $what, got ${value.runtimeType}',
    location: location,
  );
}

/// Reads [value] as an optional string, distinguishing absent from malformed.
String? asOptionalString(Object? value, String what, {String? location}) =>
    value == null ? null : asString(value, what, location: location);

/// Reads [value] as an optional int, distinguishing absent from malformed.
int? asOptionalInt(Object? value, String what, {String? location}) {
  if (value == null) return null;
  if (value is int) return value;
  throw JournalFormatException(
    'expected an integer for $what, got $value',
    location: location,
  );
}

/// Reads [value] as a finite double, or fails with a located error.
double asDouble(Object? value, String what, {String? location}) {
  if (value is num && value.isFinite) return value.toDouble();
  throw JournalFormatException(
    'expected a finite number for $what, got $value',
    location: location,
  );
}
