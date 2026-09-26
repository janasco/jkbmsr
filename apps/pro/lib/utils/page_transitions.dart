import 'package:flutter/material.dart';

/// Custom page transition builders for JKBMSR mobile app.
/// Replaces the default instant-pop with smooth slide/fade transitions
/// that feel native on both Android and iOS.
class JKBMSRPageTransitions {
  JKBMSRPageTransitions._();

  /// Standard forward push: slides in from the right (iOS-style).
  static Widget slideFromRight(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeOutCubic;

    final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    final fadeTween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(
        opacity: animation.drive(fadeTween),
        child: child,
      ),
    );
  }

  /// Fade and scale transition for modals and overlays.
  static Widget fadeScale(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    const curve = Curves.easeOutCubic;

    final scaleTween = Tween(begin: 0.95, end: 1.0).chain(CurveTween(curve: curve));
    final fadeTween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

    return ScaleTransition(
      scale: animation.drive(scaleTween),
      child: FadeTransition(
        opacity: animation.drive(fadeTween),
        child: child,
      ),
    );
  }

  /// Slide up from bottom — used for settings, OTA, and history screens.
  static Widget slideFromBottom(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    const begin = Offset(0.0, 0.05);
    const end = Offset.zero;
    const curve = Curves.easeOutCubic;

    final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    final fadeTween = Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: curve));

    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(
        opacity: animation.drive(fadeTween),
        child: child,
      ),
    );
  }

  /// No transition — instant swap. Used for tab switches within the shell.
  static Widget noTransition(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    return child;
  }
}
