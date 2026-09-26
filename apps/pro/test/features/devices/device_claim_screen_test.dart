import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jkbmsr_pro/features/devices/device_claim_screen.dart';
import 'package:jkbmsr_pro/features/devices/qr_scan_screen.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';

/// Stands in for the real QrScanScreen so tests never touch an actual
/// camera stream: it immediately pops with a canned result.
class _FakeScanScreen extends StatelessWidget {
  final DeviceClaimQrResult? result;

  const _FakeScanScreen({this.result});

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pop(result);
    });
    return const Scaffold(body: SizedBox.shrink());
  }
}

Widget _wrap({DeviceClaimQrResult? scanResult}) {
  final router = GoRouter(
    initialLocation: '/devices/claim',
    routes: [
      GoRoute(
        path: '/devices/claim',
        builder: (context, state) => const DeviceClaimScreen(),
      ),
      GoRoute(
        path: '/devices/claim/scan',
        builder: (context, state) => _FakeScanScreen(result: scanResult),
      ),
    ],
  );
  return MaterialApp.router(
    theme: JKBMSRTheme.darkTheme,
    routerConfig: router,
  );
}

void main() {
  group('parseDeviceClaimQr', () {
    test('parses a well-formed onboard URL', () {
      final result = parseDeviceClaimQr(
        'https://app.jkbmsr.com/onboard?device=JK-BMS-0F21A3&code=ABCD1234',
      );
      expect(result, isNotNull);
      expect(result!.deviceId, 'JK-BMS-0F21A3');
      expect(result.claimCode, 'ABCD1234');
    });

    test('returns null for an unrelated URL', () {
      expect(parseDeviceClaimQr('https://example.com/'), isNull);
    });

    test('returns null when device or code is missing', () {
      expect(parseDeviceClaimQr('https://app.jkbmsr.com/onboard?device=JK-BMS-0F21A3'), isNull);
      expect(parseDeviceClaimQr('https://app.jkbmsr.com/onboard?code=ABCD1234'), isNull);
    });

    test('returns null for unparseable or empty input', () {
      expect(parseDeviceClaimQr(null), isNull);
      expect(parseDeviceClaimQr(''), isNull);
    });
  });

  group('DeviceClaimScreen QR scan wiring', () {
    testWidgets('a successful scan fills the device ID and claim code fields', (tester) async {
      await tester.pumpWidget(_wrap(
        scanResult: const DeviceClaimQrResult(deviceId: 'JK-BMS-0F21A3', claimCode: 'ABCD1234'),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan QR Code'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'JK-BMS-0F21A3'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'ABCD1234'), findsOneWidget);
    });

    testWidgets('backing out of the scanner without a result leaves the form untouched', (tester) async {
      await tester.pumpWidget(_wrap(scanResult: null));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scan QR Code'));
      await tester.pumpAndSettle();

      expect(find.text('Add a Gateway'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'JK-BMS-0F21A3'), findsNothing);
    });
  });
}
