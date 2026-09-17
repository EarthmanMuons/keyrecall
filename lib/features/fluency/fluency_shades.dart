import 'package:keyrecall_practice/keyrecall_practice.dart';
import 'package:material_ui/material_ui.dart';

import 'fluency_summary.dart';

/// The one ramp the report shades on, from nothing shown to the most shown, so
/// a level reads as the same color on the key map and in its charts.
class FluencyShades {
  final ColorScheme scheme;

  const FluencyShades(this.scheme);

  Color _step(int step) => switch (step) {
    0 => scheme.surfaceContainerHighest,
    _ => Color.lerp(scheme.surfaceContainerHighest, scheme.primary, step / 3)!,
  };

  Color ofLevel(DemonstrationLevel? level) =>
      _step(level == null ? 0 : level.index + 1);

  Color ofBand(TempoBand band) => _step(band.index);
}
