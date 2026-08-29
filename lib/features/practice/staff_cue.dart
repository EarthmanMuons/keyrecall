import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'fingering.dart';
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
/// Loads the engraving font's metrics before a staff needs them.
///
/// The first staff to render otherwise waits on an asset read, which is the
/// kind of lag that shows up once, on the first exercise of a session, and
/// then never again while you are looking for it.
Future<void> warmStaffRendering() =>
    crisp.MusicFonts.load(crisp.MusicFont.bravura);

class StaffCue extends StatelessWidget {
  const StaffCue({
    required this.exercise,
    this.showsFingering = false,
    super.key,
  });

  /// The exercise whose realization is drawn.
  final Exercise exercise;

  /// Whether the fingering is written over the notes.
  ///
  /// The motor cue is its own channel, so the staff carries it only when that
  /// channel is open rather than whenever the catalog happens to have one.
  final bool showsFingering;

  /// Pixels per staff space. Small enough that two octaves hands together fit
  /// a phone in a few systems, large enough to read.
  static const double staffSpace = 7;

  @override
  Widget build(BuildContext context) {
    final realization = realize(exercise);
    final scheme = Theme.of(context).colorScheme;
    final theme = crisp.CrispNotationTheme.standard.copyWith(
      staffColor: scheme.onSurfaceVariant,
      noteColor: scheme.onSurface,
      highlightColor: scheme.primary,
    );

    // The cue is showing the scale on purpose, so it is written the way a
    // scale book writes it. The staff that grows from what was played is not;
    // see [TranscriptStaff].
    final keySignature = crisp.KeySignature(
      keySignatureFifths(exercise.material),
    );

    if (realization.hands.length > 1) {
      return Column(
        children: [
          // Each row sizes itself to the width, rather than one long system
          // running off the side.
          for (final row in grandStaffRowsFor(
            realization,
            fingering: {
              if (showsFingering)
                for (final hand in realization.hands)
                  hand: displayFingeringFor(exercise, hand),
            },
            keySignature: keySignature,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: crisp.GrandStaffView(grandStaff: row, theme: theme),
            ),
        ],
      );
    }
    return crisp.MultiSystemView(
      score: staffScoreFor(
        realization,
        realization.hands.single,
        fingering: showsFingering
            ? displayFingeringFor(exercise, realization.hands.single)
            : null,
        keySignature: keySignature,
      ),
      theme: theme,
      staffSpace: staffSpace,
    );
  }
}

/// What the learner has played so far, written out.
///
/// The same surface as [StaffCue] carrying different information: this one
/// grows from observations and starts empty, so it discloses nothing about
/// what is coming. One staff rather than two, in the clef the exercise's
/// register suggests, since which hand played a note is not something the
/// input stream says.
class TranscriptStaff extends StatelessWidget {
  const TranscriptStaff({
    required this.transcript,
    required this.exercise,
    super.key,
  });

  /// What has been played.
  final PerformanceTranscript transcript;

  /// The exercise being attempted, which decides the clef.
  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = crisp.CrispNotationTheme.standard.copyWith(
      staffColor: scheme.onSurfaceVariant,
      noteColor: scheme.onSurface,
      highlightColor: scheme.primary,
    );

    return crisp.MultiSystemView(
      score: transcriptScoreFor(
        transcript,
        clef: exercise.conditions.hands == HandConfiguration.left
            ? crisp.Clef.bass
            : crisp.Clef.treble,
      ),
      theme: theme,
      staffSpace: StaffCue.staffSpace,
    );
  }
}
