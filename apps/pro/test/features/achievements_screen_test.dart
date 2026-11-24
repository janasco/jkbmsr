import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_pro/features/achievements/achievements_screen.dart';
import 'package:jkbmsr_pro/services/api_client.dart';
import 'package:jkbmsr_pro/widgets/shared/design_system/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget wrapWithTheme(Widget child) =>
    MaterialApp(theme: JKBMSRTheme.darkTheme, home: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The API client reads the session token from SharedPreferences before every
  // request. Without the mock, that read never answers and the loading spinner
  // animates forever, which reads as a hang rather than a missing test setup.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('earned and locked milestones read differently, and the scope is stated',
      (tester) async {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async {
        expect(request.url.path, endsWith('/v1/user/me/achievements'));
        return http.Response(
          '{"achievements":['
          '{"key":"first_pack","title":"First pack","detail":"Contribute your first pack.",'
          '"points":50,"earnedAt":"2026-11-24 03:10:00"},'
          '{"key":"ten_packs","title":"Ten packs","detail":"Ten accepted packs.",'
          '"points":100,"earnedAt":null}'
          '],"earned":1,"total":2,"pointsEarned":50}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await tester.pumpWidget(wrapWithTheme(const AchievementsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2 earned'), findsOneWidget);
    expect(find.text('50 points from achievements'), findsOneWidget);
    expect(find.text('First pack'), findsOneWidget);
    expect(find.text('Ten packs'), findsOneWidget);
    // One verified mark for the earned row, one lock for the other.
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    // The account scope is on screen, not only in the API.
    expect(find.textContaining('Points belong to your account'), findsOneWidget);
  });

  testWidgets('a failed read never claims an empty record', (tester) async {
    APIClient.configure(
      baseUrl: 'https://test.local',
      client: MockClient((request) async => http.Response('{"error":"boom"}', 500)),
    );

    await tester.pumpWidget(wrapWithTheme(const AchievementsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('This is not an empty record'), findsOneWidget);
    expect(find.textContaining('0 of'), findsNothing);
  });
}
