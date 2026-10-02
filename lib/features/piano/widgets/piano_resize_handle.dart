import 'package:material_ui/material_ui.dart';

/// Drag-to-resize splitter for the keyboard. Dragging up grows the keyboard's
/// vertical space; double-tapping restores the default size.
///
/// The host pins it to the top edge of the keyboard, on the separator band;
/// the splitter sits at the top and the touch target reaches down over the
/// keys. The host supplies the current [baseHeight] (default/minimum), the live
/// [currentHeight], and the [maxHeight] available so the drag can be clamped to
/// the room on screen.
class PianoResizeHandle extends StatefulWidget {
  const PianoResizeHandle({
    super.key,
    required this.baseHeight,
    required this.currentHeight,
    required this.maxHeight,
    required this.onHeightChanged,
    this.onReset,
  });

  final double baseHeight;
  final double currentHeight;
  final double maxHeight;

  /// Called with each clamped height during a drag.
  final ValueChanged<double> onHeightChanged;

  /// Restores the default size. Null when it is already the default.
  final VoidCallback? onReset;

  /// Hit-target size. Bounded width (not full width) so that, sitting on the
  /// keys, the rest of the top edge stays free for horizontal scrolling. The
  /// height reaches down over the keys.
  static const double hitWidth = 180.0;
  static const double hitHeight = 30.0;

  /// Splitter dimensions. Thin, with [splitterInset] of breathing room above
  /// it (and matching room below, from the band), so it reads as a handle rather
  /// than a scroll bar. [splitterInset] is also how far the host pins the splitter
  /// down from the top of the hit area.
  static const double splitterWidth = 40.0;
  static const double splitterHeight = 4.0;
  static const double splitterInset = 2.0;

  @override
  State<PianoResizeHandle> createState() => _PianoResizeHandleState();
}

class _PianoResizeHandleState extends State<PianoResizeHandle> {
  // Tracks the in-flight height across drag updates so deltas accumulate from
  // the live size rather than the (frame-lagged) provider value.
  double? _dragHeight;

  void _onDragStart(DragStartDetails _) {
    _dragHeight = widget.currentHeight;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final start = _dragHeight ?? widget.currentHeight;
    // Dragging up (negative dy) grows the keyboard.
    final next = (start - details.delta.dy).clamp(
      widget.baseHeight,
      widget.maxHeight,
    );
    _dragHeight = next;
    widget.onHeightChanged(next);
  }

  void _onDragEnd(DragEndDetails _) {
    _dragHeight = null;
  }

  /// How far one assistive-technology adjustment moves the height.
  double get _step => widget.baseHeight * 0.1;

  double _stepped(double delta) =>
      (widget.currentHeight + delta).clamp(widget.baseHeight, widget.maxHeight);

  String _percent(double height) =>
      '${(height / widget.baseHeight * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      slider: true,
      label: 'Resize keyboard',
      hint: 'Drag up or down to resize. Double tap to reset.',
      value: _percent(widget.currentHeight),
      increasedValue: _percent(_stepped(_step)),
      decreasedValue: _percent(_stepped(-_step)),
      onIncrease: widget.currentHeight < widget.maxHeight
          ? () => widget.onHeightChanged(_stepped(_step))
          : null,
      onDecrease: widget.currentHeight > widget.baseHeight
          ? () => widget.onHeightChanged(_stepped(-_step))
          : null,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: _onDragStart,
          onVerticalDragUpdate: _onDragUpdate,
          onVerticalDragEnd: _onDragEnd,
          onDoubleTap: widget.onReset,
          child: SizedBox(
            width: PianoResizeHandle.hitWidth,
            height: PianoResizeHandle.hitHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(
                  top: PianoResizeHandle.splitterInset,
                ),
                child: _splitter(cs),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _splitter(ColorScheme cs) {
    return Container(
      width: PianoResizeHandle.splitterWidth,
      height: PianoResizeHandle.splitterHeight,
      decoration: BoxDecoration(
        // Standard drag-handle treatment: onSurfaceVariant at low opacity.
        color: cs.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(
          PianoResizeHandle.splitterHeight / 2,
        ),
      ),
    );
  }
}
