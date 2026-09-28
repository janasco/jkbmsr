// Accessibility device pass: every tappable control must announce something.
//
// A control whose semantics node is flagged `isButton` (or carries a tap
// action) but has no label and no tooltip is invisible to a screen reader: it
// announces "button" and nothing about what it does. The shell is mounted
// directly, and the alerts screen's search-clear control is exercised by
// typing a query so the suffix icon actually renders.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:jkbmsr_pro/app/app.dart';
import 'package:jkbmsr_pro/features/alerts/alerts_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

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
    // Text fields are focused by a tap and legitimately carry their purpose in
    // the hint/editable semantics rather than a label; they are not controls
    // that "announce nothing".
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shell controls all announce a label', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: JKBMSRShellLayout(
        currentRoute: '/dashboard?deviceId=gw-1',
        onNavigate: (_) {},
        child: const SizedBox.shrink(),
      ),
    ));
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    try {
      final unlabeled = _unlabeledTappables(tester);
      expect(unlabeled, isEmpty,
          reason: 'unlabeled tappable controls: ${unlabeled.join(', ')}');
    } finally {
      handle.dispose();
    }
  });

  testWidgets('alerts search-clear control announces a label', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/alerts')) {
          return _json({'alerts': <Object>[], 'hasMore': false}, 200);
        }
        return _json({}, 200);
      }),
    );

    await tester.pumpWidget(MaterialApp(
      theme: JKBMSRTheme.darkTheme,
      home: const AlertsScreen(),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'battery');
    await tester.pumpAndSettle();

    final handle = tester.ensureSemantics();
    try {
      final unlabeled = _unlabeledTappables(tester);
      expect(unlabeled, isEmpty,
          reason: 'unlabeled tappable controls: ${unlabeled.join(', ')}');
    } finally {
      handle.dispose();
    }
    await tester.pump(const Duration(seconds: 6)); // drain toast timers
  });
}
