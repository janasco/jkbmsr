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

import '../services/ble_transport.dart';
import '../services/contribution_uploader.dart';

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

  /// Deliberately says nothing about a coarse **country** code. The backend
  /// only stores one when the payload sets `storeCountry: true`, and this
  /// client never does, so no country is ever kept and the review screen offers
  /// no control for it. Promising an opt-in the app does not provide would make
  /// the copy untrue — which is the one thing this app cannot afford. Do not
  /// add a country sentence back unless the field and its toggle are wired too.
  static const List<String> details = [
    'Each contribution carries a UTC timestamp for when it was captured, so '
        'contributions can be ordered. It is not linked to you.',
    'The server sees the connecting IP address in order to answer the request. '
        'It is not stored.',
    'You see the exact payload before anything is sent, and you can switch off '
        'each field the review shows.',
  ];

  static const String optInLabel = 'I agree to contribute my device data';

  static const String accept = 'I understand — contribute';
  static const String decline = 'Not now';

  static const String declineNote =
      'The app still works. You can turn contributing on any time from Home.';
}

/// Copy for the scan flow.
///
/// A scan can fail for reasons the user can fix (Bluetooth off, a permission
/// not granted, Location Services off). Those are expected states, not errors,
/// so each maps to a plain, actionable sentence rather than a raw
/// `PlatformException` — the reason is logged separately, never shown as the
/// product. The screen offers "Try again" beside every one of these.
abstract final class ScanStrings {
  /// Turns a [BleScanFailureKind] into the sentence the user sees.
  static String scanFailure(BleScanFailureKind kind) {
    switch (kind) {
      case BleScanFailureKind.bluetoothOff:
        return 'Bluetooth is off. Turn Bluetooth on to scan for your JK-BMS.';
      case BleScanFailureKind.permissionDenied:
        return 'JK BMS Contributor needs Bluetooth permission to scan. Allow it '
            'and try again.';
      case BleScanFailureKind.locationServicesOff:
        return 'Turn on Location Services, then try again — Android needs it to '
            'scan for Bluetooth devices.';
      case BleScanFailureKind.unsupported:
        return 'This device does not support Bluetooth LE, so it cannot scan '
            'for a JK-BMS.';
      case BleScanFailureKind.other:
        return 'Could not start the scan. Please try again.';
    }
  }
}

/// Copy for the review-before-submit screen (plan §3.4).
abstract final class ReviewStrings {
  static const String title = 'Review before you contribute';

  /// "the fields", not "anything": the envelope (`contributionId`,
  /// `capturedAt`, `consent`, `redaction`, `sizeBytes`) is always present, so
  /// only the fields the screen lists are actually controllable.
  static const String intro =
      'This is the exact data that would be sent. Uncheck the fields you do not '
      'want to share.';

  static const String serialLabel = 'Serial number';
  static const String serialDescription =
      'Off by default. Turn this on only if you want to share it.';

  static const String omittedTitle = 'These fields will be omitted';

  static const String submit = 'Submit contribution';
  static const String discard = 'Discard';
}

/// Copy for the submit + offline-export flow (plan §3.5).
///
/// Every user-visible string for a submit lives here, including the mapping
/// from a [SubmitFailureKind] to a sentence, so the wording is in one place and
/// can be asserted directly in a test without mounting a widget.
abstract final class SubmitStrings {
  static const String submitting = 'Sending your contribution…';
  static const String exportButton = 'Export file instead';
  static const String exporting = 'Preparing the file…';

  // Success ----------------------------------------------------------------
  static const String successTitle = 'Contribution received';
  static const String successBody =
      'Thank you. It is stored anonymously — no account was created and '
      'nothing identifies you.';
  static const String successReceiptLabel = 'Receipt id';

  /// The returned `id`, shown verbatim. It is the server's own receipt and the
  /// only proof of the submission.
  static String successReceipt(String id) => id;

  static const String done = 'Done';

  // Failure ----------------------------------------------------------------
  /// Offered beside every failure so a contribution is never lost.
  static const String exportHint =
      'Nothing is lost — you can save the file and send it later.';

  static const String tryAgain = 'Try again';

  /// Turns a [SubmitFailure] into the sentence the user sees. The status code
  /// and any `Retry-After` are reported honestly rather than smoothed over.
  static String failureMessage(SubmitFailure failure) {
    switch (failure.kind) {
      case SubmitFailureKind.offline:
        return 'Could not reach the server. Check your connection, or export '
            'the file and share it later.';
      case SubmitFailureKind.invalid:
        return 'The server could not read this contribution. Export the file '
            'and it can still be sent later.';
      case SubmitFailureKind.tooLarge:
        return 'This contribution is larger than the 256 KB the server '
            'accepts. Export the file instead.';
      case SubmitFailureKind.unsupportedMediaType:
        return 'The server refused the upload format. Export the file instead.';
      case SubmitFailureKind.rateLimited:
        final wait = failure.retryAfter;
        final waitText = wait == null
            ? ''
            : ' Try again in about ${_humanWait(wait)}.';
        return 'Too many contributions from this connection right now.'
            '$waitText You can also export the file instead.';
      case SubmitFailureKind.server:
        return 'The server had a problem receiving this contribution. Please '
            'try again later, or export the file instead.';
      case SubmitFailureKind.unexpected:
        final code = failure.statusCode;
        return code == null
            ? 'Something went wrong sending this contribution. Export the '
                'file instead.'
            : 'Something went wrong (HTTP $code). Export the file instead.';
    }
  }

  /// A wait duration in whole minutes (rounded up), or seconds when under a
  /// minute, so "about 1 minute" never reads as "about 0 minutes".
  static String _humanWait(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds} seconds';
    final minutes = (d.inSeconds / 60).ceil();
    return minutes == 1 ? '1 minute' : '$minutes minutes';
  }

  // Export ----------------------------------------------------------------
  static const String exportSuccessTitle = 'File ready to share';
  static const String exportSuccessBody =
      'The contribution was saved and sent to your share sheet. You can send '
      'it later from wherever you saved it.';
  static const String exportFailed =
      'Could not write the file. Please try again.';
}
