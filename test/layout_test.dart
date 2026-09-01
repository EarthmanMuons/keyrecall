import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:keyrecall/layout.dart';

void main() {
  Layout at(double width, double height) =>
      Layout.forWindow(Size(width, height));

  group('window classes', () {
    test('a phone upright is compact across and medium down', () {
      final layout = at(390, 844);

      expect(layout.width, WindowWidthClass.compact);
      expect(layout.height, WindowHeightClass.medium);
    });

    test('the same phone on its side runs out of height, not width', () {
      final layout = at(844, 390);

      expect(layout.height, WindowHeightClass.compact);
      expect(layout.width.isAtLeast(WindowWidthClass.medium), isTrue);
      expect(layout.isWide, isTrue);
    });

    test('a tablet reaches the expanded classes', () {
      expect(at(1024, 1366).width, WindowWidthClass.expanded);
      expect(at(1366, 1024).width, WindowWidthClass.large);
      expect(at(1024, 1366).height, WindowHeightClass.expanded);
    });

    test('a class knows what it has at least as much room as', () {
      expect(
        WindowWidthClass.expanded.isAtLeast(WindowWidthClass.medium),
        isTrue,
      );
      expect(
        WindowWidthClass.medium.isAtLeast(WindowWidthClass.expanded),
        isFalse,
      );
    });
  });

  group('what the room decides', () {
    test('a phone upright stacks', () {
      expect(at(390, 844).hasRoomBeside, isFalse);
    });

    test('a phone on its side has no height to stack in', () {
      expect(at(844, 390).hasRoomBeside, isTrue);
    });

    test('a window too narrow for two panes stacks however it is turned', () {
      expect(at(560, 420).hasRoomBeside, isFalse);
    });

    test('a tablet upright has the height to stack and does', () {
      expect(
        at(834, 1194).hasRoomBeside,
        isFalse,
        reason: 'tall and not especially wide is the shape stacking is for',
      );
    });

    test('a tablet on its side has width to spare', () {
      expect(at(1194, 834).hasRoomBeside, isTrue);
    });

    test('the keyboard takes less of a window that is short of height', () {
      expect(
        at(844, 390).instrumentHeight,
        lessThan(at(390, 844).instrumentHeight),
      );
    });

    test('gutters widen with the window', () {
      expect(at(390, 844).gutter, lessThan(at(1194, 834).gutter));
    });
  });
}
