import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// One tappable semantics node whose on-screen hit area is smaller than the
/// recommended minimum (48x48dp, or 44x44dp for secondary controls).
class TapTargetViolation {
  const TapTargetViolation(this.label, this.size);

  final String label;
  final Size size;

  double get smallestSide => size.width < size.height ? size.width : size.height;

  @override
  String toString() =>
      '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}  "${label.isEmpty ? '<no label>' : label}"';
}

/// Walks the live semantics tree and returns every node that is tappable —
/// either flagged as a button or carrying a tap action — whose bounding box is
/// under [minSize] on either axis, plus the total number of tappable nodes
/// seen (so callers can detect a vacuous, empty walk).
///
/// The tree must already be enabled (call `tester.ensureSemantics()` and pump
/// first). Sizes are read off [SemanticsNode.rect], i.e. the node's own
/// on-screen hit area, which is exactly what a finger has to hit.
({List<TapTargetViolation> violations, int tappableCount}) collectTapTargetViolations(
  WidgetTester tester,
  double minSize,
) {
  final renderViews = tester.binding.renderViews;
  final renderView = renderViews.firstWhere(
    (view) => view.flutterView == tester.view,
    orElse: () => renderViews.first,
  );
  final root = renderView.owner?.semanticsOwner?.rootSemanticsNode;
  if (root == null) {
    throw StateError(
      'The semantics tree is not enabled — call tester.ensureSemantics() '
      'and pump a frame before collecting tap targets.',
    );
  }

  final violations = <TapTargetViolation>[];
  var tappableCount = 0;

  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final tappable = data.hasAction(SemanticsAction.tap) ||
        data.flagsCollection.isButton ||
        data.hasAction(SemanticsAction.longPress);
    if (tappable) {
      tappableCount++;
      final size = node.rect.size;
      if (size.width < minSize - 0.01 || size.height < minSize - 0.01) {
        violations.add(TapTargetViolation(data.label, size));
      }
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  visit(root);
  violations.sort((a, b) => a.smallestSide.compareTo(b.smallestSide));
  return (violations: violations, tappableCount: tappableCount);
}

/// Enables the semantics tree, lets it build, then fails with a single message
/// listing every tappable node smaller than [minSize] (smallest first),
/// instead of stopping at the first offender. Always disposes the semantics
/// handle before returning/raising so the test framework's end-of-test check
/// stays clean.
Future<void> expectTapTargetsAtLeast(
  WidgetTester tester, {
  required double minSize,
  required String where,
}) async {
  final handle = tester.ensureSemantics();
  await tester.pump();
  try {
    final result = collectTapTargetViolations(tester, minSize);
    if (result.tappableCount == 0) {
      fail(
        '$where exposed no tappable semantics nodes at all — the walk found '
        'nothing to measure, so this test would be vacuous.',
      );
    }
    if (result.violations.isEmpty) return;

    final listing = result.violations.map((v) => '  • $v').join('\n');
    fail(
      '$where has ${result.violations.length} tappable control(s) smaller than '
      '${minSize.toStringAsFixed(0)}dp (smallest first):\n$listing',
    );
  } finally {
    handle.dispose();
  }
}
