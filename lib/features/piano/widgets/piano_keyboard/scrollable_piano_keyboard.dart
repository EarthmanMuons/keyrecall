import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'package:material_ui/material_ui.dart';

import '../../../../motion.dart';
import '../../models/piano_key_decoration.dart';
import '../../services/piano_geometry.dart';
import '../../services/piano_scroll_policy.dart';
import 'piano_keyboard.dart';

/// Actions offered by the keyboard's long-press menu.
enum _PianoQuickAction { center, resetSize }

/// Scale recognizer tuned to coexist with the keyboard's horizontal scroll view.
///
/// A single finger is left entirely to the scroll view (its movement is
/// ignored), so one-finger drags scroll as usual. As soon as a second finger
/// lands, the recognizer claims the gesture arena outright: otherwise the
/// scroll view's (greedy) horizontal drag recognizer wins the moment a finger
/// crosses touch
/// slop, stealing the pinch before its scale delta grows enough to assert
/// itself. Two fingers always means zoom; one finger always means scroll.
class _PinchScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && pointerCount < 2) return;
    super.handleEvent(event);
    if (pointerCount >= 2) resolve(GestureDisposition.accepted);
  }
}

class ScrollablePianoKeyboard extends StatefulWidget {
  const ScrollablePianoKeyboard({
    super.key,
    required this.visibleWhiteKeyCount,
    required this.height,
    required this.highlightedNoteNumbers,
    this.frameNoteNumbers = const <int>{},
    this.anchorNoteNumbers = const <int>{},
    this.autoCenter = true,
    this.autoCenterSuppression = const Duration(seconds: 3),
    this.fullWhiteKeyCount = PianoGeometry.fullKeyboardWhiteKeyCount,
    this.lowestNoteNumber = 21, // A0
    this.decorations = const <PianoKeyDecoration>[],
    this.scaleNoteNumbers = const <int>{},
    this.normalHighlightPitchClasses,
    this.tonicPitchClass,
    this.enableZoom = false,
    this.widthScale = 1.0,
    this.onWidthScaleChanged,
    this.onResetSize,
  }) : assert(visibleWhiteKeyCount > 0);

  /// How many white keys should be visible in the viewport width.
  /// (fewer in portrait, often 52 in landscape)
  ///
  /// May be fractional, so zooming changes the key width continuously.
  final double visibleWhiteKeyCount;

  final double height;

  final Set<int> highlightedNoteNumbers;

  /// Notes the viewport rests centered on while nothing is sounding.
  final Set<int> frameNoteNumbers;

  /// Notes kept in view when [frameNoteNumbers] does not fit.
  final Set<int> anchorNoteNumbers;

  /// If true, auto-center the viewport to keep highlighted notes visible.
  final bool autoCenter;

  /// When user scrolls manually, suppress follow for this window.
  final Duration autoCenterSuppression;

  /// Full keyboard span rendered into the scroll content.
  final int fullWhiteKeyCount;

  /// First white MIDI note of the full span (A0 = 21 for a standard 88-key).
  final int lowestNoteNumber;

  final List<PianoKeyDecoration> decorations;

  /// Scale member note numbers. When non-empty, each member key is marked with
  /// a dot so the in-scale notes read at a glance.
  final Set<int> scaleNoteNumbers;

  /// Pitch classes that keep the normal active highlight when highlighted.
  /// Highlighted notes outside this set use the muted active fill. Null means
  /// no pitch-class filter.
  final Set<int>? normalHighlightPitchClasses;

  /// Pitch class (0-11) of the scale tonic, marked with a triangle instead of a
  /// dot. Null marks every member with a dot.
  final int? tonicPitchClass;

  /// When true, a two-finger pinch widens/narrows the keys via
  /// [onWidthScaleChanged]. Single-finger drags still scroll.
  final bool enableZoom;

  /// Current horizontal zoom factor, used as the basis for pinch deltas.
  final double widthScale;

  /// Called with the new (unclamped) width scale during a pinch. The host is
  /// responsible for clamping/persisting and feeding back a new
  /// [visibleWhiteKeyCount].
  final ValueChanged<double>? onWidthScaleChanged;

  /// Restores the default keyboard size. Null hides the reset action.
  final VoidCallback? onResetSize;

