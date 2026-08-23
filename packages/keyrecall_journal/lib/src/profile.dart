import 'dart:math';

import 'package:meta/meta.dart';

import 'canonical_json.dart';

/// One person using this install.
///
/// A shared instrument means a shared install, so an install has no single
/// learner. It has one independent history per profile, and the profile owns
/// that history: its own journal, its own state, its own session.
///
/// [id] is opaque and stable, never derived from [displayName]. Names change
/// and repeat; a history keyed on one would be lost by a rename and merged by
/// a coincidence. A stable id is also the namespace a future sync would merge
/// on, which is a second reason not to let it carry meaning.
@immutable
class Profile {
  /// Stable opaque identifier, conventionally a UUID.
  final String id;

  /// What this person is called, for display only.
  final String displayName;

  /// When the profile was created, in UTC.
  final DateTime createdAt;

  /// Optional presentation hint, such as a color or avatar token.
  ///
  /// Deliberately untyped: it belongs to whatever the UI decides to show, and
  /// nothing here interprets it.
  final String? presentationHint;

  Profile({
    required this.id,
    required this.displayName,
    required DateTime createdAt,
    this.presentationHint,
  }) : createdAt = createdAt.toUtc() {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'must not be empty');
    }
    if (displayName.isEmpty) {
      throw ArgumentError.value(
        displayName,
        'displayName',
        'must not be empty',
      );
    }
  }

  /// A new profile with a freshly generated [id].
  factory Profile.create({
    required String displayName,
    required DateTime createdAt,
    String? presentationHint,
  }) => Profile(
    id: newProfileId(),
    displayName: displayName,
    createdAt: createdAt,
    presentationHint: presentationHint,
  );

  /// This profile under a different display name, keeping its history.
  ///
  /// Renaming is a display change and nothing more, which is the point of an
  /// opaque id.
  Profile renamed(String displayName) => Profile(
    id: id,
    displayName: displayName,
    createdAt: createdAt,
    presentationHint: presentationHint,
  );

  /// Writes the profile.
  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'created_at': encodeTime(createdAt),
    'presentation_hint': presentationHint,
  };

  /// Reads a profile back.
  factory Profile.fromJson(Map<String, Object?> json) => Profile(
    id: requireString(json, 'id', location: 'profile'),
    displayName: requireString(json, 'display_name', location: 'profile'),
    createdAt: requireTime(json, 'created_at', location: 'profile'),
    presentationHint: json['presentation_hint'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.id == id &&
      other.displayName == displayName &&
      other.createdAt == createdAt &&
      other.presentationHint == presentationHint;

  @override
  int get hashCode => Object.hash(id, displayName, createdAt, presentationHint);

  @override
  String toString() => 'Profile($displayName, $id)';
}

final Random _ids = Random.secure();

/// A random RFC 4122 version 4 identifier.
///
/// Generated from a cryptographic source so two installs that later sync
/// cannot collide.
String newProfileId() {
  final bytes = List<int>.generate(16, (_) => _ids.nextInt(256));
  // Version 4 in the high nibble of byte 6, and the RFC 4122 variant in the
  // top bits of byte 8.
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}
