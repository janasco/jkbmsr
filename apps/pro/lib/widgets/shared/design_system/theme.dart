import 'package:flutter/material.dart';

import 'colors.dart';
import 'tokens.dart';
import 'typography.dart';

/// Unified design system themes for JKBMSR (Unified Design System v1.0).
///
/// Both themes are built from the same semantic palette (JKBMSRColors); the
/// brand environment is dark-first, but light and dark ship with equal care.
class JKBMSRTheme {
  JKBMSRTheme._();

  static ThemeData get lightTheme => _build(JKBMSRColors.light, Brightness.light);
  static ThemeData get darkTheme => _build(JKBMSRColors.dark, Brightness.dark);

  static ThemeData _build(JKBMSRColors c, Brightness brightness) {
    final textColor = c.textSecondary;
    final headingColor = c.textPrimary;

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      primaryColor: c.accent,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.panel,
      cardColor: c.panel,
      dividerColor: c.line,
      extensions: [c],

      // --- Color Scheme ---
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.signal,
        onSecondary: c.onSignal,
        surface: c.panel,
        onSurface: textColor,
        error: c.critical,
        onError: brightness == Brightness.dark ? c.textPrimary : c.panel,
      ),

      // --- Typography (colors applied per theme; scale is shared) ---
      textTheme: TextTheme(
        displayLarge: JKBMSRTypography.pageHeading.copyWith(color: headingColor),
        displayMedium: JKBMSRTypography.sectionHeading.copyWith(color: headingColor),
        titleLarge: JKBMSRTypography.pageHeading.copyWith(color: headingColor),
        titleMedium: JKBMSRTypography.cardHeading.copyWith(color: headingColor),
        bodyLarge: JKBMSRTypography.body.copyWith(color: textColor),
        bodyMedium: JKBMSRTypography.body.copyWith(color: textColor),
        bodySmall: JKBMSRTypography.tableText.copyWith(color: c.textMuted),
        labelLarge: JKBMSRTypography.label.copyWith(color: c.textMuted),
      ),

      // --- Input Decoration (Forms, TextFields) ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.inset,
        hintStyle: JKBMSRTypography.bodySecondary.copyWith(color: c.textSubtle),
        labelStyle: JKBMSRTypography.label.copyWith(color: c.textMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: JKBMSRTokens.space16,
          vertical: JKBMSRTokens.space12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          borderSide: BorderSide(color: c.line),
        ),
        // Focus is signal blue across the design system, not the accent.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          borderSide: BorderSide(color: c.signal, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          borderSide: BorderSide(color: c.critical),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          borderSide: BorderSide(color: c.critical, width: 1.5),
        ),
      ),

      // --- Buttons ---
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          padding: const EdgeInsets.symmetric(
            horizontal: JKBMSRTokens.space24,
            vertical: JKBMSRTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          ),
          textStyle: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: headingColor,
          side: BorderSide(color: c.control),
          padding: const EdgeInsets.symmetric(
            horizontal: JKBMSRTokens.space24,
            vertical: JKBMSRTokens.space12,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
          ),
          textStyle: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: c.signal),
      ),

      // --- App Bar ---
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: headingColor),
        titleTextStyle: JKBMSRTypography.sectionHeading.copyWith(color: headingColor),
        shape: Border(bottom: BorderSide(color: c.line)),
      ),

      // --- Navigation Bar (bottom nav) ---
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.panel,
        indicatorColor: c.accent.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return JKBMSRTypography.label.copyWith(color: c.accent);
          }
          return JKBMSRTypography.label.copyWith(color: c.textMuted);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: c.accent);
          }
          return IconThemeData(color: c.textMuted);
        }),
      ),

      // --- Card ---
      cardTheme: CardThemeData(
        color: c.panel,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        ),
        margin: EdgeInsets.zero,
      ),

      // --- Overlays ---
      dialogTheme: DialogThemeData(
        backgroundColor: c.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.panel,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(JKBMSRTokens.radius16)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.panel,
        contentTextStyle: JKBMSRTypography.bodySecondary.copyWith(color: headingColor),
        actionTextColor: c.signal,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.line),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        ),
      ),
    );
  }
}
