import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/main.dart';

import 'support/fake_flutter_blue_plus.dart';

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('JKBMSR BLE App test', (WidgetTester tester) async {
    // flutter_blue_plus has no platform implementation on the Dart VM, so
    // install a no-op one — otherwise the app's adapter-state subscription
    // throws UnsupportedError during initState and the test can never pump.
    await tester.pumpWidget(const JkbmsrBleApp());
    expect(find.byType(JkbmsrBleApp), findsOneWidget);
  });
}
