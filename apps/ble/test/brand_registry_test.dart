import 'package:flutter_test/flutter_test.dart';
import 'package:jkbmsr_ble/models/bms_models.dart';
import 'package:jkbmsr_ble/protocols/bms_protocol.dart';
import 'package:jkbmsr_ble/services/brand_registry.dart';

/// JKBMSR publicly supports JK-BMS only. Every other decoder is retained
/// internally, so these tests pin the *public* surface while guarding the
/// detection machinery the retained decoders depend on.
void main() {
  group('public vs internal brand split', () {
    test('only JK-BMS is publicly selectable', () {
      final selectable = BrandRegistry.selectableBrands;
      expect(selectable.length, 1);
      expect(selectable.single.brand, BmsBrand.jkbms);
    });

    test('isPublic is true for JK-BMS only', () {
      for (final brand in BmsBrand.values) {
        expect(
          brand.isPublic,
          brand == BmsBrand.jkbms,
          reason: '${brand.name} public-support flag is wrong',
        );
      }
    });

    test('internal decoders are retained, not removed', () {
      // Guards against a "delete the other brands" sweep. These parsers are
      // real shipped work and are load-bearing for detection.
      const retained = [
        BmsBrand.daly,
        BmsBrand.jbd,
        BmsBrand.ant,
        BmsBrand.seplos,
        BmsBrand.tianpower,
        BmsBrand.basen,
        BmsBrand.ks,
        BmsBrand.ogt,
        BmsBrand.topband,
        BmsBrand.lolan,
      ];
      for (final brand in retained) {
        expect(BrandRegistry.supportedBrands.map((d) => d.brand),
            contains(brand),
            reason: '${brand.name} should remain an internal brand');
      }
    });
  });

  group('detection depends on the FULL brand set, not the public one', () {
    // 0xFF00 and 0xFFE0 are each shared by several protocols. If the public
    // list were ever used to build the candidate set or the sharing count,
    // a JBD/Seplos/ANT/Tianpower device would score an "exclusive" 0.6
    // service match and the scanner would show a confident "60% MATCH JK"
    // badge — after which the app would write JK02 frames to a non-JK pack.
    test('serviceSharingCount still reports shared services as shared', () {
      expect(BrandRegistry.serviceSharingCount(BmsProtocolHelper.jkBmsServiceUuid),
          greaterThan(1),
          reason: '0xFFE0 must stay classified as shared');
      expect(BrandRegistry.serviceSharingCount(BmsProtocolHelper.jk02ServiceUuid),
          greaterThan(1),
          reason: '0xFF00 must stay classified as shared');
      expect(BrandRegistry.serviceSharingCount(BmsProtocolHelper.dalyServiceUuid),
          greaterThan(1),
          reason: '0xFFF0 is shared by Daly and OGT');
    });

    test('an exclusive service is still scored as exclusive', () {
      expect(
          BrandRegistry.serviceSharingCount(BmsProtocolHelper.basenServiceUuid), 1,
          reason: 'Basen 0xFA00 is genuinely exclusive and must stay so');
    });
  });
}
