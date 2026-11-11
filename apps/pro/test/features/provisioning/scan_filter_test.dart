// Which scan results count as ours.
//
// The failure this pins: requiring both the service UUID and the name made the
// list empty whenever the name was truncated out of a 31-byte advertisement, with
// no error to read anywhere.

import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/provisioning/ble_gateway_scan_source.dart';
import 'package:jkbmsr_pro/features/provisioning/provisioning_protocol.dart';

void main() {
  const prefix = ProvisioningProtocol.namePrefix;

  test('a device advertising our service is a candidate even with no name', () {
    expect(isProvisioningCandidate([ProvisioningProtocol.service], ''), isTrue);
  });

  test('a device with the name but no service list is a candidate', () {
    // Some platforms do not expose the advertised service list on every packet.
    expect(isProvisioningCandidate(const [], '${prefix}4A21'), isTrue);
  });

  test('someone else\'s device is not', () {
    expect(isProvisioningCandidate(const ['180d'], 'HRM-1234'), isFalse);
    expect(isProvisioningCandidate(const [], ''), isFalse);
  });

  test('the UUID comparison is case insensitive', () {
    expect(
      isProvisioningCandidate([ProvisioningProtocol.service.toUpperCase()], ''),
      isTrue,
    );
  });
}
