import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

/// The colour a profile is recognized by.
///
/// One install, more than one person: a name in a list says who is who when
/// somebody reads it, and a colour says it at a glance from across the room.
/// The palette is small on purpose, since colours only tell people apart while
/// they stay apart.
///
/// Carried in [Profile.presentationHint], which the journal keeps as an
/// uninterpreted string. Nothing below this reads it, so the palette can change
/// without touching a record.
enum ProfileColor {
  amber(0xFFE0A030),
  teal(0xFF2FA090),
  indigo(0xFF6070D0),
  rose(0xFFD06080),
  lime(0xFF7FA83C),
  violet(0xFFA070C8);

  const ProfileColor(this._value);

  final int _value;

  /// The colour itself.
  Color get color => Color(_value);

  /// The colour [profile] is shown in.
  ///
  /// A profile recorded before colours existed has no hint, and gets one
  /// derived from its id instead of none: it is stable for the life of the
  /// profile, which is all a recognizable colour has to be.
  static ProfileColor of(Profile profile) {
    final named = values.where(
      (color) => color.name == profile.presentationHint,
    );
    return named.isNotEmpty
        ? named.first
        : values[profile.id.hashCode.abs() % values.length];
  }

  /// The colour to give a new profile, given who is already here.
  ///
  /// The first one nobody is using, so a second person is never handed the
  /// colour of the first. Past the palette it wraps, because a repeated colour
  /// is a worse outcome than no colour only until there are six people on one
  /// piano.
  static ProfileColor unusedAmong(Iterable<Profile> profiles) {
    final taken = profiles.map(ProfileColor.of).toSet();
    return values.firstWhere(
      (color) => !taken.contains(color),
      orElse: () => values[profiles.length % values.length],
    );
  }
}

/// The letters shown when there is no room for a name.
///
/// One character, because a profile is told apart by its colour first and this
/// only has to disambiguate two people who chose the same one.
String profileInitial(Profile profile) =>
    profile.displayName.characters.first.toUpperCase();
