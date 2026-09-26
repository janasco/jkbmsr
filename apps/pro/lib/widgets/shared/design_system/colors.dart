import 'package:flutter/material.dart';

import 'tokens_generated.dart';

/// Theme-aware semantic colors (Unified Design System v1.0).
///
/// Widgets read these through `context.colors` instead of the fixed dark
/// constants that predate the light theme. Both palettes come from
/// jkbmsr-brand/tokens/tokens.json via tokens_generated.dart.
@immutable
class JKBMSRColors extends ThemeExtension<JKBMSRColors> {
  const JKBMSRColors({
    required this.canvas,
    required this.panel,
    required this.inset,
    required this.control,
    required this.line,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textSubtle,
    required this.accent,
    required this.onAccent,
    required this.signal,
    required this.onSignal,
    required this.warning,
    required this.critical,
  });

  final Color canvas;
  final Color panel;
  final Color inset;
  final Color control;
  final Color line;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textSubtle;

  /// Energy green — the product accent: healthy states, primary actions,
  /// active navigation.
  final Color accent;
  final Color onAccent;

  /// Interactive blue — links, focus, informational states. Never the green.
  final Color signal;
  final Color onSignal;
  final Color warning;
  final Color critical;

  static const JKBMSRColors light = JKBMSRColors(
    canvas: JKBMSRLightTokens.canvas,
    panel: JKBMSRLightTokens.panel,
    inset: JKBMSRLightTokens.inset,
    control: JKBMSRLightTokens.control,
    line: JKBMSRLightTokens.line,
    textPrimary: JKBMSRLightTokens.textPrimary,
    textSecondary: JKBMSRLightTokens.textSecondary,
    textMuted: JKBMSRLightTokens.textMuted,
    textSubtle: JKBMSRLightTokens.textSubtle,
    accent: JKBMSRLightTokens.accent,
    onAccent: JKBMSRLightTokens.onAccent,
    signal: JKBMSRLightTokens.signal,
    onSignal: JKBMSRLightTokens.onSignal,
    warning: JKBMSRLightTokens.warning,
    critical: JKBMSRLightTokens.critical,
  );

  static const JKBMSRColors dark = JKBMSRColors(
    canvas: JKBMSRDarkTokens.canvas,
    panel: JKBMSRDarkTokens.panel,
    inset: JKBMSRDarkTokens.inset,
    control: JKBMSRDarkTokens.control,
    line: JKBMSRDarkTokens.line,
    textPrimary: JKBMSRDarkTokens.textPrimary,
    textSecondary: JKBMSRDarkTokens.textSecondary,
    textMuted: JKBMSRDarkTokens.textMuted,
    textSubtle: JKBMSRDarkTokens.textSubtle,
    accent: JKBMSRDarkTokens.accent,
    onAccent: JKBMSRDarkTokens.onAccent,
    signal: JKBMSRDarkTokens.signal,
    onSignal: JKBMSRDarkTokens.onSignal,
    warning: JKBMSRDarkTokens.warning,
    critical: JKBMSRDarkTokens.critical,
  );

  @override
  JKBMSRColors copyWith({
    Color? canvas,
    Color? panel,
    Color? inset,
    Color? control,
    Color? line,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textSubtle,
    Color? accent,
    Color? onAccent,
    Color? signal,
    Color? onSignal,
    Color? warning,
    Color? critical,
  }) {
    return JKBMSRColors(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      inset: inset ?? this.inset,
      control: control ?? this.control,
      line: line ?? this.line,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textSubtle: textSubtle ?? this.textSubtle,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      signal: signal ?? this.signal,
      onSignal: onSignal ?? this.onSignal,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
    );
  }

  @override
  JKBMSRColors lerp(ThemeExtension<JKBMSRColors>? other, double t) {
    if (other is! JKBMSRColors) {
      return this;
    }
    return JKBMSRColors(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      inset: Color.lerp(inset, other.inset, t)!,
      control: Color.lerp(control, other.control, t)!,
      line: Color.lerp(line, other.line, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      signal: Color.lerp(signal, other.signal, t)!,
      onSignal: Color.lerp(onSignal, other.onSignal, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
    );
  }
}

/// `context.colors.panel` — the standard way widgets read semantic colors.
extension JKBMSRColorsX on BuildContext {
  JKBMSRColors get colors => Theme.of(this).extension<JKBMSRColors>()!;
}
