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

  test('every failure except a 400 points at the export fallback', () {
    for (final kind in SubmitFailureKind.values) {
      final message = SubmitStrings.failureMessage(SubmitFailure(kind: kind));
      if (kind == SubmitFailureKind.invalid) {
        // A document the server cannot read is exactly the document an export
        // would fail to send later, so the 400 copy must not promise one.
        continue;
      }
      expect(message.toLowerCase(), contains('export'),
          reason: 'kind $kind does not offer the offline fallback');
    }
  });

  test('the 400 copy does not promise an export that would also fail', () {
    final message = SubmitStrings.failureMessage(
      const SubmitFailure(kind: SubmitFailureKind.invalid),
    );
    expect(message.toLowerCase(), isNot(contains('export')));
    expect(message.toLowerCase(), isNot(contains('send it later')));
    expect(message.trim(), isNotEmpty);
  });
}
