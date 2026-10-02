import 'package:flutter_test/flutter_test.dart';

import 'package:keyrecall/features/practice/item_lines.dart';

void main() {
  double characters(String text) => text.length.toDouble();
  const items = ['Up and down', '2 octaves', '60 bpm'];

  test('items that fit share one line', () {
    expect(packItems(items, 100, characters), [
      'Up and down · 2 octaves · 60 bpm',
    ]);
  });

  test('a line breaks between items, not inside one', () {
    expect(packItems(items, 30, characters), [
      'Up and down · 2 octaves',
      '60 bpm',
    ]);
  });

  test('an item too wide for any line still gets one of its own', () {
    expect(packItems(items, 8, characters), items);
  });
}
