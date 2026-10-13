import 'package:flutter/material.dart';

import '../services/app_info.dart';

/// The app's brand mark.
///
/// Falls back to an icon when the asset cannot be loaded (for example on the
/// Dart VM during a widget test), so the screen never renders an error box.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 96});

  /// Rendered width and height, in logical pixels.
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/app_logo.png',
      width: size,
      height: size,
      errorBuilder: (context, error, stackTrace) => Icon(
        Icons.battery_charging_full_rounded,
        size: size,
        color: AppInfo.brandColor,
      ),
    );
  }
}
