import 'package:flutter/material.dart';

import '../services/app_info.dart';
import '../services/consent_controller.dart';
import '../widgets/brand_mark.dart';
import 'capture_screen.dart';
import 'consent_screen.dart';

/// Home.
///
/// The app opens here. Capture is gated on consent: while the gate is covering
/// the shell it cannot be reached at all, and after a decline this button
/// re-opens the consent screen instead of starting a scan.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _startCapture(BuildContext context) {
    final consent = ConsentScope.maybeOf(context);
    final navigator = Navigator.of(context);
    if (consent == null || consent.isGranted) {
      navigator.push(
        MaterialPageRoute<void>(builder: (_) => const CaptureScreen()),
      );
      return;
    }
    // Declined earlier: ask again rather than capture without consent.
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ConsentScreen(
          controller: consent,
          onDecided: () => navigator.pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppInfo.appName)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BrandMark(),
              const SizedBox(height: 24),
              Text(
                AppInfo.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppInfo.tagline,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _startCapture(context),
                icon: const Icon(Icons.bluetooth_searching_rounded),
                label: const Text('Start a capture'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
