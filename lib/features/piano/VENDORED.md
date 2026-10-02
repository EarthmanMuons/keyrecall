# Vendored from WhatChord

The files under this directory are copied from the WhatChord piano feature
(`~/src/whatchord/lib/features/piano/`) rather than written here.

## Why it was copied rather than rewritten

Drawing a convincing keyboard is mostly accumulated detail: black-key width and
height ratios, the per-pitch-class horizontal bias that keeps C♯ and F♯ looking
right, how a black key hanging off the end of the span clamps, felt strip,
pressed-key borders and separators, and a palette that survives both themes.
None of that is interesting to rediscover, and all of it is already correct
upstream.

It also already separates the two channels KeyRecall needs kept apart:
`scaleNoteNumbers` describes the material and knows nothing about a performance,
while `highlightedNoteNumbers` is what is sounding now. That distinction is the
presentation-versus-observation seam, and it happens to be the widget's existing
API.

## What came across

- `models/piano_key_decoration.dart`
- `models/piano_palette.dart`
- `models/piano_view_settings.dart`
- `services/piano_geometry.dart`
- `services/piano_scroll_policy.dart`
- `widgets/piano_keyboard/piano_keyboard.dart`
- `widgets/piano_keyboard/piano_keyboard_painter.dart`
- `widgets/piano_keyboard/scrollable_piano_keyboard.dart`
- `widgets/piano_resize_handle.dart`

`piano_scroll_policy.dart` adds `frameTarget`, where the keyboard rests on an
exercise known in advance.

The two widgets are adapted rather than copied, because upstream reads
WhatChord's settings and input providers directly. Here the host passes the size
in and takes changes back through callbacks (`onWidthScaleChanged`,
`onResetSize`, `onHeightChanged`, `onReset`), since KeyRecall stores the size
per profile. The scrollable keyboard also has no idle recentering, takes caller
decorations in place of the middle-C marker, and rests on `frameNoteNumbers`,
keeping `anchorNoteNumbers` in view, recentering whenever either changes or the
visible key count does.

`piano.dart` is a KeyRecall barrel and is not vendored.

## What was deliberately left behind

`piano_view_metrics.dart`, the settings notifier, and its preference keys.
KeyRecall resolves key width and height in `KeyboardScale`, from the keyboard's
default height rather than a fixed key count, and stores each profile's settings
in `practice/keyboard_size.dart`.

## If it needs to change

- **Fixing a drawing bug?** WhatChord probably has it too.
- **Restyling?** Don't, unless the file is being taken over outright.
- **Adding KeyRecall-specific behavior?** Put it in a new file rather than
  threading it through a vendored one. `exercise_presentation.dart` is where
  exercise-shaped knowledge belongs.

If the two copies stay this close, this directory and WhatChord's are the
material a shared package would be cut from.
