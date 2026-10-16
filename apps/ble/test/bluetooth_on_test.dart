import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/bluetooth_on.dart';

void main() {
  group('classifyBluetoothOnFailure', () {
    test('a dismissed system dialog is a decline, not a fault', () {
      final error = FlutterBluePlusException(
        ErrorPlatform.fbp,
        'turnOn',
        FbpErrorCode.userRejected.index,
        'user rejected',
      );
      expect(classifyBluetoothOnFailure(error), BluetoothOnFailure.declined);
    });

    test('a timeout is a failure the user needs a next step for', () {
      final error = FlutterBluePlusException(
        ErrorPlatform.fbp,
        'turnOn',
        FbpErrorCode.timeout.index,
        'turnOn timed out',
      );
      expect(classifyBluetoothOnFailure(error), BluetoothOnFailure.unavailable);
    });

    test('an adapter-is-off refusal is unavailable, not a decline', () {
      final error = FlutterBluePlusException(
        ErrorPlatform.fbp,
        'turnOn',
        FbpErrorCode.adapterIsOff.index,
        'adapter is off',
      );
      expect(classifyBluetoothOnFailure(error), BluetoothOnFailure.unavailable);
    });

    test('a platform-channel error is unavailable', () {
      // The Android 13+ companion-device policy path surfaces as a platform
      // error rather than a FlutterBluePlusException.
      expect(
        classifyBluetoothOnFailure(
          PlatformException(code: 'turnOn', message: 'not permitted'),
        ),
        BluetoothOnFailure.unavailable,
      );
    });

    test('an unclassified error is unavailable, never silently ignored', () {
      expect(
        classifyBluetoothOnFailure(StateError('boom')),
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
