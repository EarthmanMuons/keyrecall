import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

import 'profile_color.dart';

/// A profile as a colored disc.
///
/// The same mark wherever a profile is shown, so switching between them is
/// recognizing a color rather than reading a list. The name is always beside
/// it, so the disc carries the color and nothing the name already says.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.profile, this.radius = 20, super.key});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = ProfileColor.of(profile).color;
    // Fixed against the disc rather than taken from the scheme: the disc is
    // the same color in either theme, so a mark that followed the theme would
    // go unreadable in one of them.
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;

    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Icon(Icons.person, size: radius * 1.2, color: onColor),
    );
  }
}
