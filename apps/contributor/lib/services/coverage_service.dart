import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'contribution_uploader.dart' show contributionApiBase;

/// The public, aggregate-only corpus summary.
///
/// It is unauthenticated and CORS-open because it carries no
/// per-contribution rows: just how many captures exist and how varied they are.
const String contributionSummaryPath = '/v2/contributions/summary';

/// The part of the corpus summary the home screen shows.
///
/// Only the two counts are read. Everything else the endpoint returns is
/// deliberately ignored, so a shape change in the rest of the document cannot
/// break the one line that is displayed.
class CorpusCoverage {
  const CorpusCoverage({required this.contributions, required this.models});

  final int contributions;
  final int models;
}

/// Reads the corpus summary.
///
/// The [client] is injectable so a widget test can drive the real parsing with
/// a fake transport (`package:http/testing.dart` `MockClient`) instead of
/// reaching the network.
///
/// Failure is not an error state: [fetch] resolves to null for an unreachable
/// server, a non-200 answer, or a document that does not carry two usable
/// counts. The caller shows nothing in that case rather than inventing a
/// figure or leaving a spinner behind.
class CoverageService {
  CoverageService({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ??
            Uri.parse('$contributionApiBase$contributionSummaryPath');

  final http.Client _client;
  final Uri _endpoint;

  /// Bounded so a slow or black-holed request cannot hold a socket for the
  /// life of the app. Nothing waits on this future, so a timeout is invisible.
  static const Duration requestTimeout = Duration(seconds: 6);

  Future<CorpusCoverage?> fetch() async {
    try {
      final response = await _client.get(
        _endpoint,
        headers: const {'Accept': 'application/json'},
      ).timeout(requestTimeout);
      if (response.statusCode != 200) return null;
      return _parse(response.body);
    } on TimeoutException {
      return null;
    } catch (_) {
      // SocketException, ClientException, HandshakeException, ... all mean the
      // same thing here: there is no figure to show.
      return null;
    }
  }

  static CorpusCoverage? _parse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final contributions = decoded['contributions'];
      final models = decoded['models'];
      if (contributions is! int || models is! int) return null;
      if (contributions <= 0 || models <= 0) return null;
      return CorpusCoverage(contributions: contributions, models: models);
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
