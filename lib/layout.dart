import 'package:material_ui/material_ui.dart';

/// How much room the window has across.
///
/// Material 3's window size classes, so the breakpoints match what every other
/// adaptive Flutter surface uses. Classes rather than pixels, because what a
/// layout needs to know is whether there is room for another pane, not how
/// many logical pixels it has.
enum WindowWidthClass {
  /// A phone held upright, and anything narrower.
  compact(0),

  /// A phone on its side, a small tablet upright, a narrow window.
  medium(600),

  /// A tablet on its side, and most desktop windows.
  expanded(840),

  /// A large tablet or a wide desktop window.
  large(1200),

  /// A desktop window with room to spare.
  extraLarge(1600);

  const WindowWidthClass(this.minimumWidth);

  /// The narrowest window in this class, in logical pixels.
  final double minimumWidth;

  /// The class [width] falls in.
  static WindowWidthClass of(double width) =>
      values.lastWhere((size) => width >= size.minimumWidth);

  /// Whether this class has at least the room [other] does.
  bool isAtLeast(WindowWidthClass other) => index >= other.index;
}

/// How much room the window has down.
///
/// Its own axis rather than an orientation flag, because the thing that breaks
/// a stacked layout is running out of height, and a phone on its side and a
/// window with a keyboard over it run out of it the same way.
enum WindowHeightClass {
  /// A phone on its side, or a window most of the way collapsed.
  compact(0),

  /// A phone held upright, and most tablets on their side.
  medium(480),

  /// A tablet held upright, and most desktop windows.
  expanded(900);

  const WindowHeightClass(this.minimumHeight);

  /// The shortest window in this class, in logical pixels.
  final double minimumHeight;

  /// The class [height] falls in.
  static WindowHeightClass of(double height) =>
      values.lastWhere((size) => height >= size.minimumHeight);

  /// Whether this class has at least the room [other] does.
  bool isAtLeast(WindowHeightClass other) => index >= other.index;
}

/// The room the app has, and the decisions that follow from it.
///
/// One place where a window's shape becomes a number a screen uses, so the
/// numbers stay consistent between screens and a change to any of them is one
/// edit. A screen asks what it should do; it does not measure the window and
/// decide for itself.
///
/// Not held in a provider. The window's shape is already inherited state that
/// rebuilds what depends on it, and a second copy of it in application state
/// would be a cache of something the framework hands out for free.
@immutable
class Layout {
  /// How much room there is across.
  final WindowWidthClass width;

  /// How much room there is down.
  final WindowHeightClass height;

  /// Whether the window is wider than it is tall.
  ///
  /// Kept as the coarse fact rather than as the size it came from, so a layout
  /// changes when the window's shape does and not when a pixel does.
  final bool isWide;

  const Layout({
    required this.width,
    required this.height,
    required this.isWide,
  });

  /// The layout a window of [size] gets.
  factory Layout.forWindow(Size size) => Layout(
    width: WindowWidthClass.of(size.width),
    height: WindowHeightClass.of(size.height),
    isWide: size.width > size.height,
  );

  /// The layout in force, from the nearest [LayoutScope] or, outside one, from
  /// the window itself.
  ///
  /// The fallback is what lets a widget be pumped on its own in a test or a
  /// preview without a scope around it, and it reads the same window the scope
  /// would have.
  static Layout of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_InheritedLayout>()?.layout ??
      Layout.forWindow(MediaQuery.sizeOf(context));

  /// The space between a screen's content and its edges.
  double get gutter => switch (width) {
    WindowWidthClass.compact => 24,
    WindowWidthClass.medium => 32,
    _ => 40,
  };

  /// How wide content that is read rather than looked at may get.
  ///
  /// A line of text running the full width of a tablet is a line nobody
  /// finishes, so text-shaped screens center inside this instead.
  double get readableWidth => 640;

  /// Whether the screen has room to put two things beside each other.
  ///
  /// A window on its side, and wide enough for two panes to each be worth
  /// having. Orientation is what decides it rather than the width class alone,
  /// because a tablet held upright is wide by any measure and still wants its
  /// content stacked.
  bool get hasRoomBeside => isWide && width.isAtLeast(WindowWidthClass.medium);

  /// How tall the on-screen keyboard is drawn.
  ///
  /// It is a diagram of the instrument rather than something played, so it
  /// takes what is left over: enough to read the marks on a phone upright, and
  /// no more than a third of a window that is on its side.
  double get instrumentHeight => switch (height) {
    WindowHeightClass.compact => 120,
    WindowHeightClass.medium => 160,
    WindowHeightClass.expanded => 200,
  };

  @override
  bool operator ==(Object other) =>
      other is Layout &&
      other.width == width &&
      other.height == height &&
      other.isWide == isWide;

  @override
  int get hashCode => Object.hash(width, height, isWide);

  @override
  String toString() =>
      'Layout(${width.name}, ${height.name}, ${isWide ? 'wide' : 'tall'})';
}

/// Puts the window's [Layout] in the tree, above every route.
///
/// Installed from `MaterialApp.builder`, so routes, sheets, and dialogs all
/// read the same one, and it is recomputed when the window changes shape.
class LayoutScope extends StatelessWidget {
  const LayoutScope({required this.child, this.layout, super.key});

  final Widget child;

  /// The layout to impose, for a test or a preview that is showing what a
  /// window shape does rather than running in one.
  final Layout? layout;

  @override
  Widget build(BuildContext context) => _InheritedLayout(
    layout: layout ?? Layout.forWindow(MediaQuery.sizeOf(context)),
    child: child,
  );
}

class _InheritedLayout extends InheritedWidget {
  const _InheritedLayout({required this.layout, required super.child});

  final Layout layout;

  @override
  bool updateShouldNotify(_InheritedLayout oldWidget) =>
      oldWidget.layout != layout;
}
