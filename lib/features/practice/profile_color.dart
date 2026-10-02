import 'dart:math';

import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

/// The color a profile is recognized by.
///
/// One install, more than one person: a name in a list says who is who when
/// somebody reads it, and a color says it at a glance from across the room.
/// The palette is small on purpose, since colors only tell people apart while
/// they stay apart. It spans the cool hues at an even lightness, leaving the
/// warm ones to the theme's amber and its error red.
///
/// Carried in [Profile.presentationHint], which the journal keeps as an
/// uninterpreted string. Nothing below this reads it, so the palette can change
/// without touching a record.
enum ProfileColor {
  green(0xFF60A563),
  teal(0xFF19AA8E),
  cyan(0xFF00A6B5),
  azure(0xFF369DD1),
  indigo(0xFF6E90DC),
  violet(0xFF9882D4),
  orchid(0xFFB777BB),
  rose(0xFFCB7196);

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
  /// The unused color farthest along the palette from every taken one, so a
  /// second person is never handed the color of the first, nor its neighbor.
  /// Past the palette it wraps, because a repeated color is a worse outcome
  /// than no color only until there are more people than colors on one piano.
  static ProfileColor unusedAmong(Iterable<Profile> profiles) {
    final taken = profiles.map(ProfileColor.of).toSet();
    final unused = values.where((color) => !taken.contains(color));
    if (unused.isEmpty) return values[profiles.length % values.length];

    int distanceFromTaken(ProfileColor color) => taken.fold(
      values.length,
      (nearest, other) => min(nearest, (color.index - other.index).abs()),
    );
    return unused.reduce(
      (best, color) =>
          distanceFromTaken(color) > distanceFromTaken(best) ? color : best,
    );
  }
}
