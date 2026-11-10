import 'package:universal_ble/universal_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/services/ble_adapter.dart';
import 'package:jkbmsr_ble/services/ble_service.dart';

// The adapter-state boundary.
//
// The app's screens used to subscribe to the BLE package's own enum, which meant
// every one of them named the plugin. This mapper is now the single place that
// knows it, so a plugin swap is a change here and nowhere else - and a mapping
// that silently collapsed two states would put a "turn Bluetooth on" banner in
// front of a user whose adapter is fine, or hide it from one whose adapter is
// off.

void main() {
  test('every plugin state maps to exactly one app state', () {
    expect(mapAdapterState(AvailabilityState.poweredOn), BleAdapterState.on);
    expect(mapAdapterState(AvailabilityState.poweredOff), BleAdapterState.off);
    expect(mapAdapterState(AvailabilityState.unauthorized), BleAdapterState.unauthorized);
    expect(mapAdapterState(AvailabilityState.unsupported), BleAdapterState.unsupported);
  });

  test('the transitional states stay unknown rather than being guessed', () {
    // Transitional and resetting states are not "on": showing the connected UI
    // before the adapter is usable would make the app look broken for the second
    // it takes.
    expect(mapAdapterState(AvailabilityState.resetting), BleAdapterState.unknown);
    expect(mapAdapterState(AvailabilityState.resetting), BleAdapterState.unknown);
    expect(mapAdapterState(AvailabilityState.unknown), BleAdapterState.unknown);
  });

  test('isOn is true only for the ready state', () {
    for (final state in BleAdapterState.values) {
      expect(state.isOn, state == BleAdapterState.on, reason: state.name);
    }
  });
}
