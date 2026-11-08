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
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.surfaceContainerHigh,
                        scheme.surfaceContainerLow,
                      ],
                    ),
                    border: Border.all(color: scheme.outlineVariant),
                    boxShadow: [
                      BoxShadow(
                        color: scheme.shadow.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const BrandMark(),
                ),
                const SizedBox(height: 26),
                Text(
                  AppInfo.appName,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                Text(
                  AppInfo.tagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 34),
                FilledButton.icon(
                  onPressed: () => _startCapture(context),
                  icon: const Icon(Icons.bluetooth_searching_rounded),
                  label: const Text('Start a capture'),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Anonymous by design · no account, no identity',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
