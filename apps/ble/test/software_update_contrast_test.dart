// Software Update modal: low-emphasis text must follow the active theme.
//
// The modal used to hardcode a dark inset surface (0xFF1E2830) and light greys
// (0xFF94A3B8 / 0xFF64748B). On the light theme the inset rendered as a mid
// grey and the grey copy on it was effectively invisible. This pins the
// resolved colour so the literal can never creep back in.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/widgets/software_update_modal.dart';
import 'package:package_info_plus/package_info_plus.dart';

const _lightMuted = Color(0xFF475569); // AppColors.textMuted on light
const _darkMuted = Color(0xFF94A3B8); // AppColors.textMuted on dark

/// The no-network path resolves to the offline state; pump enough frames for
/// PackageInfo + the (test-mocked) HTTP probe to settle there.
Future<void> _pumpToOffline(WidgetTester tester, ThemeData theme) async {
  PackageInfo.setMockInitialValues(
    appName: 'JK BMS Bluetooth',
    packageName: 'com.jkbmsr.ble',
    version: '4.17.24',
    buildNumber: '44',
    buildSignature: '',
  );
  await tester.pumpWidget(MaterialApp(
    theme: theme,
    home: Scaffold(body: SoftwareUpdateModal(onClose: () {})),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Color _offlineCopyColor(WidgetTester tester) {
  final finder = find.text('Could not reach the update server.');
  expect(finder, findsOneWidget, reason: 'expected the offline state to render');
  return tester.widget<Text>(finder).style!.color!;
}

void main() {
  testWidgets('light theme: offline copy uses the readable muted tone',
      (tester) async {
    await _pumpToOffline(tester, ThemeData.light());

    expect(
      _offlineCopyColor(tester),
      _lightMuted,
      reason: 'light-mode muted text must follow the theme, not 0xFF94A3B8',
    );
  });

  testWidgets('dark theme: offline copy keeps the same token, dark value',
      (tester) async {
    await _pumpToOffline(tester, ThemeData.dark());

    expect(
      _offlineCopyColor(tester),
      _darkMuted,
      reason: 'dark mode must resolve the muted token to its dark value',
    );
  });
}
