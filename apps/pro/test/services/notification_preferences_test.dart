// The warning-alerts preference (cell imbalance / over-current). It is local
// state in SharedPreferences that rides the FCM registration payload; the
// default matters because these alerts used to be silent, so a fresh install
// must still receive them unless the user opts out.
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('protection-warning alerts default to on', () async {
    expect(await NotificationService.instance.isWarningsEnabled(), isTrue);
  });

  test('protection-warning alerts can be turned off and the choice persists', () async {
    await NotificationService.instance.setWarningsEnabled(false);
    expect(await NotificationService.instance.isWarningsEnabled(), isFalse);

    await NotificationService.instance.setWarningsEnabled(true);
    expect(await NotificationService.instance.isWarningsEnabled(), isTrue);
  });
}
