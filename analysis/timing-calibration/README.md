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

## The constants these justify

```text
temporal stability   1.0 at dispersion <= 0.12     a margin above the comfortable
                                                   takes, which measured 0.082
                                                   and 0.092
                     0.0 at dispersion >= 0.80     just under the rolled take, the
                                                   mildest of the takes that are
                                                   dispersed rather than interrupted

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
stumble: its left hand reached 0.245 dispersion, and reading that as perfectly
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
