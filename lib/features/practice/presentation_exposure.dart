import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import 'package:material_ui/material_ui.dart';

/// Whether the app had an opportunity to put something in front of a learner.
///
/// Not a claim that anybody looked. A screen cannot establish that, and a
/// record that said so would be asserting what it cannot observe. What this
/// does say is that the content was drawn, on the route in front, while the app
/// was the thing on the device's screen: everything between the app and the
/// learner's eyes was out of the way.
///
/// Five conditions rather than one, because a mounted widget satisfies none of
/// the other four. A retained screen goes on building behind a settings route,
/// a backgrounded app keeps its tree, a section below the fold of a scroll view
/// is laid out and never seen, and a screen fading in is mounted at nothing.
@immutable
class ExposureConditions {
  /// Whether the widget reporting this is still in the tree.
  final bool isMounted;

  /// Whether its route is the one in front.
  final bool isRouteCurrent;

  /// Whether the app itself is what the device is showing.
  final bool isForeground;

  /// Whether it has been laid out somewhere the viewport covers.
  final bool isOnScreen;

  /// Whether no fade above it is still bringing it in.
  final bool isFadedIn;

  const ExposureConditions({
    required this.isMounted,
    required this.isRouteCurrent,
    required this.isForeground,
    required this.isOnScreen,
    required this.isFadedIn,
  });

  /// Whether the learner had an opportunity to perceive it.
  bool get isExposed =>
      isMounted && isRouteCurrent && isForeground && isOnScreen && isFadedIn;

  @override
  String toString() =>
      'ExposureConditions(mounted: $isMounted, current: $isRouteCurrent, '
      'foreground: $isForeground, onScreen: $isOnScreen, '
      'fadedIn: $isFadedIn)';
}

/// The fades above [render] that keep it from being fully drawn yet: each one
/// still running short of opaque, or holding it at nothing.
///
/// Arrival rather than any opacity at all, so a part that rises in after the
/// screen is reported when it has arrived, not on the first frame it was
/// mounted. A fade resting part of the way, like a dimmed paused staff, is
/// settled and does not hold anything back.
List<Animation<double>> fadesOver(RenderObject render) => [
  for (
    var ancestor = render.parent;
    ancestor != null;
    ancestor = ancestor.parent
  )
    if (ancestor is RenderAnimatedOpacity &&
        (ancestor.opacity.value == 0 ||
            (ancestor.opacity.value < 1 &&
                ancestor.opacity.status.isAnimating)))
      ancestor.opacity,
];

/// Whether [content] has any of itself inside [viewport].
///
/// Any overlap at all. A stricter fraction would be a threshold nothing has
/// measured, and this is deciding whether something could have been seen
/// rather than whether it was read.
bool isWithinViewport(Rect content, Rect viewport) =>
    !content.isEmpty && content.overlaps(viewport);

/// Where [box] actually reaches the screen, in global coordinates.
///
/// Its own bounds narrowed by every ancestor that clips them. A scroll view
/// lays out all of a column it can measure and paints only the part in its
/// viewport, so a section below the fold has real global bounds and is on
/// screen in none of them. Comparing against the window alone reports it as
/// seen, which for feedback exposure is a claim about a section the learner
/// never scrolled to.
///
/// Empty when nothing of it is painted.
Rect visibleBounds(RenderBox box) {
  var visible = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  RenderObject child = box;
  for (
    var ancestor = child.parent;
    ancestor != null;
    child = ancestor, ancestor = ancestor.parent
  ) {
    final clip = ancestor.describeApproximatePaintClip(child);
    if (clip == null) continue;
    visible = visible.intersect(
      MatrixUtils.transformRect(ancestor.getTransformTo(null), clip),
    );
    if (visible.isEmpty) return Rect.zero;
  }
  return visible;
}

/// Whether the app is foregrounded, as the binding currently has it.
bool appIsForeground() =>
    SchedulerBinding.instance.lifecycleState == null ||
    SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;

/// Reports [onExposed] the first frame its child is actually in front of the
/// learner, and not before.
///
/// [onExposed] answers whether its owner accepted the report. A refusal is
/// asked again rather than merely left armed, so an exposure is never
/// permanently recorded by the surface that drew it and a refusal that nothing
/// else happens to disturb is not silently dropped. The wait doubles after
/// each refusal, so a write that is not going to succeed is not retried at
/// speed for as long as the screen is up.
///
/// Re-arms when [presentation] changes, because a second presentation is a
/// second thing to have been exposed to.
class ExposureGate extends StatefulWidget {
  const ExposureGate({
    required this.presentation,
    required this.onExposed,
    required this.child,
    super.key,
  });

  /// What is being exposed. Changing it is a new thing to report.
  final Object presentation;

  /// Records the exposure, answering whether its owner took it.
  final Future<bool> Function() onExposed;

  final Widget child;

  @override
  State<ExposureGate> createState() => _ExposureGateState();
}

