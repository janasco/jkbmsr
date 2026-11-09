import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jkbmsr_contributor/services/coverage_service.dart';

CoverageService _respond(int status, String body) => CoverageService(
      client: MockClient((_) async => http.Response(body, status)),
    );

void main() {
  test('a 200 summary yields the two displayed counts', () async {
    final coverage = await _respond(
      200,
      jsonEncode({'contributions': 12, 'models': 9}),
    ).fetch();

    expect(coverage, isNotNull);
    expect(coverage!.contributions, 12);
    expect(coverage.models, 9);
  });

  test('it asks the documented aggregate endpoint for JSON', () async {
    Uri? seen;
    final service = CoverageService(
      client: MockClient((request) async {
        seen = request.url;
        expect(request.method, 'GET');
        expect(request.headers['Accept'], 'application/json');
        return http.Response('{"contributions":1,"models":1}', 200);
      }),
    );

    await service.fetch();

    expect(
      seen.toString(),
      'https://api.jkbmsr.com/v2/contributions/summary',
    );
  });

  test('a non-200 answer yields nothing rather than a figure', () async {
    expect(await _respond(500, '{}').fetch(), isNull);
    expect(await _respond(404, '{}').fetch(), isNull);
  });

  test('an unreadable document yields nothing and does not throw', () async {
    expect(await _respond(200, 'not json').fetch(), isNull);
    expect(await _respond(200, '[]').fetch(), isNull);
    expect(await _respond(200, '{"contributions":12}').fetch(), isNull);
    expect(
      await _respond(200, '{"contributions":"12","models":9}').fetch(),
      isNull,
    );
    expect(
      await _respond(200, '{"contributions":0,"models":0}').fetch(),
      isNull,
    );
  });

  test('a transport failure yields nothing and does not throw', () async {
    final service = CoverageService(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    expect(await service.fetch(), isNull);
  });
}
