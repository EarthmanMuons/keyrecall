import 'package:crisp_notation/crisp_notation.dart' as crisp;
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import 'fingering.dart';
import 'staff_score.dart';

/// Loads the engraving font's metrics before a staff needs them.
///
/// The first staff to render otherwise waits on an asset read, which is the
/// kind of lag that shows up once, on the first exercise of a session, and
/// then never again while you are looking for it.
Future<void> warmStaffRendering() =>
    crisp.MusicFonts.load(crisp.MusicFont.bravura);

/// Pixels per staff space when nothing can be measured yet, and the range a
/// measured one is held to.
///
/// The floor keeps a wide exercise legible rather than letting it shrink to
/// fit; the ceiling keeps a short one from being blown up to fill a tablet.
const double _fallbackStaffSpace = 7;
const double _minimumStaffSpace = 5;
const double _maximumStaffSpace = 16;

/// Rows of one staff, drawn as large as the width allows.
///
/// Two bars to a row, and the same size on every row. A renderer packing
/// measures to a width gives whatever number happens to fit at a size chosen in
/// advance, which on a phone is a small staff with space left over.
class FittedStaff extends StatelessWidget {
  const FittedStaff({
    required this.score,
    required this.theme,
    this.showsNoteNames = false,
    super.key,
  });

  final crisp.Score score;
  final crisp.CrispNotationTheme theme;
  final bool showsNoteNames;

  @override
  Widget build(BuildContext context) {
    final rows = rowsOf(score);
    return LayoutBuilder(
      builder: (context, constraints) {
        final space = _spaceFor(
          fittedStaffSpace(rows, width: constraints.maxWidth),
        );
        return Column(
          children: [
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: crisp.StaffView(
                  score: row,
                  theme: theme,
                  staffSpace: space,
                  showNoteNames: showsNoteNames,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Rows of a braced grand staff, drawn as large as the width allows.
class FittedGrandStaff extends StatelessWidget {
  const FittedGrandStaff({required this.rows, required this.theme, super.key});

  final List<crisp.GrandStaff> rows;
  final crisp.CrispNotationTheme theme;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final space = _spaceFor(
        fittedGrandStaffSpace(rows, width: constraints.maxWidth),
      );
      return Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: crisp.GrandStaffView(
                grandStaff: row,
                theme: theme,
                staffSpace: space,
              ),
            ),
        ],
      );
    },
  );
}

double _spaceFor(double? fitted) => (fitted ?? _fallbackStaffSpace).clamp(
  _minimumStaffSpace,
  _maximumStaffSpace,
);

/// The theme a staff is drawn in, taken from the app's colours.
crisp.CrispNotationTheme staffTheme(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return crisp.CrispNotationTheme.standard.copyWith(
    staffColor: scheme.onSurfaceVariant,
    noteColor: scheme.onSurface,
    highlightColor: scheme.primary,
  );
}

/// The exercise's notes, written out.
///
/// A cue surface, not a progress display: it draws what the exercise asks for
/// and knows nothing about what has been played. Showing where the learner is,
/// or filling notes in as they arrive, needs a layer that relates a
/// performance to the realization, and that layer does not exist.
///
/// Both hands get a braced grand staff, one hand a single staff in its own
/// clef.
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

  @override
  Widget build(BuildContext context) {
    final realization = realize(exercise);
    final theme = staffTheme(context);

    // The cue is showing the scale on purpose, so it is written the way a
    // scale book writes it. The staff that grows from what was played is not;
    // see [TranscriptStaff].
    final keySignature = crisp.KeySignature(
      keySignatureFifths(exercise.material),
    );

    if (realization.hands.length > 1) {
      return FittedGrandStaff(
        rows: grandStaffRowsFor(
          realization,
          fingering: {
            if (showsFingering)
              for (final hand in realization.hands)
                hand: displayFingeringFor(exercise, hand),
          },
          keySignature: keySignature,
        ),
        theme: theme,
      );
    }
    return FittedStaff(
      score: staffScoreFor(
        realization,
        realization.hands.single,
        fingering: showsFingering
            ? displayFingeringFor(exercise, realization.hands.single)
            : null,
        keySignature: keySignature,
      ),
      theme: theme,
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
  Widget build(BuildContext context) => FittedStaff(
    score: transcriptScoreFor(
      transcript,
      clef: exercise.conditions.hands == HandConfiguration.left
          ? crisp.Clef.bass
          : crisp.Clef.treble,
    ),
    theme: staffTheme(context),
  );
}
