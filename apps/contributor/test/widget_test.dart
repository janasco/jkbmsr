import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/main.dart';
import 'package:jkbmsr_contributor/screens/home_screen.dart';
import 'package:jkbmsr_contributor/services/app_info.dart';

import 'support/fake_flutter_blue_plus.dart';

void main() {
  setUp(installFakeFlutterBluePlus);

  testWidgets('app launches to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ContributorApp());

    // The shell mounts and lands on the placeholder home screen.
    expect(find.byType(HomeScreen), findsOneWidget);

    // The screen identifies the app and says what it is for.
    expect(find.text(AppInfo.appName), findsWidgets);
    expect(find.text(AppInfo.tagline), findsOneWidget);

    // The capture flow is reachable from home.
    expect(find.text('Start a capture'), findsOneWidget);
  });
}
