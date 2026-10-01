import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:keyrecall_domain/keyrecall_domain.dart';
import 'package:material_ui/material_ui.dart';

import '../practice/exercise_presentation.dart';
import 'fluency_summary.dart';

/// The circle of keys, one ring per entry of each sector's cells.
class KeyWheel extends StatefulWidget {
  const KeyWheel({
    super.key,
    required this.sectors,
    required this.fill,
    required this.emptyColor,
    required this.labelStyle,
    required this.describe,
    required this.onTap,
  });

  final List<KeySector> sectors;
  final Color Function(TechnicalMaterial material) fill;

  /// The color of a cell with no material.
  final Color emptyColor;
  final TextStyle labelStyle;

  /// What a key reads as to assistive technology, which finds the wheel one
  /// key at a time.
  final String Function(KeySector sector) describe;
  final void Function(int sector, int ring) onTap;

  @override
  State<KeyWheel> createState() => _KeyWheelState();
}

class _KeyWheelState extends State<KeyWheel> {
  WheelCell? _preview;
  bool _scrubbing = false;

  static const _holdDelay = Duration(milliseconds: 200);

  KeyWheelGeometry get _geometry =>
      KeyWheelGeometry(rings: widget.sectors.first.cells.length);

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final half = constraints.maxWidth / 2;
        final previewAtTop =
            _preview != null &&
            math.cos(_geometry.centerAngleOf(_preview!.sector)) < 0;
        return RawGestureDetector(
          gestures: {
            TapGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (recognizer) =>
                      recognizer.onTapUp = (details) =>
                          _select(_cellAt(details.localPosition, half)),
                ),
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(() => LongPressGestureRecognizer(duration: _holdDelay), (
                  recognizer,
                ) {
                  recognizer.onLongPressStart = (details) =>
                      _previewAt(details.localPosition, half);
                  recognizer.onLongPressMoveUpdate = (details) =>
                      _previewAt(details.localPosition, half);
                  recognizer.onLongPressEnd = (details) {
                    final cell = _cellAt(details.localPosition, half);
                    _clearPreview();
                    _select(cell);
                  };
                  recognizer.onLongPressCancel = _clearPreview;
                }),
          },
          excludeFromSemantics: true,
          child: FocusTraversalGroup(
            policy: OrderedTraversalPolicy(),
            child: Stack(
              children: [
                CustomPaint(
                  size: Size.square(constraints.maxWidth),
                  painter: _KeyWheelPainter(
                    sectors: widget.sectors,
                    geometry: _geometry,
                    fill: widget.fill,
                    emptyColor: widget.emptyColor,
                    labelStyle: widget.labelStyle,
                    preview: _preview,
                    highlightColor: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (_scrubbing)
                  Positioned(
                    left: 16,
                    right: 16,
                    top: previewAtTop ? 0 : null,
                    bottom: previewAtTop ? null : 0,
                    child: IgnorePointer(
                      child: Material(
                        color: Theme.of(context).colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            _preview == null
                                ? 'Release to cancel'
                                : materialName(
                                    widget
                                        .sectors[_preview!.sector]
                                        .cells[_preview!.ring]!,
                                  ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                for (final (index, sector) in widget.sectors.indexed)
                  if (sector.cells.indexWhere((cell) => cell != null)
                      case final ring when ring >= 0)
                    Positioned.fromRect(
                      rect: _targetOf(index, half),
                      child: FocusTraversalOrder(
                        order: NumericFocusOrder(index.toDouble()),
                        child: _KeyTarget(
                          label: widget.describe(sector),
                          onActivate: () => widget.onTap(index, ring),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    ),
  );

  WheelCell? _cellAt(Offset position, double half) {
    final cell = _geometry.cellAt(
      (position.dx - half) / half,
      (position.dy - half) / half,
    );
    return cell != null && widget.sectors[cell.sector].cells[cell.ring] != null
        ? cell
        : null;
  }

  void _previewAt(Offset position, double half) => setState(() {
    _scrubbing = true;
    _preview = _cellAt(position, half);
  });

  void _clearPreview() => setState(() {
    _scrubbing = false;
    _preview = null;
  });

  void _select(WheelCell? cell) {
    if (cell != null) widget.onTap(cell.sector, cell.ring);
  }

  Rect _targetOf(int sector, double half) {
    final target = _geometry.semanticTargetOf(sector);
    return Rect.fromCenter(
      center: Offset(half + target.x * half, half + target.y * half),
      width: target.side * half,
      height: target.side * half,
    );
  }
}

class _KeyTarget extends StatefulWidget {
  const _KeyTarget({required this.label, required this.onActivate});

  final String label;
  final VoidCallback onActivate;

  @override
  State<_KeyTarget> createState() => _KeyTargetState();
}

class _KeyTargetState extends State<_KeyTarget> {
  bool _showFocus = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
    onShowFocusHighlight: (show) => setState(() => _showFocus = show),
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
      SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
    },
    actions: {
      ActivateIntent: CallbackAction<ActivateIntent>(
        onInvoke: (_) => widget.onActivate(),
      ),
    },
    child: Semantics(
      label: widget.label,
      button: true,
      onTap: widget.onActivate,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: _showFocus
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2,
                  )
                : null,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

/// A small, silent picture of the key wheel, with no names, targets, or
/// gestures, so it reads as the shape of progress rather than a control.
class KeyWheelPreview extends StatelessWidget {
  const KeyWheelPreview({
    super.key,
    required this.sectors,
    required this.fill,
    required this.emptyColor,
    this.size = 72,
  });

  final List<KeySector> sectors;
  final Color Function(TechnicalMaterial material) fill;
  final Color emptyColor;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      // The rings stop short of the edge to leave room for key names, which
      // a preview has none of.
      child: Transform.scale(
        scale: 1 / KeyWheelGeometry.outerRadius,
        child: CustomPaint(
          size: Size.square(size),
          painter: _KeyWheelPainter(
            sectors: sectors,
            geometry: KeyWheelGeometry(rings: sectors.first.cells.length),
            fill: fill,
            emptyColor: emptyColor,
            labelStyle: null,
            preview: null,
            highlightColor: emptyColor,
            gap: 1,
          ),
        ),
      ),
    ),
  );
}

class _KeyWheelPainter extends CustomPainter {
  _KeyWheelPainter({
    required this.sectors,
    required this.geometry,
    required this.fill,
    required this.emptyColor,
    required this.labelStyle,
    required this.preview,
    required this.highlightColor,
    this.gap = 2,
  });

  final List<KeySector> sectors;
  final KeyWheelGeometry geometry;
  final Color Function(TechnicalMaterial material) fill;
  final Color emptyColor;

  /// How the key names are written, or null to leave them off.
  final TextStyle? labelStyle;

  final WheelCell? preview;
  final Color highlightColor;

  /// The gap between neighboring cells, in logical pixels.
  final double gap;

  static const _sweep = 2 * math.pi / 12;

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final center = Offset(half, half);
    final separator = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = gap
      ..color = emptyColor;

    for (final (index, sector) in sectors.indexed) {
      // Canvas angles run clockwise from three o'clock.
      final start = geometry.centerAngleOf(index) - _sweep / 2 - math.pi / 2;
      for (final (ring, material) in sector.cells.indexed) {
        final (outer, inner) = geometry.ringOf(ring);
        final path = _cell(center, outer * half, inner * half, start);
        canvas
          ..drawPath(
            path,
            Paint()..color = material == null ? emptyColor : fill(material),
          )
          ..drawPath(path, separator);
      }
      if (labelStyle case final style?) {
        _label(canvas, center, half, index, sector, style);
      }
    }
    if (preview case final cell?) {
      final (outer, inner) = geometry.ringOf(cell.ring);
      final start =
          geometry.centerAngleOf(cell.sector) - _sweep / 2 - math.pi / 2;
      final path = _cell(center, outer * half, inner * half, start);
      canvas
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 6
            ..color = emptyColor,
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = highlightColor,
        );
    }
  }

  Path _cell(Offset center, double outer, double inner, double start) => Path()
    ..arcTo(Rect.fromCircle(center: center, radius: outer), start, _sweep, true)
    ..arcTo(
      Rect.fromCircle(center: center, radius: inner),
      start + _sweep,
      -_sweep,
      false,
    )
    ..close();

  void _label(
    Canvas canvas,
    Offset center,
    double half,
    int index,
    KeySector sector,
    TextStyle labelStyle,
  ) {
    final major = sector.majorTonic;
    if (major == null) return;
    final minor = sector.minorTonic;
    final painter = TextPainter(
      text: TextSpan(
        text: prettyTonic(major),
        style: labelStyle,
        children: [
          if (minor != null)
            TextSpan(
              text: '\n${prettyTonic(minor)}m',
              style: labelStyle.copyWith(
                fontSize: (labelStyle.fontSize ?? 14) * 0.75,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    final angle = geometry.centerAngleOf(index);
    final radius = (KeyWheelGeometry.outerRadius + 1) / 2 * half;
    final at = center + Offset(math.sin(angle), -math.cos(angle)) * radius;
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(_KeyWheelPainter old) => true;
}
