import 'package:meta/meta.dart';

/// One material family's repeating pitch and spelling structure.
@immutable
class MaterialTopology {
  final int originSemitoneOffset;
  final int originLetterOffset;
  final List<int> semitoneOffsets;
  final List<int> letterOffsets;

  MaterialTopology({
    this.originSemitoneOffset = 0,
    this.originLetterOffset = 0,
    required Iterable<int> semitoneOffsets,
    required Iterable<int> letterOffsets,
  }) : semitoneOffsets = List.unmodifiable(semitoneOffsets),
       letterOffsets = List.unmodifiable(letterOffsets) {
    if (this.semitoneOffsets.isEmpty ||
        this.semitoneOffsets.length != this.letterOffsets.length) {
      throw ArgumentError(
        'pitch and spelling offsets must be nonempty and the same length',
      );
    }
  }

  int get degreesPerOctave => semitoneOffsets.length;
}
