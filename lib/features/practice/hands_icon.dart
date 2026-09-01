import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'exercise_presentation.dart';

/// Which hand or hands play, as a mark rather than as words.
///
/// One glyph, mirrored: a left hand is a right hand seen the other way round,
/// and hands together is both of them. Reading it takes no language, which is
/// what earns it the room the words would want in a bar.
class HandsIcon extends StatelessWidget {
  const HandsIcon(this.hands, {this.size = 18, this.color, super.key});

  final HandConfiguration hands;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final hand = Icon(Icons.back_hand_outlined, size: size, color: color);
    final left = Transform.flip(flipX: true, child: hand);

    return Semantics(
      label: handsName(hands),
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: switch (hands) {
            HandConfiguration.right => [hand],
            HandConfiguration.left => [left],
            HandConfiguration.together => [
              left,
              SizedBox(width: size * 0.1),
              hand,
            ],
          },
        ),
      ),
    );
  }
}
