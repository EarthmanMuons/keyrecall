# Timing calibration

- **Status:** Provisional constants for `keyrecall_measurement`
- **Data:** the takes recorded for
  [onset grouping](../onset-grouping/README.md), three of five played badly on
  purpose

## What this is for

Measurement reads two timing scores off the notes alignment has already matched,
and both need to know where ordinary playing ends:

- **temporal stability** reacts to dispersion across the traversal, measured as
  the interquartile range of the inter-onset intervals over their median, so a
  performance that alternates fast and slow scores badly even with no dramatic
  break;
- **continuity** reacts to a local interruption, measured as the longest
  interval over the upper quartile, so a steady performance with one long pause
  scores badly even though the rest was even.

Both statistics are robust on purpose, and the choice is what makes the two
scores independent. A mean-based spread makes one pause read as unsteady
playing, and measuring the longest gap against the median makes merely uneven
playing read as interrupted; either way the two scores collapse into one.

## What the takes show

| Take                      | Hand | Median | Dispersion | Worst interval |
| ------------------------- | ---- | -----: | ---------: | -------------: |
| comfortable c major       | LH   |  295ms |      0.052 |          1.11x |
| comfortable c major       | RH   |  294ms |      0.070 |          1.18x |
| fast c major with stumble | LH   |  196ms |      0.179 |          1.35x |
| fast c major with stumble | RH   |  208ms |      0.080 |          1.08x |
| deliberate rolled c major | LH   |  548ms |      0.612 |          2.60x |
| deliberate rolled c major | RH   |  569ms |      0.568 |          2.47x |
| uneven d major            | LH   |  289ms |      0.601 |          3.28x |
| uneven d major            | RH   |  278ms |      0.723 |          3.79x |
| hands out of phase        | RH   |  646ms |      1.510 |          6.11x |

Dispersion separates cleanly: comfortable playing sits at 0.05 to 0.08, and
everything played deliberately unevenly sits above 0.55. The worst-interval
ratio separates too, at 1.1 to 1.35 against 2.5 and up.

The stumble take is the interesting one. Its per-hand intervals look nearly
comfortable (dispersion 0.08 to 0.18, worst 1.35x), because the stumble showed
up as the two hands drifting apart rather than as either hand pausing. That is a
reminder that these two scores measure one hand's fluency and say nothing about
coordination, which needs the grouping work.

## What a factorial run answered

Twenty-four takes recorded through the app on August 29, 2026: C major, right
hand, up and down, notes shown throughout, three takes of every cell.

| Span     | bpm | median | absolute spread | was discrete | now interpolated |
| -------- | --: | -----: | --------------: | -----------: | ---------------: |
| 1 octave |  60 |  957ms |          51.7ms |        0.054 |            0.049 |
| 1 octave |  80 |  760ms |          41.3ms |        0.054 |            0.048 |
| 1 octave | 100 |  597ms |          28.7ms |        0.048 |            0.045 |
| 1 octave | 120 |  498ms |          35.7ms |        0.072 |            0.062 |
| 2 octave |  60 |  919ms |          40.0ms |        0.044 |            0.040 |
| 2 octave |  80 |  740ms |          37.3ms |        0.050 |            0.051 |
| 2 octave | 100 |  590ms |          35.7ms |        0.061 |            0.060 |
| 2 octave | 120 |  495ms |          27.0ms |        0.055 |            0.055 |

**No absolute floor is warranted.** The hypothesis was that spread would stay
flat in milliseconds while the median shrank, so dispersion would climb with
tempo. It does not. Spread is flat and if anything falls as the tempo rises,
from 52ms to 36ms across the one-octave row, so dispersion stays between 0.04
and 0.07 across the whole matrix. Every cell sits comfortably inside the 0.12
threshold, so a floor would have been fitted to a problem this player does not
have at the tempi the app offers.

