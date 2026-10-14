import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/contribution.dart';

/// The anonymous contribution endpoint (plan §3.5, §5).
///
/// It is deliberately **unauthenticated**: no token, no cookie, no account. The
/// request body is the versioned capture JSON and the server re-enforces the
/// anonymisation rules it already carries. There is exactly one destination;
/// the path is a constant so the contract lives in one place.
const String contributionApiBase = 'https://api.jkbmsr.com';
const String contributionApiPath = '/api/v2/ble/contributions';

/// Why a submit did not succeed. The screen turns one of these into copy from
/// `lib/l10n/strings.dart`; the enum is transport vocabulary, the message is
/// user-facing, and they are kept apart so neither has to be parsed.
enum SubmitFailureKind {
  /// The server could not be reached at all (no connection, DNS, TLS or a
  /// request that timed out). The offline export path is the honest answer.
  offline,

  /// `400` — the server could not read the document (bad/missing
  /// `schemaVersion`, malformed JSON, a failed field check).
  invalid,

  /// `413` — the payload exceeds the server's 256 KB cap. Caught client-side
  /// first, so this is the server's own refusal when it disagrees.
  tooLarge,

  /// `415` — the server refused the content type. Should not happen with this
  /// client's own header, but it is surfaced honestly rather than guessed.
  unsupportedMediaType,

  /// `429` — rate limited, per connecting IP. Never retried automatically; the
  /// user is told and can wait or export instead.
  rateLimited,

  /// `5xx` — the server failed. Retrying immediately is not useful.
  server,

  /// Any other non-201 status.
  unexpected,
}

/// A successful submission. [receivedAt] is the server's timestamp when it
/// parsed it; it is optional because it is informational, not the receipt.
class SubmitReceipt {
  final String id;
  final DateTime? receivedAt;

  const SubmitReceipt({required this.id, this.receivedAt});
}

/// The outcome of a submit: exactly one of [receipt] / [failure] is set.
class SubmitResult {
  final SubmitReceipt? receipt;
  final SubmitFailure? failure;

  const SubmitResult.success(SubmitReceipt this.receipt) : failure = null;
  const SubmitResult.failed(SubmitFailure this.failure) : receipt = null;

  bool get isSuccess => receipt != null;
  SubmitReceipt get requireReceipt => receipt!;
  SubmitFailure get requireFailure => failure!;
}

/// A submit that did not succeed. [statusCode] and [retryAfter] are present
/// only when the server supplied them.
class SubmitFailure {
  final SubmitFailureKind kind;
  final int? statusCode;

  /// Parsed from a `Retry-After` header on a `429`, when present.
  final Duration? retryAfter;

  const SubmitFailure({
    required this.kind,
    this.statusCode,
    this.retryAfter,
  });
}

/// Posts a contribution to the anonymous endpoint.
///
/// The [client] is injectable so a test can drive the real status handling
/// with a fake transport (`package:http/testing.dart` `MockClient`) rather
/// than a mock of this class — the mapping from an HTTP status to a
/// [SubmitFailureKind] is the thing worth testing, so it is exercised for real.
class ContributionUploader {
  ContributionUploader({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _endpoint = endpoint ??
            Uri.parse('$contributionApiBase$contributionApiPath');

  final http.Client _client;
  final Uri _endpoint;

  /// How long a single request may take before it is treated as unreachable.
  /// A contribution is at most 256 KB, so this is generous.
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Submits [payload] (the exact string from [Contribution.encode]).
  ///
  /// It never retries: a failure is returned to the caller so the user can
  /// choose to try again or export. Auto-retrying would turn a `429` into a
  /// longer rate-limit window and would hide a real failure behind a spinner.
  Future<SubmitResult> submit(String payload) async {
    final bytes = utf8.encode(payload);
    // Same cap the server enforces, checked before the network so an oversized
    // document fails fast with the same reason the server would give.
    if (bytes.length > Contribution.maxPayloadBytes) {
      return const SubmitResult.failed(
        SubmitFailure(kind: SubmitFailureKind.tooLarge),
      );
    }

    http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: bytes,
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      return const SubmitResult.failed(
        SubmitFailure(kind: SubmitFailureKind.offline),
      );
    } catch (_) {
      // SocketException, ClientException, HandshakeException, ... — all mean
      // the same thing to the user: the server was not reached.
      return const SubmitResult.failed(
        SubmitFailure(kind: SubmitFailureKind.offline),
      );
    }

    return _interpret(response);
  }

  SubmitResult _interpret(http.Response response) {
    if (response.statusCode == 201) {
      return SubmitResult.success(_parseReceipt(response.body));
    }

    final kind = switch (response.statusCode) {
      400 => SubmitFailureKind.invalid,
      413 => SubmitFailureKind.tooLarge,
      415 => SubmitFailureKind.unsupportedMediaType,
      429 => SubmitFailureKind.rateLimited,
      >= 500 => SubmitFailureKind.server,
      _ => SubmitFailureKind.unexpected,
    };

    return SubmitResult.failed(
      SubmitFailure(
        kind: kind,
        statusCode: response.statusCode,
        retryAfter: kind == SubmitFailureKind.rateLimited
            ? _parseRetryAfter(response.headers['retry-after'])
            : null,
      ),
    );
  }

  /// A `201` body is `{id, receivedAt}`. A body that cannot be read is not
  /// allowed to turn a recorded success into an apparent failure, so the id
  /// falls back to a clearly-unknown marker rather than throwing.
  SubmitReceipt _parseReceipt(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final id = decoded['id'];
        final received = decoded['receivedAt'];
        return SubmitReceipt(
          id: id is String && id.isNotEmpty ? id : '(unconfirmed)',
          receivedAt: received is String ? DateTime.tryParse(received)?.toUtc() : null,
        );
      }
    } catch (_) {
      // fall through
    }
    return const SubmitReceipt(id: '(unconfirmed)');
  }

  /// `Retry-After` is either a number of seconds or an HTTP date. Only the
  /// seconds form is parsed; an unparseable value is simply absent.
  static Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null && seconds >= 0) return Duration(seconds: seconds);
    return null;
  }
}
