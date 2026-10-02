/// A piano keyboard renderer, vendored from whatchord's `features/piano`.
///
/// Copied rather than depended on: the two apps want the same drawing and
/// different behavior around it. The scrolling keyboard follows live playing
/// as whatchord's does, but rests on an exercise known in advance rather than
/// on middle C. If the divergence stays small, this is the material a shared
/// package would be cut from.
///
/// [PianoKeyboard] keeps two channels apart, which is what KeyRecall needs
/// from it: `scaleNoteNumbers` describes the material and knows nothing about
/// a performance, while `highlightedNoteNumbers` is what is sounding now.
library;

export 'models/piano_key_decoration.dart';
export 'models/piano_palette.dart';
export 'models/piano_view_settings.dart';
export 'services/piano_geometry.dart';
export 'services/piano_scroll_policy.dart';
export 'widgets/piano_keyboard/piano_keyboard.dart';
export 'widgets/piano_keyboard/scrollable_piano_keyboard.dart';
export 'widgets/piano_resize_handle.dart';
