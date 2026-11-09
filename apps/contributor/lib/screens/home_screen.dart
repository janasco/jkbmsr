import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/app_info.dart';
import '../services/consent_controller.dart';
import '../services/coverage_service.dart';
import '../widgets/app_surface.dart';
import '../widgets/brand_mark.dart';
import 'capture_screen.dart';
import 'consent_screen.dart';

/// Home.
///
/// The app opens here. Capture is gated on consent: while the gate is covering
/// the shell it cannot be reached at all, and after a decline this button
/// re-opens the consent screen instead of starting a scan.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.coverageService});

  /// Injected for tests; defaults to the real summary endpoint. The fetch is
  /// strictly cosmetic, so nothing on this screen waits for it.
  final CoverageService? coverageService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final CoverageService _coverageService;
  late final bool _ownsCoverageService;
  CorpusCoverage? _coverage;

  @override
  void initState() {
    super.initState();
    _ownsCoverageService = widget.coverageService == null;
    _coverageService = widget.coverageService ?? CoverageService();
    // After the first frame, never during it: the capture flow must be ready
    // before a network request is even attempted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCoverage());
  }

  Future<void> _loadCoverage() async {
    final coverage = await _coverageService.fetch();
    if (!mounted || coverage == null) return;
    setState(() => _coverage = coverage);
  }

  @override
  void dispose() {
    if (_ownsCoverageService) _coverageService.close();
    super.dispose();
  }

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
                if (_coverage != null) ...[
                  const SizedBox(height: 18),
                  AppSurface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    radius: 18,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.battery_charging_full_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            CoverageStrings.line(
                              packs: _coverage!.contributions,
                              models: _coverage!.models,
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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
