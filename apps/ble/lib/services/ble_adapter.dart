/// The Bluetooth adapter states this app reacts to.
///
/// Deliberately our own enum rather than the BLE package's. The app's public
/// surface used to expose `Stream<BluetoothAdapterState>` straight from
/// flutter_blue_plus, which meant every screen and every test knew the plugin by
/// name. Migrating the radio layer (2026-11-10, to universal_ble) is a change of
/// *plugin*, not of *product behaviour*, and the UI should only ever have cared
/// about these five cases — so the plugin type stops at the service boundary and
/// only the mapper below changes when the implementation does.
enum BleAdapterState {
  /// The platform has not answered yet, or is between states.
  unknown,

  /// The adapter is switched off. Expected and actionable, not a failure.
  off,

  /// Ready to scan and connect.
  on,

  /// The OS refused access to Bluetooth (permission denied / restricted).
  unauthorized,

  /// This device has no Bluetooth LE support at all.
  unsupported,
}

extension BleAdapterStateX on BleAdapterState {
  bool get isOn => this == BleAdapterState.on;
}
