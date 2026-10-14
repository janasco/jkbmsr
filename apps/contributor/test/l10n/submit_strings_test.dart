import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/services/contribution_uploader.dart';

/// Every failure kind maps to a distinct, non-empty sentence, and the honest
/// details (the HTTP code, the `Retry-After`) reach the user rather than being
/// smoothed over.
void main() {
  test('every failure kind produces a distinct message', () {
    final messages = <String>{};
    for (final kind in SubmitFailureKind.values) {
      final message = SubmitStrings.failureMessage(SubmitFailure(kind: kind));
      expect(message.trim(), isNotEmpty, reason: 'kind $kind had no copy');
      messages.add(message);
    }
    expect(messages.length, SubmitFailureKind.values.length,
        reason: 'two kinds share a message, so the reason is not specific');
  });

  test('rate limited surfaces the Retry-After it was given', () {
    final message = SubmitStrings.failureMessage(
      const SubmitFailure(
        kind: SubmitFailureKind.rateLimited,
        retryAfter: Duration(seconds: 120),
      ),
    );
    expect(message, contains('2 minutes'));
  });

  test('rate limited under a minute reads in seconds, never "0 minutes"', () {
    final message = SubmitStrings.failureMessage(
      const SubmitFailure(
        kind: SubmitFailureKind.rateLimited,
        retryAfter: Duration(seconds: 45),
      ),
    );
    expect(message, contains('45 seconds'));
    expect(message, isNot(contains('0 minute')));
  });

  test('an unexpected status names the HTTP code', () {
    final message = SubmitStrings.failureMessage(
      const SubmitFailure(kind: SubmitFailureKind.unexpected, statusCode: 418),
    );
    expect(message, contains('418'));
  });

  test('every failure message points at the export fallback', () {
    for (final kind in SubmitFailureKind.values) {
      final message = SubmitStrings.failureMessage(SubmitFailure(kind: kind));
      expect(message.toLowerCase(), contains('export'),
          reason: 'kind $kind does not offer the offline fallback');
    }
  });
}
