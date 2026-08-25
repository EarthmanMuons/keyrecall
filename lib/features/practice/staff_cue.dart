import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'staff_score.dart';

/// The exercise's notes, written out.
///
/// A cue surface, not a progress display: it draws what the exercise asks for
/// and knows nothing about what has been played. Showing where the learner is,
/// or filling notes in as they arrive, needs a layer that relates a
/// performance to the realization, and that layer does not exist.
///
/// Both hands get a braced grand staff, one hand a single staff in its own
/// clef. Long material wraps into systems rather than being squeezed onto one
/// line.
class StaffCue extends StatelessWidget {
  const StaffCue({required this.exercise, super.key});

  /// The exercise whose realization is drawn.
  final Exercise exercise;

  /// Pixels per staff space. Small enough that two octaves hands together fit
  /// a phone in a few systems, large enough to read.
  static const double _staffSpace = 7;

  @override
  Widget build(BuildContext context) {
    final realization = realize(exercise);
    final scheme = Theme.of(context).colorScheme;
    final theme = crisp.CrispNotationTheme.standard.copyWith(
      staffColor: scheme.onSurfaceVariant,
      noteColor: scheme.onSurface,
      highlightColor: scheme.primary,
    );

    if (realization.hands.length > 1) {
      return crisp.GrandStaffView(
        grandStaff: grandStaffFor(realization),
        theme: theme,
        staffSpace: _staffSpace,
      );
    }
    return crisp.MultiSystemView(
      score: staffScoreFor(realization, realization.hands.single),
      theme: theme,
      staffSpace: _staffSpace,
    );
  }
}