**The estimator was the real defect, and the run's own design hid it.** Both
spans were played up and down, so the shortest traversal measured was fourteen
intervals, where the discrete estimator inflates dispersion by about 1.1x. The
app also generates ascending-only exercises, which for one octave is seven
intervals. Recomputing on the ascending half of each one-octave take, which is
the same playing at that length:

| bpm | discrete | interpolated | inflation |
| --: | -------: | -----------: | --------: |
|  60 |    0.053 |        0.037 |     1.42x |
|  80 |    0.045 |        0.035 |     1.27x |
| 100 |    0.077 |        0.060 |     1.28x |
| 120 |    0.066 |        0.053 |     1.24x |

So `quartiles` here and `_quartilesOf` in the Dart now interpolate. The
constants were refitted against the same takes rather than kept: the rolled
take, which is the reference for entirely unsteady, measures 0.678 across its
moments under interpolated quartiles where it measured above 0.80 before, so
`unsteadyDispersion` moved with it. The reference point is the take, not the
number a particular estimator gave it. `steadyDispersion` did not move;
comfortable playing measures 0.07 and the new run stays under 0.08 throughout.

**The device report that prompted this is not reproduced.** Playing evenly at
120 bpm measures 0.055 to 0.072, well inside steady. Whatever produced a "the
pulse kept moving around" on a real attempt was not the tempo, so it was either
a genuine reading or something these cells do not cover: every take here shows
the notes throughout, and a hesitation over what comes next lands in the
interval series exactly like unsteadiness.

## What motivated the factorial run

Recorded here for provenance: the section above is the answer, and this was the
question. All nine rows of the original corpus are one traversal length at one
tempo, roughly 295ms between notes, so two doubts about the constants had no
evidence either way, and they push the same direction.

**Tempo.** Dispersion is a spread over a median, so the variation it allows
shrinks in milliseconds as somebody plays faster. Scalar timing says variability
scales with the interval, which would make the ratio right; a constant motor
component, and the input stack's own fixed jitter, would call for an absolute
floor. **Answered: no floor.** Absolute spread was flat to falling across the
tempi.

**Length.** The quartile estimator took `ordered[n // 4]` and
`ordered[3 * n // 4]`, which is a different percentile at every length.
**Answered: this was the defect.** Quartiles are interpolated now, here and in
the Dart.

## The constants these justify

```text
temporal stability   1.0 at dispersion <= 0.12     a margin above the comfortable
                                                   takes, which measure 0.071 and
                                                   0.090 per hand
                     0.0 at dispersion >= 0.67     just under the rolled take, the
                                                   mildest of the takes that are
                                                   dispersed rather than
                                                   interrupted, at 0.678 across
                                                   its moments

continuity           1.0 at longest <= 1.15x       covers both comfortable takes
                                                   (1.05x, 1.12x) and both hands of
                                                   the stumble (1.06x, 1.14x)
                     0.0 at longest >= 3.00x       between the out-of-phase take's
                                                   2.69x and the uneven D major's
                                                   2.94x
```

Linear between the two ends, since nothing here justifies a curve.

The two floors are chosen differently on purpose. The continuity floor covers
every take that was not deliberately interrupted, including the stumble, whose
per-hand gaps stayed within 1.14x. The stability floor does not cover the
stumble: its left hand reached 0.235 dispersion, and reading that as perfectly
steady would be generous. So 0.12 is a margin above comfortable playing rather
than a line drawn under everything that felt fine to play.

## What this is not

Engineering calibration, not empirical validation. These numbers say what this
input stack sees when this player plays comfortably on this instrument, which is
what the scores need in order to not be arbitrary. They do not establish a
pedagogically meaningful boundary between steady and unsteady playing, and they
are one player, one instrument, one sitting, with three of five takes played
badly on purpose.

Revisit them with takes from people genuinely finding the material hard, and
with a second instrument, before treating any of it as more than provisional.

## Reproducing

```sh
uv run --no-project python analysis/timing-calibration/analyze.py
```
