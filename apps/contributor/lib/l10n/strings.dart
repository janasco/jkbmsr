/// User-facing copy for the Phase 4 consent and review flows, in one place.
///
/// **Localisation decision.** `apps/ble` and `apps/pro` ship **no** Flutter
/// localisation mechanism: there is no `flutter_localizations`, no `intl`, no
/// `.arb` file and no generated `AppLocalizations` in either app or in
/// `packages/`; their user-facing strings are inline English literals. Rather
/// than introduce a localisation framework that the shipping apps do not use
/// (and which would then need a real translator workflow), Contributor follows
/// the family and keeps the copy here — one file — so a future localisation
/// pass has a single source to extract from. This file is the answer to "where
/// is the copy", not an l10n framework.
library;

/// Copy for the first-run consent screen (plan §3.1).
abstract final class ConsentStrings {
  static const String title = 'Before you contribute';

  static const String intro =
      'JK BMS Contributor is anonymous and opt-in. Nothing is captured or sent '
      'until you switch it on below.';

  static const String collectedTitle = 'What we collect';
  static const List<String> collected = [
    "Real JK02 frames from your JK-BMS — the battery's own bytes",
    'Device model, hardware and firmware version strings',
    'Decoded telemetry samples: voltage, current, temperature, state of charge, '
        'cell voltages and alarm flags',
    'Optionally, a settings snapshot and the on-board logbook',
    'Your app build and phone details (platform and OS version — never the '
        'phone model)',
  ];

  static const String notCollectedTitle = 'What we never collect';
  static const List<String> notCollected = [
    'No account, no email, no name — you are never identified',
    'No location, contacts, files, phone state or advertising ID',
    'The battery serial number (withheld by default; you can opt in per '
        'contribution)',
    'The full Bluetooth/MAC address — only the vendor prefix is kept',
    "Day-level device dates — the manufacturing date is kept only as a year "
        'and month',
  ];

  static const String detailsTitle = 'The details, honestly';
  static const List<String> details = [
    'Each contribution carries a UTC timestamp for when it was captured, so '
        'contributions can be ordered. It is not linked to you.',
    'The server sees the connecting IP address in order to answer the request. '
        'It is not stored against your contribution; at most a coarse country '
        'code is kept, and only if that option is left on.',
    'You see the exact payload before anything is sent, and you can switch off '
        'any field.',
  ];

  static const String optInLabel = 'I agree to contribute my device data';

  static const String accept = 'I understand — contribute';
  static const String decline = 'Not now';

  static const String declineNote =
      'The app still works. You can turn contributing on any time from Home.';
}

/// Copy for the review-before-submit screen (plan §3.4).
abstract final class ReviewStrings {
  static const String title = 'Review before you contribute';

  static const String intro =
      'This is the exact data that would be sent. Uncheck anything you do not '
      'want to share.';

  static const String serialLabel = 'Serial number';
  static const String serialDescription =
      'Off by default. Turn this on only if you want to share it.';

  static const String omittedTitle = 'These fields will be omitted';

  static const String submit = 'Submit contribution';
  static const String discard = 'Discard';

  /// The Phase 5 seam: nothing is submitted from Phase 4.
  static const String submitSeam =
      'Submitting and exporting arrive in the next phase.';
}
