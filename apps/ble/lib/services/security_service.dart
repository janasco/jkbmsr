import 'app_database.dart';

/// Persists and verifies the local PIN that gates Control/Settings write
/// access. This is an app-side gate only — it is not transmitted to every
/// BMS brand's hardware (only JK-BMS's protocol embeds a password in the
/// write frame itself), so a correct PIN here means "this app is allowed
/// to send control commands," not "the BMS validated a password."
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final _db = AppDatabase();
  static const String _pinKey = 'jkbmsr_control_pin';
  static const String defaultPin = '1234';

  Future<String> getPin() async {
    final stored = await _db.getValue(_pinKey);
    return (stored == null || stored.isEmpty) ? defaultPin : stored;
  }

  Future<void> setPin(String pin) async {
    await _db.setValue(_pinKey, pin);
  }

  Future<bool> verifyPin(String entered) async {
    final actual = await getPin();
    return entered == actual;
  }
}
