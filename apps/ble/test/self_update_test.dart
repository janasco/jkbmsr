import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/self_update.dart';

void main() {
  group('isPlayManagedInstall', () {
    test('Play Store installer is Play-managed', () {
      expect(SelfUpdate.isPlayManagedInstall('com.android.vending'), isTrue);
    });

    test('sideload / third-party installers are not Play-managed', () {
      expect(SelfUpdate.isPlayManagedInstall(null), isFalse);
      expect(
          SelfUpdate.isPlayManagedInstall('com.android.packageinstaller'),
          isFalse);
      expect(SelfUpdate.isPlayManagedInstall('org.fdroid.fdroid'),
          isFalse);
      expect(SelfUpdate.isPlayManagedInstall('com.amazon.venezia'), isFalse);
    });
  });
}