  @override
  State<ScrollablePianoKeyboard> createState() =>
      _ScrollablePianoKeyboardState();
}

class _ScrollablePianoKeyboardState extends State<ScrollablePianoKeyboard> {
  final ScrollController _ctl = ScrollController();

  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);
  Set<int> _previousHighlightedNotes = const <int>{};

  // Cached scroll indicator state; updated deterministically from scroll + note changes.
  ScrollIndicatorState _indicatorState = ScrollIndicatorState.none;

  // Whether recentering would move nothing; updated alongside the indicators.
  bool _isCentered = true;

  // Most recent viewport width from LayoutBuilder.
  double? _cachedViewportWidth;

  // True while a programmatic scroll animation is in flight.
  bool _isAutoScrolling = false;

  // Width scale captured at the start of a pinch; deltas multiply from here.
  double _zoomStartScale = 1.0;

  // The point under the pinch, in white keys from the keyboard's left edge,
  // and where in the viewport the fingers hold it. Null while not pinching.
  double? _pinchAnchorKeys;
  double _pinchFocalX = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _zoomStartScale = widget.widthScale;
    final width = _cachedViewportWidth;
    if (details.pointerCount < 2 || width == null || !_ctl.hasClients) return;

    // Take over from any recentering animation still running.
    _ctl.jumpTo(_ctl.offset);
    _pinchFocalX = details.localFocalPoint.dx;
    final whiteKeyWidth = PianoGeometry.whiteKeyWidthForViewport(
      viewportWidth: width,
      visibleWhiteKeyCount: widget.visibleWhiteKeyCount,
    );
    _pinchAnchorKeys = (_ctl.offset + _pinchFocalX) / whiteKeyWidth;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final anchor = _pinchAnchorKeys;
    final width = _cachedViewportWidth;
    if (details.pointerCount < 2 || anchor == null || width == null) return;
    _pinchFocalX = details.localFocalPoint.dx;

    // Pans by the fingers' movement whether or not the zoom changes, so a
    // pinch held at a zoom limit still moves the keyboard. A zoom that does
    // change is anchored again in the rebuild it causes.
    if (_ctl.hasClients) {
      final whiteKeyWidth = PianoGeometry.whiteKeyWidthForViewport(
        viewportWidth: width,
        visibleWhiteKeyCount: widget.visibleWhiteKeyCount,
      );
      _ctl.jumpTo(
        (anchor * whiteKeyWidth - _pinchFocalX).clamp(
          0.0,
          _ctl.position.maxScrollExtent,
        ),
      );
    }
    widget.onWidthScaleChanged?.call(_zoomStartScale * details.scale);
  }

  void _onScaleEnd(ScaleEndDetails _) {
    if (_pinchAnchorKeys == null) return;
    _pinchAnchorKeys = null;
    _onUserScroll();
    _updateIndicatorState();
  }

  Widget _wrapWithZoom(Widget child) {
    if (!widget.enableZoom || widget.onWidthScaleChanged == null) return child;
    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _PinchScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_PinchScaleGestureRecognizer>(
              _PinchScaleGestureRecognizer.new,
              (recognizer) {
                recognizer
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd;
              },
            ),
      },
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_onScrollOffsetChanged);
    _scheduleInitialCenter();
  }

  @override
  void dispose() {
    _ctl.removeListener(_onScrollOffsetChanged);
    _ctl.dispose();
    super.dispose();
  }

  void _onScrollOffsetChanged() {
    if (!mounted) return;
    _updateIndicatorState();
  }

  Future<void> _animateTo(
    double target, {
    Duration duration = const Duration(milliseconds: 220),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!mounted) return;
    if (!_ctl.hasClients) return;

    final clamped = target.clamp(0.0, _ctl.position.maxScrollExtent);
    final delta = (clamped - _ctl.offset).abs();
    if (delta < 1.0) return;

    if (Motion.of(context).reduced) {
      _ctl.jumpTo(clamped);
      _updateIndicatorState();
      return;
    }

    if (!_isAutoScrolling) {
      setState(() => _isAutoScrolling = true);
    }

    try {
      await _ctl.animateTo(clamped, duration: duration, curve: curve);
    } finally {
      if (mounted) {
        if (_isAutoScrolling) {
          setState(() => _isAutoScrolling = false);
        }
        _updateIndicatorState();
      }
    }
  }

  void _scheduleInitialCenter() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryCenterWhenReady(retries: 8);
    });
  }

  void _tryCenterWhenReady({required int retries}) {
    if (!mounted) return;

    // Controller not attached yet.
    if (!_ctl.hasClients) {
      _retry(retries);
      return;
    }

    final pos = _ctl.position;

    // Layout not settled / no extents yet.
    if (!pos.hasContentDimensions || pos.maxScrollExtent == 0.0) {
      _retry(retries);
      return;
    }

    _centerNow();
  }

  void _retry(int retries) {
    if (retries <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryCenterWhenReady(retries: retries - 1);
    });
  }

  Set<int> get _focusNotes => widget.highlightedNoteNumbers;

  void _centerNow() {
    if (!mounted) return;
    _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(
      0,
    ); // allow follow immediately

    final viewport = _viewport();
    if (viewport == null) return;

    unawaited(_animateTo(_centerTarget(viewport)));
  }

  /// Where recentering scrolls to: the sounding notes, or the exercise while
  /// nothing is sounding.
  double _centerTarget(KeyboardViewport viewport) => _focusNotes.isEmpty
      ? PianoScrollPolicy.frameTarget(
          viewport,
          frame: widget.frameNoteNumbers,
          anchors: widget.anchorNoteNumbers,
        )
      : PianoScrollPolicy.centerTarget(viewport, _focusNotes);

  /// Whether recentering from [viewport] would move less than [_animateTo]
  /// bothers to.
  bool _centeredIn(KeyboardViewport? viewport) =>
      viewport == null || (_centerTarget(viewport) - viewport.offset).abs() < 1;

  /// Long-press context menu surfacing the keyboard's otherwise-hidden view
  /// actions: recenter (also the body double-tap) and reset size (also the
  /// handle double-tap). Each is disabled where it would change nothing, and
  /// reset also where no [onResetSize] is given.
  Future<void> _showQuickActions(LongPressStartDetails details) async {
    if (!mounted) return;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    unawaited(Feedback.forLongPress(context));

    final canResetSize = widget.onResetSize != null;

    final position = RelativeRect.fromRect(
      details.globalPosition & const Size(40, 40),
      Offset.zero & overlay.size,
    );

    final action = await showMenu<_PianoQuickAction>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<_PianoQuickAction>(
          value: _PianoQuickAction.center,
          enabled: !_centeredIn(_viewport()),
          child: const _QuickActionRow(
            icon: Icons.center_focus_strong_outlined,
            label: 'Recenter keyboard',
          ),
        ),
        PopupMenuItem<_PianoQuickAction>(
          value: _PianoQuickAction.resetSize,
          enabled: canResetSize,
          child: const _QuickActionRow(
            icon: Icons.straighten_outlined,
            label: 'Reset keyboard size',
          ),
        ),
      ],
    );

    if (!mounted || action == null) return;
    switch (action) {
      case _PianoQuickAction.center:
        _centerNow();
      case _PianoQuickAction.resetSize:
        _resetKeyboardSize();
    }
  }

  void _resetKeyboardSize() {
    widget.onResetSize?.call();
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  void didUpdateWidget(covariant ScrollablePianoKeyboard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!setEquals(oldWidget.frameNoteNumbers, widget.frameNoteNumbers) ||
        !setEquals(oldWidget.anchorNoteNumbers, widget.anchorNoteNumbers)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerNow();
      });
    }

    // If notes changed, consider recentering.
    if (!setEquals(oldWidget.highlightedNoteNumbers, _focusNotes)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _autoCenterIfNeeded(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateIndicatorState();
      });
    }

    // If visible key count changed (rotation, zoom), keep things stable by
    // recentering, on the exercise while nothing is sounding. A pinch holds
    // its own anchor instead.
    if (oldWidget.visibleWhiteKeyCount != widget.visibleWhiteKeyCount &&
        _pinchAnchorKeys == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNotes.isEmpty ? _centerNow() : _autoCenterIfNeeded(force: true);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateIndicatorState();
      });
    }
  }

  void _onUserScroll() {
    _lastUserScroll = DateTime.now();
    // Reset diff baseline so follow logic doesn't interpret changes during the
    // cooldown as a large "added" burst once suppression ends.
    _previousHighlightedNotes = Set<int>.from(_focusNotes);
  }

  bool get _isAutoCenterSuppressed =>
      DateTime.now().difference(_lastUserScroll) < widget.autoCenterSuppression;

  /// Snapshot of layout and scroll position for the policy, or null before
  /// layout and scroll attachment settle.
  KeyboardViewport? _viewport({double? viewportWidth}) {
    final double? width =
        viewportWidth ?? _cachedViewportWidth ?? context.size?.width;
    if (width == null || width <= 0) return null;
    if (!_ctl.hasClients) return null;

    return KeyboardViewport(
      geometry: PianoGeometry(
        firstWhiteMidi: widget.lowestNoteNumber,
        whiteKeyCount: widget.fullWhiteKeyCount,
      ),
      whiteKeyWidth: PianoGeometry.whiteKeyWidthForViewport(
        viewportWidth: width,
        visibleWhiteKeyCount: widget.visibleWhiteKeyCount,
      ),
      width: width,
      offset: _ctl.offset,
      maxScrollExtent: _ctl.position.maxScrollExtent,
    );
  }

  void _updateIndicatorState({double? viewportWidth}) {
    final double? width = viewportWidth ?? _cachedViewportWidth;
    if (width == null || width <= 0) return;

    final viewport = _viewport(viewportWidth: width);
    final next = viewport == null
        ? ScrollIndicatorState.none
        : PianoScrollPolicy.indicatorState(
            viewport,
            highlighted: _focusNotes,
            previous: _indicatorState,
          );

    final centered = _centeredIn(viewport);

    if (next != _indicatorState || centered != _isCentered) {
      setState(() {
        _indicatorState = next;
        _isCentered = centered;
      });
    }
  }

  void _autoCenterIfNeeded({bool force = false}) {
    if (!mounted) return;
    if (!widget.autoCenter && !force) return;
    if (_isAutoCenterSuppressed && !force) return;

    final next = _focusNotes;
    if (next.isEmpty) {
      _previousHighlightedNotes = const <int>{};
      return;
    }

    final viewport = _viewport();
    if (viewport == null) return;

    // Diff against the last known highlighted set, then update the baseline.
    final prev = _previousHighlightedNotes;
    final added = next.difference(prev);
    final removed = prev.difference(next);
    _previousHighlightedNotes = Set<int>.from(next);

    final target = PianoScrollPolicy.autoCenterTarget(
      viewport,
      highlighted: next,
      added: added,
      removed: removed,
      force: force,
    );
    if (target != null) unawaited(_animateTo(target));
  }

  Future<void> _handleChevronTap(AxisDirection direction) async {
    if (!mounted) return;
    if (_isAutoScrolling) return;
    if (!_ctl.hasClients) return;

    final viewport = _viewport();
    if (viewport == null) return;

    final target = PianoScrollPolicy.chevronTarget(
      viewport,
      highlighted: _focusNotes,
      towardLeft: direction == AxisDirection.left,
      indicator: _indicatorState,
    );
    if (target == null) return;
    await _animateTo(target);
  }

  @override
  Widget build(BuildContext context) {
    // Reset is offered as an accessibility action (mirroring the long-press
    // menu) only where sizing is adjustable and not already at the default.
    final canResetSize = widget.onResetSize != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;

        // Capture the latest viewport width for deterministic indicator state computation.
        // If it changes (rotation / resize), recompute after this frame.
        final previousWidth = _cachedViewportWidth;
        if (previousWidth != viewportWidth) {
          _cachedViewportWidth = viewportWidth;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _updateIndicatorState(viewportWidth: viewportWidth);
          });
          // A viewport width change also invalidates the preserved pixel
          // offset, which would land on arbitrary keys; recenter like the
          // explicit center action (active notes, middle C when idle). The
          // first layout is handled by the initial center instead. Pinch
          // zoom is unaffected: it changes the key count, not this width.
          if (previousWidth != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _centerNow();
            });
          }
        }

        final whiteKeyWidth = PianoGeometry.whiteKeyWidthForViewport(
          viewportWidth: viewportWidth,
          visibleWhiteKeyCount: widget.visibleWhiteKeyCount,
        );
        final contentWidth = whiteKeyWidth * widget.fullWhiteKeyCount;

        // Keep the point under the pinch under the fingers in the same frame
        // the keys change width, rather than correcting it afterwards.
        final anchor = _pinchAnchorKeys;
        if (anchor != null && _ctl.hasClients) {
          final maxOffset = math.max(0.0, contentWidth - viewportWidth);
          _ctl.position.correctPixels(
            (anchor * whiteKeyWidth - _pinchFocalX).clamp(0.0, maxOffset),
          );
        }

        return SizedBox(
          height: widget.height,
          child: Stack(
            children: [
              Semantics(
                container: true,
                label: 'Piano keyboard',
                hint: 'Horizontally scrollable. Use the recenter keyboard action to bring it back.',
                customSemanticsActions: {
                  if (!_isCentered)
                    const CustomSemanticsAction(label: 'Recenter keyboard'):
                        _centerNow,
                  if (canResetSize)
                    const CustomSemanticsAction(label: 'Reset keyboard size'):
                        _resetKeyboardSize,
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onDoubleTap: _centerNow,
                  onLongPressStart: _showQuickActions,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification &&
                          n.dragDetails != null) {
                        _onUserScroll();
                      }
                      if (n is ScrollUpdateNotification &&
                          n.dragDetails != null) {
                        _onUserScroll();
                      }
                      return false;
                    },
                    child: _wrapWithZoom(
                      SingleChildScrollView(
                        controller: _ctl,
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: SizedBox(
                          width: contentWidth,
                          height: widget.height,
                          child: PianoKeyboard(
                            whiteKeyCount: widget.fullWhiteKeyCount,
                            firstMidiNote: widget.lowestNoteNumber,
                            highlightedNoteNumbers:
                                widget.highlightedNoteNumbers,
                            scaleNoteNumbers: widget.scaleNoteNumbers,
                            normalHighlightPitchClasses:
                                widget.normalHighlightPitchClasses,
                            tonicPitchClass: widget.tonicPitchClass,
                            height: widget.height,
                            decorations: widget.decorations,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 6,
                top: 0,
                bottom: 0,
                child: _OffscreenNoteCue(
                  direction: AxisDirection.left,
                  visible: _indicatorState.showLeft,
                  enabled: !_isAutoScrolling,
                  onTap: () => _handleChevronTap(AxisDirection.left),
                ),
              ),
              Positioned(
                right: 6,
                top: 0,
                bottom: 0,
                child: _OffscreenNoteCue(
                  direction: AxisDirection.right,
                  visible: _indicatorState.showRight,
                  enabled: !_isAutoScrolling,
                  onTap: () => _handleChevronTap(AxisDirection.right),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickActionRow extends StatelessWidget {
  const _QuickActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }
}

class _OffscreenNoteCue extends StatelessWidget {
  const _OffscreenNoteCue({
    required this.direction,
    required this.visible,
    required this.enabled,
    required this.onTap,
  });

  final AxisDirection direction;
  final bool visible;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final directionLabel = direction == AxisDirection.left ? 'left' : 'right';
    final semanticsLabel = 'Reveal notes to the $directionLabel';

    final icon = direction == AxisDirection.left
        ? Icons.chevron_left
        : Icons.chevron_right;

    final showOpacity = visible ? 1.0 : 0.0;
    final showScale = visible ? 1.0 : 0.92;

    return IgnorePointer(
      ignoring: !visible || !enabled,
      child: AnimatedOpacity(
        opacity: showOpacity,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: AnimatedScale(
          scale: showScale,
          duration: Motion.of(context)
              .travel(const Duration(milliseconds: 140)),
          curve: Curves.easeOutCubic,
          child: Center(
            child: Material(
              type: MaterialType.transparency,
              child: Semantics(
                container: true,
                label: semanticsLabel,
                hidden: !visible,
                button: true,
                enabled: visible && enabled,
                onTapHint: semanticsLabel,
                child: Tooltip(
                  message: semanticsLabel,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: enabled ? onTap : null,
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: cs.surface.withValues(
                              alpha: enabled ? 0.55 : 0.40,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            child: Icon(
                              icon,
                              size: 20,
                              color: cs.onSurfaceVariant.withValues(
                                alpha: enabled ? 0.85 : 0.55,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
