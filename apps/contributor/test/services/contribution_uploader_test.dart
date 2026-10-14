import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_contributor/services/contribution_uploader.dart';

/// A small, valid payload body. The uploader treats the payload as opaque
/// bytes, so the exact document does not matter here — only that the same
/// bytes reach the wire.
const _payload = '{"schemaVersion":"1","contributionId":"c_abc"}';

/// Counts how many requests a MockClient actually served, so "no auto-retry"
/// is measured rather than assumed.
class _Counter {
  int value = 0;
  void reset() => value = 0;
}

final _callCounter = _Counter();

void main() {
  setUp(_callCounter.reset);

  ContributionUploader uploader(
    int status,
    String body, {
    Map<String, String> headers = const {},
    void Function(http.Request request)? onRequest,
  }) {
    return ContributionUploader(
      client: MockClient((request) async {
        _callCounter.value++;
        onRequest?.call(request);
        return http.Response(body, status, headers: headers);
      }),
    );
  }

  test('a 201 returns the server receipt id and timestamp', () async {
    final u = uploader(
      201,
      jsonEncode({'id': 'c_01926f6a', 'receivedAt': '2026-10-14T09:20:00.000Z'}),
    );

    final result = await u.submit(_payload);

    expect(result.isSuccess, isTrue);
    expect(result.requireReceipt.id, 'c_01926f6a');
    expect(result.requireReceipt.receivedAt, DateTime.utc(2026, 10, 14, 9, 20));
  });

  test('the request is an anonymous JSON POST to the v2 endpoint', () async {
    http.Request? seen;
    final u = uploader(201, '{"id":"c_x"}', onRequest: (r) => seen = r);

    await u.submit(_payload);

    expect(seen, isNotNull);
    expect(seen!.method, 'POST');
    expect(seen!.url.toString(),
        'https://api.jkbmsr.com/v2/contributions');
    expect(seen!.headers['Content-Type'], 'application/json');
    expect(seen!.body, _payload);
    // Anonymous: no authorization / token header of any kind.
    expect(seen!.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains('authorization')));
  });

  test('400 -> invalid', () async {
    final result = await uploader(400, '{"error":"bad schema"}').submit(_payload);
    expect(result.requireFailure.kind, SubmitFailureKind.invalid);
    expect(result.requireFailure.statusCode, 400);
  });

  test('413 -> tooLarge', () async {
    final result = await uploader(413, '{}').submit(_payload);
    expect(result.requireFailure.kind, SubmitFailureKind.tooLarge);
  });

  test('415 -> unsupportedMediaType', () async {
    final result = await uploader(415, '{}').submit(_payload);
    expect(result.requireFailure.kind, SubmitFailureKind.unsupportedMediaType);
  });

  test('429 -> rateLimited, with Retry-After parsed, and no auto-retry',
      () async {
    final u = uploader(429, '{"error":"slow down"}',
        headers: {'retry-after': '120'});

    final result = await u.submit(_payload);

    final failure = result.requireFailure;
    expect(failure.kind, SubmitFailureKind.rateLimited);
    expect(failure.retryAfter, const Duration(seconds: 120));
    // The limiter was hit exactly once: this client never retries on its own.
    expect(_callCounter.value, 1);
  });

  test('500 -> server', () async {
    final result = await uploader(500, '{}').submit(_payload);
    expect(result.requireFailure.kind, SubmitFailureKind.server);
  });

  test('any other status -> unexpected, with the code kept', () async {
    final result = await uploader(418, '{}').submit(_payload);
    expect(result.requireFailure.kind, SubmitFailureKind.unexpected);
    expect(result.requireFailure.statusCode, 418);
  });

  test('a transport failure -> offline', () async {
    final u = ContributionUploader(
      client: MockClient((_) async => throw http.ClientException('no route')),
    );

    final result = await u.submit(_payload);

    expect(result.requireFailure.kind, SubmitFailureKind.offline);
    expect(_callCounter.value, 0);
  });

  test('an oversized payload is refused before any request is sent', () async {
    var called = false;
    final u = ContributionUploader(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 201);
      }),
    );
    // One byte over the 256 KB cap.
    final oversized = 'x' * (256 * 1024 + 1);

    final result = await u.submit(oversized);

    expect(result.requireFailure.kind, SubmitFailureKind.tooLarge);
    expect(called, isFalse);
  });

  test('a 201 with an unreadable body still reports success', () async {
    final result = await uploader(201, 'not json').submit(_payload);
    expect(result.isSuccess, isTrue);
    expect(result.requireReceipt.id, '(unconfirmed)');
    expect(result.requireReceipt.receivedAt, isNull);
  });
}
