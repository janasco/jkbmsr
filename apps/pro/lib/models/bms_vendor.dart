/// BMS vendor identifiers used by the Pro app's device configuration UI.
///
/// JKBMSR is an independent project that publicly supports **JK-BMS only**.
/// These identifiers mirror the API's two deliberately separate sets — see
/// `jkbmsr-api/src/constants/bmsVendors.ts`:
///
///  * [kSelectableBmsVendors]  — what the product offers. The settings picker
///    must offer only these. Do not widen it as part of a copy change.
///
///  * [kLegacyBmsVendorLabels]  — display labels for values a gateway may
///    already have stored from before. These are *not* supported and must
///    never appear as selectable options; they exist so a deployed gateway
///    with a legacy vendor is described honestly rather than silently
///    rewritten or shown as if it were supported.
///
/// The Pro app round-trips the stored `bmsVendor` on every settings save, and
/// the API still accepts all of the legacy values. Narrowing either side would
/// break saving settings for hardware already in the field.
library;

/// The only BMS hardware this product supports and offers in its UI.
const List<String> kSelectableBmsVendors = <String>['jk'];

/// Display names for legacy `bmsVendor` values that may still be stored on a
/// deployed gateway. Presentation only — never use these as picker items.
const Map<String, String> kLegacyBmsVendorLabels = <String, String>{
  'daly': 'Daly BMS',
  'jbd': 'JBD (Jiabaida)',
  'seplos': 'Seplos BMS',
  'ant': 'ANT BMS',
  'tianpower': 'Tianpower',
  'basen': 'Basen BMS',
  'ks': 'KS48100',
  'lolan': 'Lolan',
};

/// Human label for a stored vendor value, whether public or legacy.
String bmsVendorLabel(String value) {
  if (value == 'jk') return 'JK-BMS';
  return kLegacyBmsVendorLabels[value] ?? value;
}

/// True when a stored vendor is a publicly supported product target.
bool isPublicBmsVendor(String value) => kSelectableBmsVendors.contains(value);
