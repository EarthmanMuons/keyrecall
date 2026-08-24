/// A piano keyboard renderer, vendored from whatchord's `features/piano`.
///
/// Copied rather than depended on: the two apps want the same drawing and
/// different behavior around it, and KeyRecall's exercise range is known in
/// advance, so none of whatchord's live-following scroll machinery came along.
/// If the divergence stays small, this is the material a shared package would
/// be cut from.
///
/// [PianoKeyboard] keeps two channels apart, which is what KeyRecall needs
/// from it: `scaleNoteNumbers` describes the material and knows nothing about
/// a performance, while `highlightedNoteNumbers` is what is sounding now.
library;

export 'models/piano_key_decoration.dart';
export 'models/piano_palette.dart';
export 'services/piano_geometry.dart';
export 'widgets/piano_keyboard/piano_keyboard.dart';
