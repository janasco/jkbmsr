import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/models/device.dart';

// Only the fields under test are asserted; Device.fromJson defaults the rest.
Device _device(Map<String, dynamic> extra) {
  return Device.fromJson(<String, dynamic>{
    'id': 'dev-1',
    'name': 'Main Bank',
    'status': 'online',
    'lastSeen': 'Just now',
    ...extra,
  });
}

void main() {
  test('defaults to the Free-tier plan when the API omits the fields', () {
    final d = _device(const {});
    expect(d.subscriptionTierId, 'free');
    expect(d.subscriptionTierLabel, 'Free');
    expect(d.subscriptionTierIntervalSeconds, 3600);
    expect(d.subscriptionStatus, 'inactive');
    expect(d.subscriptionCurrentPeriodEnd, isNull);
  });

  test('parses the subscription fields when present', () {
    final d = _device(const {
      'subscriptionTierId': 'entry',
      'subscriptionTierLabel': 'Entry',
      'subscriptionTierIntervalSeconds': 300,
      'subscriptionStatus': 'active',
      'subscriptionCurrentPeriodEnd': '2026-11-01T00:00:00Z',
    });
    expect(d.subscriptionTierId, 'entry');
    expect(d.subscriptionTierLabel, 'Entry');
    expect(d.subscriptionTierIntervalSeconds, 300);
    expect(d.subscriptionStatus, 'active');
    expect(d.subscriptionCurrentPeriodEnd, '2026-11-01T00:00:00Z');
  });

  test('tolerates a tier interval sent as a JSON double', () {
    final d = _device(const {'subscriptionTierIntervalSeconds': 300.0});
    expect(d.subscriptionTierIntervalSeconds, 300);
  });

  test('round-trips the subscription fields through toJson', () {
    final d = _device(const {
      'subscriptionTierId': 'standard',
      'subscriptionTierLabel': 'Standard',
      'subscriptionTierIntervalSeconds': 60,
      'subscriptionStatus': 'active',
      'subscriptionCurrentPeriodEnd': '2026-11-01T00:00:00Z',
    });
    final json = d.toJson();
    expect(json['subscriptionTierId'], 'standard');
    expect(json['subscriptionTierLabel'], 'Standard');
    expect(json['subscriptionTierIntervalSeconds'], 60);
    expect(json['subscriptionStatus'], 'active');
    expect(json['subscriptionCurrentPeriodEnd'], '2026-11-01T00:00:00Z');
  });

  test('DeviceSubscription.fromConfig parses a getDeviceConfig map', () {
    final sub = DeviceSubscription.fromConfig(const {
      'subscriptionTierId': 'lite',
      'subscriptionTierLabel': 'Lite',
      'subscriptionTierIntervalSeconds': 900,
      'subscriptionStatus': 'active',
      'subscriptionCurrentPeriodEnd': '2026-11-01T00:00:00Z',
    });
    expect(sub.tierId, 'lite');
    expect(sub.tierLabel, 'Lite');
    expect(sub.intervalSeconds, 900);
    expect(sub.status, 'active');
    expect(sub.currentPeriodEnd, '2026-11-01T00:00:00Z');
  });

  test('DeviceSubscription.fromConfig defaults a bare config map', () {
    final sub = DeviceSubscription.fromConfig(const {'otaEnabled': true});
    expect(sub.tierId, 'free');
    expect(sub.tierLabel, 'Free');
    expect(sub.intervalSeconds, 3600);
    expect(sub.status, 'inactive');
    expect(sub.currentPeriodEnd, isNull);
  });

  test('DeviceSubscription.fromDevice carries the device fields', () {
    final sub = DeviceSubscription.fromDevice(_device(const {
      'subscriptionTierId': 'fast',
      'subscriptionTierLabel': 'Fast',
      'subscriptionTierIntervalSeconds': 30,
      'subscriptionStatus': 'active',
    }));
    expect(sub.tierId, 'fast');
    expect(sub.tierLabel, 'Fast');
    expect(sub.intervalSeconds, 30);
    expect(sub.status, 'active');
  });
}
