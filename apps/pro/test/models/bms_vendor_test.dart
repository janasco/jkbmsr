import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_pro/models/bms_vendor.dart';

/// JKBMSR publicly supports JK-BMS only, but a gateway deployed before that
/// decision may still have a legacy `bmsVendor` stored on it. The Pro app
/// round-trips that value on every settings save, so these tests pin the
/// distinction between "what we offer" and "what we must not silently
/// rewrite".
void main() {
  group('selectable vendors', () {
    test('JK-BMS is the only option offered in the UI', () {
      expect(kSelectableBmsVendors, <String>['jk']);
    });

    test('no legacy vendor is offered as a selectable option', () {
      for (final vendor in kLegacyBmsVendorLabels.keys) {
        expect(
          kSelectableBmsVendors.contains(vendor),
          false,
          reason: '$vendor must not be selectable — it is not a supported product',
        );
      }
    });
  });

  group('isPublicBmsVendor', () {
    test('is true only for JK-BMS', () {
      expect(isPublicBmsVendor('jk'), isTrue);
      for (final vendor in kLegacyBmsVendorLabels.keys) {
        expect(isPublicBmsVendor(vendor), isFalse, reason: vendor);
      }
      expect(isPublicBmsVendor('acme'), isFalse);
      expect(isPublicBmsVendor(''), isFalse);
    });
  });

  group('bmsVendorLabel', () {
    test('labels every legacy value so a stored config reads honestly', () {
      // The combobox renders itemToString(selectedItem) from the stored VALUE,
      // not from the items list, so a legacy value must still produce a
      // sensible label rather than crashing or rendering blank.
      for (final entry in kLegacyBmsVendorLabels.entries) {
        expect(bmsVendorLabel(entry.key), entry.value);
      }
    });

    test('falls back to the raw value for anything unknown', () {
      expect(bmsVendorLabel('some-future-vendor'), 'some-future-vendor');
    });

    test('labels JK-BMS', () {
      expect(bmsVendorLabel('jk'), 'JK-BMS');
    });
  });

  test('every selectable vendor is also public', () {
    for (final vendor in kSelectableBmsVendors) {
      expect(isPublicBmsVendor(vendor), isTrue, reason: vendor);
    }
  });
}
