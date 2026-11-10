/// What asking the platform to enable Bluetooth resulted in.
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

/// Classifies the outcome of an enable-Bluetooth request.
///
/// The old package reported a dismissed dialog as a `userRejected` error code,
/// so a decline could be told apart from a failure. universal_ble answers with a
/// bool instead and does not separate the two: `false` is the only signal that
/// the adapter did not come on, and a thrown error is the only signal that the
/// request itself failed. A `false` is therefore treated as a decline — silence
/// is the right answer when someone says no — and anything thrown is a failure
/// that gets an explanation.
///
/// Unclassified is never harmless: a non-platform error still maps to
/// [BluetoothOnFailure.unavailable] rather than being swallowed.
BluetoothOnFailure? classifyBluetoothOnOutcome({required bool enabled, Object? error}) {
  if (error != null) return BluetoothOnFailure.unavailable;
  return enabled ? null : BluetoothOnFailure.declined;
}
