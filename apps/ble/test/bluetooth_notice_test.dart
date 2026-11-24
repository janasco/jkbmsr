import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/ble_adapter.dart';
import 'package:jkbmsr_ble/services/bluetooth_notice.dart';

// The adapter boundary is three different problems, not one. This mapper is
// what lets the banner say "allow Nearby devices" for a denied permission
// instead of "Bluetooth is off" with a button that cannot grant it.

void main() {
  test('off keeps the turn-on action and the original wording', () {
    final notice = bluetoothNoticeFor(BleAdapterState.off)!;
    expect(notice.title, 'Bluetooth is off');
    expect(notice.body, 'Turn it on to scan for BMS devices.');
    expect(notice.offersTurnOn, isTrue);
  });

  test('unauthorized points at Android Settings and offers no turn-on button', () {
    final notice = bluetoothNoticeFor(BleAdapterState.unauthorized)!;
    expect(notice.offersTurnOn, isFalse);
    expect(notice.body, contains('Nearby devices'));
    expect(notice.body, contains('Android Settings'));
    // A turn-on request would not grant a runtime permission, so the copy must
    // not tell the user to switch Bluetooth on.
    expect(notice.title.toLowerCase(), isNot(contains('bluetooth is off')));
  });

  test('unsupported says the device has no Bluetooth LE', () {
    final notice = bluetoothNoticeFor(BleAdapterState.unsupported)!;
    expect(notice.offersTurnOn, isFalse);
    expect(notice.body, contains('Bluetooth LE'));
  });

  test('only the off state offers an action', () {
    for (final state in BleAdapterState.values) {
      final notice = bluetoothNoticeFor(state);
      expect(
        notice?.offersTurnOn ?? false,
        state == BleAdapterState.off,
        reason: state.name,
      );
    }
  });

  test('on and unknown show no notice', () {
    expect(bluetoothNoticeFor(BleAdapterState.on), isNull);
    expect(bluetoothNoticeFor(BleAdapterState.unknown), isNull);
  });
}
