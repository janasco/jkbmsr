import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/models/consent.dart';
import 'package:jkbmsr_contributor/services/consent_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('nothing is stored before the user answers (default off)', () async {
    final store = SharedPreferencesConsentStore();
    expect(await store.read(), isNull);
  });

  test('a granted decision persists with its timestamp', () async {
    final store = SharedPreferencesConsentStore();
    await store.write(ConsentState(
      decision: ConsentDecision.granted,
      decidedAt: DateTime.utc(2026, 10, 14, 9, 30),
    ));

    final reread = await SharedPreferencesConsentStore().read();
    expect(reread, isNotNull);
    expect(reread!.isGranted, isTrue);
    expect(reread.decidedAt, DateTime.utc(2026, 10, 14, 9, 30));
    expect(reread.record!.scope, ConsentState.scope);
  });

  test('a declined decision persists and blocks granting', () async {
    final store = SharedPreferencesConsentStore();
    await store.write(ConsentState(
      decision: ConsentDecision.declined,
      decidedAt: DateTime.utc(2026, 10, 14, 9, 31),
    ));

    final reread = await SharedPreferencesConsentStore().read();
    expect(reread!.isGranted, isFalse);
    expect(reread.record, isNull);
  });

  test('revoking clears the decision', () async {
    final store = SharedPreferencesConsentStore();
    await store.write(ConsentState(
      decision: ConsentDecision.granted,
      decidedAt: DateTime.utc(2026, 10, 14),
    ));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('a corrupt stored value fails closed (reads as unanswered)', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('consent.v1', 'not json');
    expect(await SharedPreferencesConsentStore().read(), isNull);

    await prefs.setString('consent.v1', '{"decision":"maybe"}');
    expect(await SharedPreferencesConsentStore().read(), isNull);
  });
}
