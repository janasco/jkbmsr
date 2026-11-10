import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';

import 'support/fake_universal_ble.dart';

void main() {
  setUp(installFakeUniversalBle);

  testWidgets('JK BMS Bluetooth App test', (WidgetTester tester) async {
    // the BLE package has no platform implementation on the Dart VM, so
    // install a no-op one — otherwise the app's adapter-state subscription
    // throws UnsupportedError during initState and the test can never pump.
    await tester.pumpWidget(const JkbmsrBleApp());
    expect(find.byType(JkbmsrBleApp), findsOneWidget);
  });
}
