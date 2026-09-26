/// Shape, spacing, and motion tokens for JKBMSR (Unified Design System v1.0).
///
/// Colors intentionally live elsewhere: theme-aware semantic colors are read
/// through `context.colors` (see colors.dart); the raw palette values come
/// from jkbmsr-brand/tokens/tokens.json via tokens_generated.dart.
class JKBMSRTokens {
  JKBMSRTokens._();

  // --- Spacing / Padding (4-pt grid) ---
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space48 = 48.0;

  // --- Border Radii ---
  // sm: badges/chips · md: buttons/inputs · lg: cards/dialogs · xl: sheets.
  static const double radius2 = 2.0;
  static const double radius4 = 4.0;
  static const double radius8 = 8.0;
  static const double radius12 = 12.0;
  static const double radius16 = 16.0;
  static const double radiusFull = 9999.0;

  // --- Animation Durations ---
  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationNormal = Duration(milliseconds: 200);
  static const Duration durationSlow = Duration(milliseconds: 300);
}
