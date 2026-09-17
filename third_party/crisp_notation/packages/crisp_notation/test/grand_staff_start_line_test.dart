import 'package:crisp_notation/crisp_notation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'grand_staff_view_test.dart' show demo, wrap;
import 'interactive_grand_staff_view_test.dart' show eightBarPiano;
import 'test_setup.dart';

void main() {
  setUpAll(setUpCrispNotationForTests);

  for (final space in [5.0, 12.0]) {
    testWidgets('start line spans both staves at scale $space', (tester) async {
      await tester.pumpWidget(wrap(GrandStaffView(
        grandStaff: demo(),
        staffSpace: space,
      )));
      final render = tester.renderObject<RenderGrandStaffView>(
        find.byType(GrandStaffView),
      );
      expect(
          render,
          paints
            ..something((method, arguments) =>
                method == #drawLine &&
                arguments[0] == render.upperOrigin &&
                arguments[1] == render.lowerOrigin + Offset(0, 4 * space)));
    });
  }

  testWidgets('every wrapped system has a full start line', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(
      width: 350,
      child: InteractiveGrandStaffView(
        grandStaff: eightBarPiano(),
        staffSpace: 8,
      ),
    )));
    final render = tester.renderObject<RenderInteractiveGrandStaffView>(
      find.byType(InteractiveGrandStaffView),
    );
    expect(render.grandStaffSystems!.systems.length, greaterThan(1));
    for (var i = 0; i < render.grandStaffSystems!.systems.length; i++) {
      expect(
          render,
          paints
            ..something((method, arguments) =>
                method == #drawLine &&
                arguments[0] == render.upperOrigin(i) &&
                arguments[1] == render.lowerOrigin(i) + const Offset(0, 32)));
    }
  });
}
