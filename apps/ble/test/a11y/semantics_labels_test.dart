// Accessibility device pass: every tappable control must announce something.
//
// A control whose semantics node is flagged `isButton` (or carries a tap
// action) but has an empty label is invisible to a screen reader: it announces
// "button" and nothing about what it does. This walks the live semantics tree
// on every tab of the real app and fails with the full list.
//
// The scan button on the Devices screen and the header menu/overflow controls
// were the offenders; they are icon-only, so they had no descendant text to
// borrow a label from.
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';

import '../support/fake_flutter_blue_plus.dart';

class _Unlabeled {
  const _Unlabeled(this.size);
  final Size size;

  @override
  String toString() =>
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}';
}

List<_Unlabeled> _unlabeledTappables(WidgetTester tester) {
  final renderView = tester.binding.renderViews.firstWhere(
    (view) => view.flutterView == tester.view,
    orElse: () => tester.binding.renderViews.first,
  );
  final root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    throw StateError('Semantics tree not enabled; call ensureSemantics() first.');
  }

  final out = <_Unlabeled>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final tappable = data.hasAction(SemanticsAction.tap) ||
        data.flagsCollection.isButton ||
        data.hasAction(SemanticsAction.longPress);
    // A tooltip is also an announced affordance, so a node with either a label
    // or a tooltip is discoverable and is not counted here. Text fields carry
    // their purpose in hint/editable semantics, not a label.
    final isTextField = data.flagsCollection.isTextField ||
        data.hasAction(SemanticsAction.setText);
    if (tappable &&
        !isTextField &&
        data.label.trim().isEmpty &&
        data.tooltip.trim().isEmpty) {
      out.add(_Unlabeled(node.rect.size));
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  return out;
}

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('every tappable control on every tab announces a label',
      (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const JkbmsrBleApp());
    await tester.pump(const Duration(milliseconds: 600));

    final start = find.text('START SCANNING');
    if (start.evaluate().isNotEmpty) {
      await tester.tap(start);
      await tester.pump(const Duration(milliseconds: 600));
    }

    final handle = tester.ensureSemantics();
    try {
      var checkedAny = false;
      for (final tab in ['STATUS', 'CELLS', 'DEVICES', 'SETTINGS']) {
        final finder = find.text(tab);
        if (finder.evaluate().isNotEmpty) {
          await tester.tap(finder.last);
          await tester.pump(const Duration(milliseconds: 500));
        }
        final unlabeled = _unlabeledTappables(tester);
        if (unlabeled.isNotEmpty) {
          fail('$tab has ${unlabeled.length} tappable control(s) that announce '
              'nothing: ${unlabeled.join(', ')}');
        }
        checkedAny = true;
      }
      if (!checkedAny) {
        fail('No tab was reachable, so this test would be vacuous.');
      }
    } finally {
      handle.dispose();
    }
  });
}
