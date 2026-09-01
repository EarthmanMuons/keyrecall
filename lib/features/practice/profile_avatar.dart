import 'package:keyrecall_journal/keyrecall_journal.dart';
import 'package:material_ui/material_ui.dart';

import 'profile_color.dart';

/// A profile as a coloured disc with its initial in it.
///
/// The same mark wherever a profile is shown, so switching between them is
/// recognizing a colour rather than reading a list.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({required this.profile, this.radius = 20, super.key});

  final Profile profile;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = ProfileColor.of(profile).color;
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: Text(
        profileInitial(profile),
        style: TextStyle(
          fontSize: radius,
          fontWeight: FontWeight.w600,
          // Fixed against the disc rather than taken from the scheme: the disc
          // is the same colour in either theme, so text that followed the
          // theme would go unreadable in one of them.
          color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black87,
        ),
      ),
    );
  }
}
