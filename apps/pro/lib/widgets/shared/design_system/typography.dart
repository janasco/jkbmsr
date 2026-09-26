import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography definitions for JKBMSR (Unified Design System v1.0).
///
/// IBM Plex Sans for UI and prose, IBM Plex Mono for telemetry values,
/// device IDs, and technical tables — the same pairing as the web surfaces.
///
/// Styles are color-free on purpose: color comes from the active theme's
/// `textTheme` (see theme.dart) or from `context.colors`, so one scale
/// serves both light and dark.
class JKBMSRTypography {
  JKBMSRTypography._();

  // --- Font Families ---
  static TextStyle get baseSans => GoogleFonts.ibmPlexSans();
  static TextStyle get baseMono => GoogleFonts.ibmPlexMono();

  /// Page heading: one per screen.
  static TextStyle get pageHeading => baseSans.copyWith(
        fontSize: 22.0,
        fontWeight: FontWeight.w600,
        height: 1.27,
      );

  /// Section heading.
  static TextStyle get sectionHeading => baseSans.copyWith(
        fontSize: 17.0,
        fontWeight: FontWeight.w600,
        height: 1.4,
      );

  /// Card heading.
  static TextStyle get cardHeading => baseSans.copyWith(
        fontSize: 16.0,
        fontWeight: FontWeight.w600,
        height: 1.35,
      );

  /// Body text — 16px on mobile for arm's-length readability.
  static TextStyle get body => baseSans.copyWith(
        fontSize: 16.0,
        fontWeight: FontWeight.w400,
        height: 1.5,
      );

  /// Secondary body text; pair with `context.colors.textMuted`.
  static TextStyle get bodySecondary => baseSans.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w400,
        height: 1.45,
      );

  /// Table text.
  static TextStyle get tableText => baseSans.copyWith(
        fontSize: 14.0,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  /// Label/caption text: uppercase labels, stat captions.
  static TextStyle get label => baseSans.copyWith(
        fontSize: 12.0,
        fontWeight: FontWeight.w600,
        height: 1.33,
        letterSpacing: 0.72,
      );

  /// Telemetry numerals and technical identifiers: mono, tabular figures so
  /// voltages align in columns.
  static TextStyle get monoTechnical => baseMono.copyWith(
        fontSize: 13.0,
        fontWeight: FontWeight.w400,
        height: 1.4,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Bold variant helper
  static TextStyle get bold => const TextStyle(fontWeight: FontWeight.bold);
}
