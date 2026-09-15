import 'dart:async';

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
/// Four conditions rather than one, because a mounted widget satisfies none of
/// the other three. A retained screen goes on building behind a settings route,
/// a backgrounded app keeps its tree, and a section below the fold of a scroll
/// view is laid out and never seen.
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

  const ExposureConditions({
    required this.isMounted,
    required this.isRouteCurrent,
    required this.isForeground,
    required this.isOnScreen,
  });

  /// Whether the learner had an opportunity to perceive it.
  bool get isExposed =>
      isMounted && isRouteCurrent && isForeground && isOnScreen;

  @override
  String toString() =>
      'ExposureConditions(mounted: $isMounted, current: $isRouteCurrent, '
      'foreground: $isForeground, onScreen: $isOnScreen)';
}

/// Whether [content] has any of itself inside [viewport].
///
/// Any overlap at all. A stricter fraction would be a threshold nothing has
/// measured, and this is deciding whether something could have been seen
/// rather than whether it was read.
bool isWithinViewport(Rect content, Rect viewport) =>
    !content.isEmpty && content.overlaps(viewport);

/// Whether the app is foregrounded, as the binding currently has it.
bool appIsForeground() =>
    SchedulerBinding.instance.lifecycleState == null ||
    SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;

/// Reports [onExposed] the first frame its child is actually in front of the
/// learner, and not before.
///
/// [onExposed] answers whether its owner accepted the report. A refusal leaves
/// this armed, so an exposure is never permanently recorded by the surface
/// that drew it: the transaction that owns the history decides, and until it
/// does, a later frame asks again.
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

class _ExposureGateState extends State<ExposureGate>
    with WidgetsBindingObserver {
  /// What has been reported and accepted. Null once a new presentation
  /// arrives, and left alone while a report is in flight.
  Object? _reported;
  bool _reporting = false;
  ScrollPosition? _scroll;
  final List<Animation<double>> _moving = [];

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
    if (old.presentation != widget.presentation) _reported = null;
    _scheduleCheck();
  }

  @override
  void dispose() {
    _scroll?.removeListener(_scheduleCheck);
    for (final animation in _moving) {
      animation.removeListener(_scheduleCheck);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

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
    return ExposureConditions(
      isMounted: mounted,
      isRouteCurrent: ModalRoute.of(context)?.isCurrent ?? true,
      isForeground: appIsForeground(),
      isOnScreen:
          render is RenderBox &&
          render.hasSize &&
          isWithinViewport(
            render.localToGlobal(Offset.zero) & render.size,
            viewport,
          ),
    );
  }

  Future<void> _check() async {
    if (!mounted || _reporting || _reported == widget.presentation) return;
    if (!_conditions().isExposed) return;

    final presentation = widget.presentation;
    _reporting = true;
    try {
      if (await widget.onExposed()) _reported = presentation;
    } finally {
      _reporting = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
