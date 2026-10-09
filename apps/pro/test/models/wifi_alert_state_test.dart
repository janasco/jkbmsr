// Model coverage for the offline-alert episode's owner controls. The ack/mute
// fields are parsed defensively: an API build that predates them omits the
// keys, and absence must read as "not muted / not acknowledged" rather than a
// reason to hide the controls.
import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/models/device_wifi_target.dart';

void main() {
  group('WifiAlertState', () {
    test('parses muted and acknowledgedAt when present', () {
      final alert = WifiAlertState.fromJson({
        'active': true,
        'lastSentAt': '2026-10-09 12:35:00',
        'count': 3,
        'muted': true,
        'acknowledgedAt': '2026-10-09 12:40:00',
      });

      expect(alert.active, isTrue);
      expect(alert.count, 3);
      expect(alert.muted, isTrue);
      expect(alert.acknowledgedAt, '2026-10-09 12:40:00');
    });

    test('absent muted/acknowledgedAt default to not muted / not acknowledged', () {
      final alert = WifiAlertState.fromJson({
        'active': false,
        'lastSentAt': null,
        'count': 0,
      });

      expect(alert.muted, isFalse);
      expect(alert.acknowledgedAt, isNull);
    });

    test('non-bool muted is treated as false rather than truthy', () {
      final alert = WifiAlertState.fromJson({
        'active': true,
        'count': 1,
        'muted': 'yes',
        'acknowledgedAt': 12345,
      });

      expect(alert.muted, isFalse);
      expect(alert.acknowledgedAt, isNull);
    });

    test('copyWith replaces muted and sets acknowledgedAt', () {
      final alert = WifiAlertState(active: true, count: 2);
      final updated = alert.copyWith(muted: true, acknowledgedAt: 'now');

      expect(updated.muted, isTrue);
      expect(updated.acknowledgedAt, 'now');
      // Untouched fields survive the copy.
      expect(updated.active, isTrue);
      expect(updated.count, 2);
      // The original is unchanged.
      expect(alert.muted, isFalse);
      expect(alert.acknowledgedAt, isNull);
    });

    test('copyWith can clear acknowledgedAt explicitly', () {
      final alert = WifiAlertState(active: true, count: 2, acknowledgedAt: 'now');
      final cleared = alert.copyWith(clearAcknowledgedAt: true);

      expect(cleared.acknowledgedAt, isNull);
      expect(cleared.active, isTrue);
      expect(cleared.count, 2);
    });
  });

  group('DeviceWifiTargetState', () {
    test('absent alert block yields a safe non-muted, non-acknowledged state', () {
      final state = DeviceWifiTargetState.fromJson({
        'target': null,
        'reported': null,
      });

      expect(state.alert.active, isFalse);
      expect(state.alert.muted, isFalse);
      expect(state.alert.acknowledgedAt, isNull);
    });
  });
}
