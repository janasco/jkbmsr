import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_contributor/models/contribution.dart';
import 'package:jkbmsr_contributor/models/contribution_selection.dart';

import '../support/jk02_fixtures.dart';

void main() {
  group('ContributionFields', () {
    test('every opt-out field is included by default (privacy-first is off-only '
        'for the serial)', () {
      final defaults = ContributionSelection.defaults();
      for (final field in ContributionFields.all) {
        expect(defaults.includes(field.id), isTrue, reason: field.id);
        expect(field.defaultIncluded, isTrue, reason: field.id);
      }
      // The serial is the one opt-in, and it is not an opt-out field.
      expect(
        ContributionFields.all.any((f) => f.id.contains('serial')),
        isFalse,
      );
    });
  });

  group('per-field opt-out', () {
    test('switching one field off removes exactly that field', () {
      final c = sampleContribution();
      final selection =
          ContributionSelection.defaults().toggled('bms.modelName', false);

      final json = c.toJson(selection: selection);
      final bms = json['bms'] as Map<String, dynamic>;

      expect(bms.containsKey('modelName'), isFalse);
      expect(bms['hardwareVersion'], c.bms.hardwareVersion);
      expect(bms['softwareVersion'], c.bms.softwareVersion);
      // Unrelated sections are untouched.
      final full = c.toJson();
      expect(json['advertisement'], full['advertisement']);
      expect(json['samples'], full['samples']);
      expect(json['contributionId'], full['contributionId']);
    });

    test('a Bluetooth sub-field can be removed on its own', () {
      final c = sampleContribution();
      final selection = ContributionSelection.defaults()
          .toggled('advertisement.addressMasked', false);

      final advertisement =
          c.toJson(selection: selection)['advertisement'] as Map<String, dynamic>;
      expect(advertisement.containsKey('addressMasked'), isFalse);
      expect(advertisement['namePattern'], c.advertisement.namePattern);
      expect(advertisement['rssiBucket'], c.advertisement.rssiBucket);
    });

    test('withholding records exactly the fields that held a value', () {
      final c = sampleContribution();
      final selection = ContributionSelection.defaults()
          .toggled('bms.modelName', false)
          .toggled('settings', false); // settings is absent in this fixture

      final redaction =
          c.toJson(selection: selection)['redaction'] as Map<String, dynamic>;
      final omitted = (redaction['omittedFields'] as List).cast<String>();
      expect(omitted, contains('bms.modelName'));
      // "settings" was never present, so it is not recorded as withheld.
      expect(omitted, isNot(contains('settings')));
      expect(omitted, isNot(contains('bms.serialHash')));
    });

    test('a fully trimmed payload is smaller and still decodes', () {
      final c = sampleContribution();
      final trimmed = ContributionSelection.none();
      expect(c.encodedBytes(selection: trimmed), lessThan(c.encodedBytes()));

      final decoded = Contribution.decode(c.encode(selection: trimmed));
      expect(decoded.samples, isEmpty);
      expect(decoded.rawFrames, isEmpty);
      expect(decoded.bms.modelName, isEmpty);
    });
  });

  group('serial opt-in', () {
    test('is withheld by default and only shared when asked for', () {
      final c = sampleContribution();
      expect(c.bms.serialHash, isNull);
      expect(c.redaction.serialNumber, 'withheld');

      final shared = c.withSerial('2021602096', include: true);
      expect(shared.bms.serialHash, '2021602096');
      expect(shared.redaction.serialNumber, 'shared');

      final withheld = c.withSerial('2021602096', include: false);
      expect(withheld.bms.serialHash, isNull);
      expect(withheld.redaction.serialNumber, 'withheld');
    });

    test('an unticked serial is never serialised into the payload', () {
      final selection = ContributionSelection.defaults();
      final json = sampleContribution().toJson(selection: selection);
      expect((json['bms'] as Map)['serialHash'], isNull);
      expect((json['redaction'] as Map)['serialNumber'], 'withheld');
    });
  });

  group('the payload is an allowlist', () {
    test('only schema fields can be serialised', () {
      final keys = sampleContribution().toJson().keys.toSet();
      const allowed = {
        'schemaVersion',
        'contributionId',
        'capturedAt',
        'app',
        'consent',
        'bms',
        'advertisement',
        'samples',
        'settings',
        'logbook',
        'rawFrames',
        'redaction',
        'sizeBytes',
      };
      expect(keys.difference(allowed), isEmpty);
    });
  });
}
