import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

/// The color a profile is recognized by.
///
/// One install, more than one person: a name in a list says who is who when
/// somebody reads it, and a color says it at a glance from across the room.
/// The palette is small on purpose, since colors only tell people apart while
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

  /// The color itself.
  Color get color => Color(_value);

  /// The color [profile] is shown in.
  ///
  /// A profile recorded before colors existed has no hint, and gets one
  /// derived from its id instead of none: it is stable for the life of the
  /// profile, which is all a recognizable color has to be.
  static ProfileColor of(Profile profile) {
    final named = values.where(
      (color) => color.name == profile.presentationHint,
    );
    return named.isNotEmpty
        ? named.first
        : values[profile.id.hashCode.abs() % values.length];
  }

  /// The color to give a new profile, given who is already here.
  ///
  /// The first one nobody is using, so a second person is never handed the
  /// color of the first. Past the palette it wraps, because a repeated color
  /// is a worse outcome than no color only until there are six people on one
  /// piano.
  static ProfileColor unusedAmong(Iterable<Profile> profiles) {
    final taken = profiles.map(ProfileColor.of).toSet();
    return values.firstWhere(
      (color) => !taken.contains(color),
      orElse: () => values[profiles.length % values.length],
    );
  }
}
