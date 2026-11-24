import 'ble_adapter.dart';

/// What the app should tell the user about the Bluetooth adapter, and whether
/// the message offers an action that can actually change the state.
///
/// This exists because "not on" is three different situations with three
/// different remedies, and the banner used to collapse them into one: a
/// denied Nearby-devices permission rendered as "Bluetooth is off" with a
/// TURN ON button that cannot grant a permission. The mapping is pure so each
/// state can be tested without a radio.
class BluetoothNotice {
  /// One-line statement of the state.
  final String title;

  /// What the user can do about it.
  final String body;

  /// Whether a "turn on" action makes sense. Only true when the adapter is
  /// switched off: the OS dialog can switch it on, but it cannot grant a
  /// runtime permission and it cannot add Bluetooth LE hardware.
  final bool offersTurnOn;

  const BluetoothNotice({
    required this.title,
    required this.body,
    required this.offersTurnOn,
  });
}

/// The notice for [state], or null when there is nothing to report.
///
/// `unknown` is deliberately silent: it means the platform has not answered
/// yet, so showing a notice would flash a warning during normal startup.
BluetoothNotice? bluetoothNoticeFor(BleAdapterState state) {
  switch (state) {
    case BleAdapterState.off:
      return const BluetoothNotice(
        title: 'Bluetooth is off',
        body: 'Turn it on to scan for BMS devices.',
        offersTurnOn: true,
      );
    case BleAdapterState.unauthorized:
      return const BluetoothNotice(
        title: 'Nearby devices permission is off',
        body: 'Allow Nearby devices for this app in Android Settings, then return and scan again.',
        offersTurnOn: false,
      );
    case BleAdapterState.unsupported:
      return const BluetoothNotice(
        title: 'Bluetooth LE is not supported',
        body: 'This device does not support Bluetooth LE, so it cannot connect to a BMS.',
        offersTurnOn: false,
      );
    case BleAdapterState.on:
    case BleAdapterState.unknown:
      return null;
  }
}
