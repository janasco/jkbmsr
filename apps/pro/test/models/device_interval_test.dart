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
  test('parses the telemetry cadence fields when present', () {
    final d = _device(const {
      'expectedIntervalSeconds': 900,
      'secondsSinceLastTelemetry': 342,
      'secondsUntilNextExpectedCheckIn': 558,
    });
    expect(d.expectedIntervalSeconds, 900);
    expect(d.secondsSinceLastTelemetry, 342);
    expect(d.secondsUntilNextExpectedCheckIn, 558);
  });

  test('leaves the cadence fields null when the API omits them', () {
    final d = _device(const {});
    expect(d.expectedIntervalSeconds, isNull);
    expect(d.secondsSinceLastTelemetry, isNull);
    expect(d.secondsUntilNextExpectedCheckIn, isNull);
  });

  test('tolerates a cadence value sent as a JSON double', () {
    final d = _device(const {'secondsUntilNextExpectedCheckIn': 42.0});
    expect(d.secondsUntilNextExpectedCheckIn, 42);
  });

  test('round-trips the cadence fields through toJson', () {
    final d = _device(const {'secondsUntilNextExpectedCheckIn': 558, 'expectedIntervalSeconds': 900});
    final json = d.toJson();
    expect(json['secondsUntilNextExpectedCheckIn'], 558);
    expect(json['expectedIntervalSeconds'], 900);
  });
}
