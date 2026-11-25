import 'package:flutter/material.dart';

/// Whether a trailing chip can share a line with the block beside it without
/// squeezing that block below a readable width.
///
/// The strip, the hero header and the hero footer all end in a small pill.
/// At the default text scale there is room for both; at 2x the pill grows with
/// the accessibility scale and would push the value or model name to nothing,
/// so it moves to its own line instead. The decision is made from measured
/// widths, not from a text-scale threshold, so a short pill stays inline even
/// at a large scale and a long one wraps as soon as it has to.
bool chipFitsBeside({
  required double availableWidth,
  required double chipWidth,
  required double leadingWidth,
  double gap = 8,
  double minPrimaryWidth = 96,
}) {
  if (!availableWidth.isFinite) return true;
  final usable = availableWidth - leadingWidth;
  return chipWidth + gap + minPrimaryWidth <= usable;
}

/// The width [text] occupies under the live text scaler.
///
/// Used by [chipFitsBeside]'s callers so the decision is made with the same
/// metrics the render tree will lay the chip out with. Measuring with the
/// default scaler instead would keep a pill inline at 2x and then overflow.
double measuredTextWidth({
  required String text,
  required TextStyle style,
  required TextScaler textScaler,
  required TextDirection textDirection,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: textDirection,
    textScaler: textScaler,
    maxLines: 1,
  )..layout();
  return painter.width;
}
