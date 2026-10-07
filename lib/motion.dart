import 'package:material_ui/material_ui.dart';

/// How long the practice screens take to hand over from one state to the
/// next, and how they move while they do.
///
/// One duration and one curve for every part of it. The statement leaving the
/// screen, the bar's controls giving up their width, and the task arriving in
/// their place are one movement, and they only read as one if they are timed
/// as one.
const Duration attemptTransition = Duration(milliseconds: 280);
const Curve attemptCurve = Curves.easeInOutCubic;

/// Whether the platform has asked for reduced motion, and what that allows.
///
/// Reduced motion keeps pacing and fades but drops movement: anything that
/// travels, resizes, or loops arrives at its end state at once.
@immutable
class Motion {
  final bool reduced;

  const Motion({required this.reduced});

  /// Android reports "Remove animations" as [disableAnimations], while iOS
  /// reports Reduce Motion separately as [reduceMotion] without setting it.
  factory Motion.fromFeatures({
    required bool disableAnimations,
    required bool reduceMotion,
  }) => Motion(reduced: disableAnimations || reduceMotion);

  /// How long something moving across the screen takes.
  Duration travel(Duration duration) => reduced ? Duration.zero : duration;

  /// The motion in force, from the nearest [MotionScope] or, outside one, from
  /// the platform directly.
  static Motion of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InheritedMotion>()?.motion ??
      _read(context);

  static Motion _read(BuildContext context) => Motion.fromFeatures(
    disableAnimations: MediaQuery.disableAnimationsOf(context),
    reduceMotion: View.of(context)
        .platformDispatcher
        .accessibilityFeatures
        .reduceMotion,
  );

  @override
  bool operator ==(Object other) => other is Motion && other.reduced == reduced;

  @override
  int get hashCode => reduced.hashCode;
}

/// Keeps [Motion.of] current as the accessibility settings change.
///
/// [MediaQuery] rebuilds its dependents for [MediaQueryData.disableAnimations]
/// but has no aspect for iOS Reduce Motion, so that change is observed here.
class MotionScope extends StatefulWidget {
  const MotionScope({required this.child, super.key});

  final Widget child;

  @override
  State<MotionScope> createState() => _MotionScopeState();
}

class _MotionScopeState extends State<MotionScope> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      _InheritedMotion(motion: Motion._read(context), child: widget.child);
}

class _InheritedMotion extends InheritedWidget {
  const _InheritedMotion({required this.motion, required super.child});

  final Motion motion;

  @override
  bool updateShouldNotify(_InheritedMotion oldWidget) =>
      oldWidget.motion != motion;
}
