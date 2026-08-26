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
DateTime requireTime(
  Map<String, Object?> json,
  String key, {
  String? location,
}) {
  final value = json[key];
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw JournalFormatException(
    'expected an ISO-8601 timestamp at "$key", got $value',
    location: location,
  );
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
