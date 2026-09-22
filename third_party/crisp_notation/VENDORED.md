# crisp_notation

Source: <https://github.com/CrispStrobe/crisp_notation>

Revision: `85b82d3508b3d858328aadde489acc23345610d7` (upstream `main`, checked
2026-09-17).

Both packages retain their upstream directory structure, source, tests, analyzer
configuration, and licenses. The screenshot baselines under
`packages/crisp_notation/test/goldens/` are the exception; see below. The
Flutter package also includes its font and metadata assets, including the
Bravura OFL license. Examples, tools, generated documentation, and the CLI
package are omitted.

The snapshot includes core version 0.4.8 from source; this is not a claim that
0.4.8 has been published on pub.dev. The Flutter package remains version 0.4.4.

## Integration

Both packages are members of KeyRecall's Pub workspace. The app uses a relative
path dependency, and workspace resolution also selects the vendored core for the
Flutter package. No sibling checkout is required to build the app.

Upstream files are not reformatted or import-sorted to KeyRecall's conventions.
`mise dart:analyze` analyzes them with their own configuration, and
`mise dart:test` runs both upstream test suites along with the app tests.

### Screenshot baselines

The baselines are maintained here rather than preserved byte for byte from
upstream. They record what KeyRecall's renderer produces under the toolchain
this repository builds with, and they were regenerated after the rendering
patches listed below were in place, so they represent that renderer rather than
upstream's. This is scoped to the images. The source stays traceable to the
revision above, and a source diff against upstream remains worth reading.

Pixel comparisons are coupled to rasterization, not only to engraving. On the
initial import, 129 of them failed here on output that was structurally
identical to the baselines, differing only in antialiasing around glyph edges;
the images that matched were the piano keyboard and fretboard, which draw no
music font glyphs, and the one baseline generated on this machine. A host whose
engine differs from the one a baseline was generated on will see the same
whole-corpus drift. Upstream's `CI=true` test mode skips pixel comparisons while
still exercising rendering and widget behavior:

```sh
cd third_party/crisp_notation/packages/crisp_notation
CI=true flutter test
```

Normal local runs retain strict pixel comparisons. Update a baseline only after
looking at the rendered output and confirming that the visual change is
intentional:

```sh
cd third_party/crisp_notation/packages/crisp_notation
flutter test --update-goldens
```

## Updates and contributions

Keep rendering fixes in separate commits from snapshot updates. Preserve the
upstream APIs where possible and put app-specific defaults in KeyRecall.

The contribution checkout is `~/src/vendor/crisp_notation`, with `origin`
pointing to `elasticdog/crisp_notation` and `upstream` pointing to
`CrispStrobe/crisp_notation`. To contribute a fix, copy the changed package
files and regression tests to the same paths under that checkout's `packages/`,
review the diff, and submit a focused PR. Do not copy KeyRecall's workspace or
dependency configuration.

To update, fetch upstream in the contribution checkout, select an explicit
revision, and replace the retained files from that revision. Reapply any pending
fixes, update this revision record, and run the required Dart checks. Include
deletions when comparing snapshots. Avoid a floating branch dependency. Keep the
baselines under `test/goldens/`: an update brings upstream's images back with
the rest of the snapshot, and they are not the reference here.

Once upstream releases the needed fixes, restore the app's hosted dependency,
remove both vendored workspace entries and this directory, and remove the
vendor-specific test and ignore configuration. Regenerate the lockfile and run
the required checks before committing.

## Local patches

The packages' development dependencies on `lints` and `flutter_lints` use
`^6.0.0` to match KeyRecall's workspace. Runtime patches are listed below.
Flutter added a `build/**` analyzer exclusion to the Flutter package.

- Extend beams to the outer stem edges, preserving the slope at the stem centers
  and the middle-line clearance. Includes cross-staff beams and geometry tests.
- Draw the grand staff's start line from the upper staff's top line to the lower
  staff's bottom line, including every wrapped interactive system. Ledger lines
  outside the five-line staves do not extend this conventional system boundary.
- Add optional above-staff, below-staff, and clef-based outside-staff fingering
  placement through layout settings and notation themes. Preserve the original
  above-note default. Place fingerings after other notation, using the staff
  edge as a baseline with local glyph-metric clearance and outward stacking. A
  focused, reviewed screenshot baseline covers piano fingering, beam edges, and
  the grand staff start line.
