import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// What asking the platform to enable Bluetooth resulted in, when it did not
/// end with the adapter on.
enum BluetoothOnFailure {
  /// The user dismissed the system dialog. That is a choice, not a fault, so
  /// the banner stays and nothing is said.
  declined,

  /// The request could not be made or completed — a refused intent (the
  /// Android 13+ companion-device policy path), a missing permission, or a
  /// timeout. The user needs a next step, not silence.
  unavailable,
}

/// The sentence shown when Bluetooth could not be turned on from the app.
const String bluetoothOnUnavailableMessage =
    "Couldn't turn Bluetooth on from the app. Open your phone's settings, "
    'turn Bluetooth on, then come back.';

/// Classifies a `FlutterBluePlus.turnOn()` failure.
///
/// `turnOn()` throws `FlutterBluePlusException` with code `userRejected` when
/// the user dismisses the system dialog, and with a timeout or a platform error
/// when it could not be completed. The two need different handling: telling
/// someone who just tapped "no" to go into their phone settings is noise, and
/// saying nothing when the request was refused is a button that reads as
/// broken.
///
/// A non-`FlutterBluePlusException` — a platform-channel error on a host with
/// no Bluetooth, say — is [BluetoothOnFailure.unavailable]. Unclassified is not
/// the same as harmless.
BluetoothOnFailure classifyBluetoothOnFailure(Object error) {
  if (error is FlutterBluePlusException &&
      error.code == FbpErrorCode.userRejected.index) {
    return BluetoothOnFailure.declined;
  }
  return BluetoothOnFailure.unavailable;
}
