import 'package:material_ui/material_ui.dart';

/// The app's name, set the way it is written: KeyRecall, with the recall half
/// carrying the weight.
///
/// Sized from whatever text style surrounds it, so the same mark works in an
/// app bar and on the placement screen without either naming a font size.
class Wordmark extends StatelessWidget {
  const Wordmark({this.style, super.key});

  /// What to set it in. Defaults to the surrounding text style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final wordmark = base.copyWith(
      fontSize: (base.fontSize ?? 20) + 2,
      letterSpacing: -0.2,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Key'),
          TextSpan(
            text: 'Recall',
            style: wordmark.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
      style: wordmark,
      semanticsLabel: 'KeyRecall',
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }
}
