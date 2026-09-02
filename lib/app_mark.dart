import 'package:material_ui/material_ui.dart';

/// The app's icon, at whatever size a screen has room for.
class AppMark extends StatelessWidget {
  const AppMark({this.size = 72, super.key});

  /// How large to draw it, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.23),
    child: Image.asset(
      'assets/icon/icon.png',
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      semanticLabel: 'KeyRecall',
    ),
  );
}
