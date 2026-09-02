import 'package:material_ui/material_ui.dart';

/// The app's badge, at whatever size a screen has room for.
class AppMark extends StatelessWidget {
  const AppMark({this.size = 88, super.key});

  /// How large to draw it, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icon/keyrecall-badge.webp',
    width: size,
    height: size,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'KeyRecall',
  );
}
