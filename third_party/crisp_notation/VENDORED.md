# crisp_notation

Source: <https://github.com/CrispStrobe/crisp_notation>

Revision: `85b82d3508b3d858328aadde489acc23345610d7` (upstream `main`, checked
2026-09-17).

Both packages retain their upstream directory structure, source, tests, analyzer
configuration, and licenses. The Flutter package also includes its font and
metadata assets, including the Bravura OFL license. Examples, tools, generated
documentation, and the CLI package are omitted.

The snapshot includes core version 0.4.8 from source; this is not a claim that
0.4.8 has been published on pub.dev. The Flutter package remains version 0.4.4.

## Integration

Both packages are members of KeyRecall's Pub workspace. The app uses a relative
path dependency, and workspace resolution also selects the vendored core for the
Flutter package. No sibling checkout is required to build the app.

Upstream files are not reformatted or import-sorted to KeyRecall's conventions.
`mise dart:analyze` analyzes them with their own configuration, and
`mise dart:test` runs both upstream test suites along with the app tests.

Upstream's screenshot baselines are host-specific. On the initial import, 129
pixel comparisons failed on our machine. The baselines are preserved rather than
regenerated as part of vendoring. Upstream's existing `CI=true` test mode skips
pixel comparisons while still exercising rendering and widget behavior:

```sh
cd third_party/crisp_notation/packages/crisp_notation
CI=true flutter test
```

Normal local runs retain strict pixel comparisons. Before changing engraving,
inspect the relevant baseline and failure images, and establish reviewed
baselines for the rendering environment used to validate that change.

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
deletions when comparing snapshots. Avoid a floating branch dependency.

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
