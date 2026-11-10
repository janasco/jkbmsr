import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_contributor/main.dart';
import 'package:jkbmsr_contributor/screens/home_screen.dart';
import 'package:jkbmsr_contributor/services/app_info.dart';
import 'package:jkbmsr_contributor/services/coverage_service.dart';

import 'support/fake_universal_ble.dart';

void main() {
  setUp(installFakeUniversalBle);

  testWidgets('app launches to the home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ContributorApp(
        // The corpus line is cosmetic; keep this smoke test off the network.
        coverageService: CoverageService(
          client: MockClient(
            (_) async => http.Response('{"contributions":12,"models":9}', 200),
          ),
        ),
      ),
    );

    // The shell mounts and lands on the placeholder home screen.
    expect(find.byType(HomeScreen), findsOneWidget);

    // The screen identifies the app and says what it is for.
    expect(find.text(AppInfo.appName), findsWidgets);
    expect(find.text(AppInfo.tagline), findsOneWidget);

    // The capture flow is reachable from home.
    expect(find.text('Start a capture'), findsOneWidget);
  });
}
