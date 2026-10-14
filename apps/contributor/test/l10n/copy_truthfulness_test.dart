import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/l10n/strings.dart';
import 'package:jkbmsr_contributor/models/contribution_selection.dart';

import '../support/jk02_fixtures.dart';

/// Guards the consent/review copy against promising a control the app does not
/// provide.
///
/// The copy is the app's entire trust story, so a sentence that implies an
/// option the client never offers is a real defect: the backend stores a coarse
/// country only when the payload sets `storeCountry: true`, and this client
/// never sets it, so no country is ever kept and the review screen has no
/// toggle for it. The fix is to say nothing about a country; these tests fail
/// if that promise is ever re-added without the field and its control.
void main() {
  /// Every user-facing consent + review string, so a claim cannot hide in one
  /// sentence while the test only reads another.
  final consentAndReviewCopy = <String>[
    ConsentStrings.title,
    ConsentStrings.intro,
    ...ConsentStrings.collected,
    ...ConsentStrings.notCollected,
    ConsentStrings.detailsTitle,
    ...ConsentStrings.details,
    ConsentStrings.optInLabel,
    ConsentStrings.accept,
    ConsentStrings.decline,
    ConsentStrings.declineNote,
    ReviewStrings.title,
    ReviewStrings.intro,
    ReviewStrings.serialLabel,
    ReviewStrings.serialDescription,
    ReviewStrings.omittedTitle,
    ReviewStrings.submit,
    ReviewStrings.discard,
  ];

  test('the consent and review copy never promise a country opt-in', () {
    for (final sentence in consentAndReviewCopy) {
      expect(
        sentence.toLowerCase(),
        isNot(contains('country')),
        reason: 'this sentence promises a country control the app does not '
            'offer; the client never sets storeCountry and there is no toggle',
      );
    }
  });

  test('the honest IP transport note is still present', () {
    // Removing the country clause must not delete the honest transport note;
    // the server does see the connecting IP to answer the request.
    final joined = ConsentStrings.details.join(' ').toLowerCase();
    expect(joined, contains('ip address'));
    expect(joined, contains('not stored'));
  });

  test('the copy makes no "you can switch off any field" over-claim', () {
    // The envelope (contributionId, capturedAt, consent, redaction, sizeBytes)
    // is always sent; only the listed fields are controllable.
    for (final sentence in consentAndReviewCopy) {
      expect(
        sentence.toLowerCase(),
        isNot(contains('any field')),
        reason: 'not every field is switchable, so "any field" over-claims',
      );
    }
  });

  test('the reviewed payload carries no country and no IP field', () {
    final json = jsonDecode(
      sampleContribution().encode(selection: ContributionSelection.defaults()),
    );
    final keys = _allKeys(json);
    expect(keys, isNot(contains('country')));
    expect(keys, isNot(contains('storeCountry')));
    expect(
      keys.where((k) => k.toLowerCase().contains('ip')),
      isEmpty,
      reason: 'the payload the user reviews must carry no IP-derived field',
    );
  });
}

/// Every map key anywhere in [node], so a nested field cannot hide from the
/// top-level assertion.
Set<String> _allKeys(Object? node) {
  final keys = <String>{};
  void walk(Object? n) {
    if (n is Map) {
      n.forEach((k, v) {
        keys.add(k.toString());
        walk(v);
      });
    } else if (n is List) {
      for (final e in n) {
        walk(e);
      }
    }
  }

  walk(node);
  return keys;
}
