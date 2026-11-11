// The provisioning wire protocol, where the mistakes would be invisible.
//
// A wrong offset does not throw: it writes a plausible packet and the gateway
// stores a WiFi password with one byte of the SSID gone. These tests exist for
// that class of defect.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:jkbmsr_pro/features/provisioning/provisioning_protocol.dart';

Uint8List _payload() => ProvisioningProtocol.encodePayload(
      ssid: 'HouseWiFi',
      password: 'correct horse battery',
      timeZone: 'PST-8',
      claimToken: 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.signature',
    );

void main() {
  test('the payload JSON carries exactly the four contract keys', () {
    final decoded = jsonDecode(utf8.decode(_payload())) as Map<String, dynamic>;
    expect(decoded.keys.toSet(), {'ssid', 'password', 'timeZone', 'claimToken'});
    expect(decoded['ssid'], 'HouseWiFi');
    expect(decoded['timeZone'], 'PST-8');
  });

  test('chunks carry their own offset and reassemble byte for byte', () {
    final payload = _payload();
    final chunks = ProvisioningProtocol.chunks(payload, size: 8);

    expect(chunks.length, greaterThan(1));
    final assembled = Uint8List(payload.length);
    final covered = List<bool>.filled(payload.length, false);

    for (final chunk in chunks) {
      final offset = chunk[0] | (chunk[1] << 8);
      final body = chunk.sublist(2);
      assembled.setRange(offset, offset + body.length, body);
      for (var i = 0; i < body.length; i++) {
        expect(covered[offset + i], isFalse, reason: 'overlap at ${offset + i}');
        covered[offset + i] = true;
      }
    }

    expect(assembled, payload);
    // Every byte covered, or the firmware would reject a gap at commit.
    expect(covered.every((c) => c), isTrue);
  });

  test('a payload larger than one chunk starts the second at the right offset', () {
    final payload = _payload();
    // A small chunk size so the second write is exercised; the offset comes
    // from the chunk size, not from the device's negotiated MTU.
    const size = 64;
    final chunks = ProvisioningProtocol.chunks(payload, size: size);
    expect(chunks.length, greaterThan(1));
    final second = chunks[1];
    final offset = second[0] | (second[1] << 8);
    expect(offset, size);
  });

  test('the device buffer limit is enforced here, not discovered there', () {
    final tooBig = Uint8List(ProvisioningProtocol.maxPayloadBytes + 1);
    expect(
      () => ProvisioningProtocol.chunks(tooBig),
      throwsA(isA<ArgumentError>()),
    );
    expect(() => ProvisioningProtocol.chunks(Uint8List(0)),
        throwsA(isA<ArgumentError>()));
  });

  test('every offered time zone is one the firmware will accept', () {
    for (final zone in [
      'UTC0',
      'PST-8',
      'JST-9',
      'IST-5:30',
      'CET-1CEST,M3.5.0,M10.5.0/3',
      'GMT0BST,M3.5.0/1,M10.5.0',
      'EST5EDT,M3.2.0,M11.1.0',
      'PST8PDT,M3.2.0,M11.1.0',
      'AEST-10AEDT,M10.1.0,M4.1.0/3',
    ]) {
      expect(ProvisioningProtocol.isValidTimeZone(zone), isTrue, reason: zone);
    }
    // The exact mistake a person makes, and the one libc would swallow.
    expect(ProvisioningProtocol.isValidTimeZone('Asia/Manila'), isFalse);
    expect(ProvisioningProtocol.isValidTimeZone(''), isFalse);
    expect(ProvisioningProtocol.isValidTimeZone('Europe/Berlin'), isFalse);
  });

  test('a claim token is checked for shape, and a wrong string fails here', () {
    expect(
      ProvisioningProtocol.isPlausibleClaimToken('aaa.bbb.ccc'),
      isTrue,
    );
    for (final bad in ['', 'not-a-jwt', 'aa..cc', 'aa.bb', 'aa.bb.cc.dd']) {
      expect(ProvisioningProtocol.isPlausibleClaimToken(bad), isFalse,
          reason: bad);
    }
  });

  test('the setup code is six digits and nothing else', () {
    expect(ProvisioningProtocol.isValidSetupCode('418302'), isTrue);
    for (final bad in ['41830', '4183021', '41830a', '', ' 418302']) {
      expect(ProvisioningProtocol.isValidSetupCode(bad), isFalse, reason: bad);
    }
  });

  test('an unknown status is never read as success', () {
    expect(ProvisioningProtocol.parseStatus('running'), ProvisioningStatus.done);
    expect(ProvisioningProtocol.parseStatus('applying'),
        ProvisioningStatus.applying);
    expect(ProvisioningProtocol.parseStatus('failed:storage'),
        ProvisioningStatus.failed);
    // 'running ' is not in this list on purpose: trailing whitespace is
    // trimmed, and the next test pins that.
    for (final odd in ['', 'OK', 'done', '🎉']) {
      final status = ProvisioningProtocol.parseStatus(odd);
      expect(status, isNot(ProvisioningStatus.done), reason: odd);
    }
  });

  test('trailing whitespace on a known state is tolerated, but not invented', () {
    expect(ProvisioningProtocol.parseStatus(' applying\n'),
        ProvisioningStatus.applying);
    expect(ProvisioningProtocol.parseStatus('applying extra'),
        ProvisioningStatus.unknown);
  });
}
