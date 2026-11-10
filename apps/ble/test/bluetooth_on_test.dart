import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/bluetooth_on.dart';

// Turning Bluetooth on from the app.
//
// The old package reported a dismissed dialog as a `userRejected` error code;
// universal_ble answers with a bool, so the distinction now comes from the bool
// itself. These tests pin the consequence: someone who taps "no" must not be
// told to go into their phone settings, and a request that threw must never be
// treated as a decline.

void main() {
  group('classifyBluetoothOnOutcome', () {
    test('the adapter came on: nothing to report', () {
      expect(classifyBluetoothOnOutcome(enabled: true), isNull);
    });

    test('a dismissed system dialog is a decline, not a fault', () {
      expect(classifyBluetoothOnOutcome(enabled: false), BluetoothOnFailure.declined);
    });

    test('a thrown error is a failure the user needs a next step for', () {
      expect(
        classifyBluetoothOnOutcome(enabled: false, error: StateError('refused intent')),
        BluetoothOnFailure.unavailable,
      );
    });

    test('an error is unavailable even if the call claimed success', () {
      // Defensive: a plugin that throws after answering must not be read as
      // success, and must not be read as a decline either.
      expect(
        classifyBluetoothOnOutcome(enabled: true, error: StateError('late failure')),
        BluetoothOnFailure.unavailable,
      );
    });

    test('the guidance gives a next step and does not leak the raw error', () {
      expect(bluetoothOnUnavailableMessage, contains('settings'));
      expect(
        bluetoothOnUnavailableMessage.toLowerCase(),
        isNot(contains('exception')),
      );
    });
  });
}
