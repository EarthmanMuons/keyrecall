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
- `services/piano_geometry.dart`
- `widgets/piano_keyboard/piano_keyboard.dart`
- `widgets/piano_keyboard/piano_keyboard_painter.dart`

Unmodified so far, so a diff against upstream is currently empty. Record any
adjustment here when that changes.

`piano.dart` is a KeyRecall barrel and is not vendored.

## What was deliberately left behind

`scrollable_piano_keyboard.dart`, `piano_scroll_policy.dart`,
`piano_view_metrics.dart`, `piano_view_settings.dart`, the settings notifier,
and `piano_resize_handle.dart`. All of that exists so a keyboard can follow live
playing and be resized by hand. A KeyRecall exercise has a range that is known
before the attempt starts, so the diagram is sized once to fit it. Pull the
scrolling layer over if a wide hands-together span turns out not to fit, rather
than in advance.

## If it needs to change

- **Fixing a drawing bug?** WhatChord probably has it too.
- **Restyling?** Don't, unless the file is being taken over outright.
- **Adding KeyRecall-specific behavior?** Put it in a new file rather than
  threading it through a vendored one. `exercise_presentation.dart` is where
  exercise-shaped knowledge belongs.

If the two copies stay this close, this directory and WhatChord's are the
material a shared package would be cut from.