/// How long a refused report waits before being asked again, and the longest
/// that wait grows to.
///
/// Timed rather than counted in frames. A frame runs only when something asks
/// for one, so a screen that has settled produces none, and a retry that waited
/// for the next frame would wait for activity that may never come.
const Duration _firstRetry = Duration(milliseconds: 250);
const Duration _slowestRetry = Duration(seconds: 30);

class _ExposureGateState extends State<ExposureGate>
    with WidgetsBindingObserver {
  /// What has been reported and accepted. Null once a new presentation
  /// arrives, and left alone while a report is in flight.
  Object? _reported;
  bool _reporting = false;

  Timer? _retry;

  /// How long to wait after the next refusal, doubling to a ceiling.
  Duration _backoff = _firstRetry;
  ScrollPosition? _scroll;
  final List<Animation<double>> _moving = [];

  /// Fades that held a report back, listened to so their arrival asks again.
  final Set<Animation<double>> _fades = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Four things move content in and out of sight without rebuilding it: the
    // route arriving, a route arriving over it, the scroll it sits in, and the
    // app leaving the foreground. Each of them is a reason to look again, and
    // the first is why a sheet is not reported from the frame it was asked
    // for: it is still below the screen then.
    _scroll?.removeListener(_scheduleCheck);
    _scroll = Scrollable.maybeOf(context)?.position
      ?..addListener(_scheduleCheck);
    for (final animation in _moving) {
      animation.removeListener(_scheduleCheck);
    }
    final route = ModalRoute.of(context);
    _moving
      ..clear()
      ..addAll([?route?.animation, ?route?.secondaryAnimation]);
    for (final animation in _moving) {
      animation.addListener(_scheduleCheck);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(ExposureGate old) {
    super.didUpdateWidget(old);
    if (old.presentation != widget.presentation) {
      _reported = null;
      _rearm();
    }
    _scheduleCheck();
  }

  @override
  void dispose() {
    _retry?.cancel();
    _scroll?.removeListener(_scheduleCheck);
    for (final animation in _moving) {
      animation.removeListener(_scheduleCheck);
    }
    for (final fade in _fades) {
      fade.removeStatusListener(_onFade);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onFade(AnimationStatus _) => _scheduleCheck();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _scheduleCheck();

  /// Looks after the frame this was asked in, which is the frame its child was
  /// drawn on.
  void _scheduleCheck() {
    if (_reported == widget.presentation || _reporting) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  ExposureConditions _conditions() {
    final render = context.findRenderObject();
    final view = View.of(context);
    final viewport = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final fading = render == null
        ? const <Animation<double>>[]
        : fadesOver(render);
    for (final fade in fading) {
      if (_fades.add(fade)) fade.addStatusListener(_onFade);
    }
    return ExposureConditions(
      isFadedIn: fading.isEmpty,
      isMounted: mounted,
      isRouteCurrent: ModalRoute.of(context)?.isCurrent ?? true,
      isForeground: appIsForeground(),
      isOnScreen:
          render is RenderBox &&
          render.hasSize &&
          isWithinViewport(visibleBounds(render), viewport),
    );
  }

  Future<void> _check() async {
    if (!mounted || _reporting || _reported == widget.presentation) return;
    if (!_conditions().isExposed) return;

    final presentation = widget.presentation;
    _reporting = true;
    var accepted = false;
    try {
      // A report that threw is a report nobody took, which is the refusal
      // case. It must not escape into the frame that asked for it. The call
      // is inside the guard as well as the wait, because a callback can throw
      // before it ever returns a future.
      accepted = await widget.onExposed();
    } on Object {
      accepted = false;
    } finally {
      // Before anything below schedules: a check asked for while this one is
      // still in flight is dropped, so nothing may ask until this is not.
      _reporting = false;
    }
    if (!mounted) return;

    // What was on screen changed while its owner was deciding. Whatever it
    // decided was about the presentation that has gone, and says nothing about
    // the one standing now, which has not been reported at all. The change
    // arrived while this was in flight, so the check it asked for was dropped
    // and this is the one that has to ask again.
    if (widget.presentation != presentation) {
      _rearm();
      // Asked for directly rather than on the next frame, for the reason the
      // retry is timed: the tree that replaced the presentation has already
      // been built, and nothing is obliged to build another.
      _retry = Timer(Duration.zero, _check);
      return;
    }

    if (accepted) {
      _reported = presentation;
      _rearm();
      return;
    }
    _retryAfterRefusal();
  }

  /// Asks again once the wait is up, and waits twice as long after that.
  ///
  /// A refusal is usually a stale attempt or a write that did not land, and
  /// neither is answered by asking again immediately or by asking forever at
  /// full speed.
  void _retryAfterRefusal() {
    _retry?.cancel();
    _retry = Timer(_backoff, _check);
    final next = _backoff * 2;
    _backoff = next > _slowestRetry ? _slowestRetry : next;
  }

  void _rearm() {
    _retry?.cancel();
    _retry = null;
    _backoff = _firstRetry;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
