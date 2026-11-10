import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/contribution.dart';
import '../services/app_info.dart';
import '../services/ble_transport.dart';
import '../services/capture_service.dart';
import '../services/consent_controller.dart';
import '../services/universal_ble_transport.dart';
import '../widgets/app_surface.dart';
import '../theme/app_theme.dart';
import '../widgets/rotating_glyph.dart';
import 'capture_success_screen.dart';

/// Default app/OS provenance for a contribution, read from the platform.
AppProvenance buildAppProvenance() {
  final os = Platform.operatingSystem; // 'android' | 'ios' | ...
  return AppProvenance(
    version: AppInfo.version,
    platform: os,
    osVersion: Platform.operatingSystemVersion,
  );
}

enum _Stage { idle, scanning, capturing, error }

/// Scan → capture → hand off to [CaptureSuccessScreen].
///
/// The three states are visually distinct on purpose. A capture is a thing that
/// takes ~30 seconds and then produces an artefact, so the screen shows a live
/// instrument while it runs (an orb whose glyph advances with the progress, a
/// real progress bar, live sample and frame counts) and then gets out of the way
/// — the result is its own screen, not a list appended under a spinner.
///
/// Capture is consent-gated: it cannot start without consent, even if this
/// screen is reached another way.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.controller, this.captureDuration});

  /// Injected for tests; defaults to the real BLE-backed service.
  final CaptureController? controller;
  final Duration? captureDuration;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with SingleTickerProviderStateMixin {
  late final CaptureController _controller = widget.controller ??
      CaptureService(transport: UniversalBleTransport());
  late final Duration _duration =
      widget.captureDuration ?? CaptureService.defaultDuration;

  /// Drives the progress bar over the capture window. Deliberately an animation
  /// rather than a `Timer`: it is smooth, it stops when told to, and a test can
  /// advance it by pumping.
  late final AnimationController _bar =
      AnimationController(vsync: this, duration: _duration);

  _Stage _stage = _Stage.idle;
  String _status = '';
  String? _error;

  /// Set only for a scan that failed for a user-fixable reason (Bluetooth off,
  /// a denied permission, Location Services off). Drives the error view's copy.
  BleScanFailureKind? _errorKind;

  /// Set only for a *capture* that failed for a classified reason (Bluetooth
  /// switched off mid-session, the pack out of range).
  BleCaptureFailureKind? _captureErrorKind;
  List<BleScanResult> _devices = const [];
  StreamSubscription<List<BleScanResult>>? _scanSubscription;
  bool _scanComplete = false;
  CaptureProgress? _progress;
  bool _cancelled = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _bar.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _scanSubscription?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.scanning;
      _status = 'Scanning for a JK-BMS…';
      _devices = const [];
      _error = null;
      _errorKind = null;
      _captureErrorKind = null;
      _scanComplete = false;
    });

    final completer = Completer<void>();
    _scanSubscription = _controller.scan().listen(
      (devices) {
        if (!mounted) return;
        setState(() => _devices = devices);
      },
      onError: (Object e) {
        if (!mounted) return;
        // Bluetooth-off (and permission/location failures) are actionable
        // states, not internal errors: show the plain sentence, and keep the
        // raw reason in the logs rather than in the product text.
        final failure = classifyScanFailure(e);
        debugPrint('Scan failed (${failure.kind.name}): ${failure.cause ?? e}');
        setState(() {
          _stage = _Stage.error;
          _error = ScanStrings.scanFailure(failure.kind);
          _errorKind = failure.kind;
        });
      },
      onDone: () => completer.complete(),
    );
    await completer.future;
    if (!mounted) return;
    setState(() {
      _scanComplete = true;
      if (_devices.isEmpty) {
        _status = 'No JK-BMS found. Make sure the pack is powered and nearby.';
      } else {
        _status = 'Found ${_devices.length} device(s). Tap one to capture.';
      }
    });
  }

  Future<void> _capture(BleScanResult device) async {
    _cancelled = false;
    setState(() {
      _stage = _Stage.capturing;
      _status = 'Connecting to ${device.name}…';
      _progress = null;
      _errorKind = null;
      _captureErrorKind = null;
    });
    _bar
      ..reset()
      ..forward();

    final outcome = await _controller.capture(
      device,
      duration: _duration,
      app: buildAppProvenance(),
      isCancelled: () => _cancelled,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _status = progress.status;
        });
      },
    );

    if (!mounted) return;
    _bar.stop();

    if (!outcome.success) {
      setState(() {
        _stage = _Stage.error;
        _error = outcome.error;
        _captureErrorKind = outcome.failureKind;
      });
      return;
    }

    // Back to idle underneath: returning from the success screen must not land
    // on a frozen instrument reading 97%.
    setState(() {
      _stage = _Stage.idle;
      _status = '';
      _progress = null;
    });

    final again = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CaptureSuccessScreen(outcome: outcome),
      ),
    );
    if (again == true && mounted) {
      await _startScan();
    }
  }

  /// True when there is no gate in scope, or the gate has granted consent.
  bool _consentGranted(BuildContext context) {
    final consent = ConsentScope.maybeOf(context);
    return consent == null || consent.isGranted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Capture')),
      body: SafeArea(
        child: _consentGranted(context)
            ? _buildBody(context)
            : _buildConsentRequired(context),
      ),
    );
  }

  /// Defence in depth: the gate already blocks this screen, but a capture must
  /// never start without consent even if the screen is reached another way.
  Widget _buildConsentRequired(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined,
                size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Contributing is switched off.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'No capture can start until you agree to contribute.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_stage) {
      case _Stage.idle:
        return _buildIdle(context);
      case _Stage.scanning:
        return _buildScanning(context);
      case _Stage.capturing:
        return _buildCapturing(context);
      case _Stage.error:
        return _buildError(context);
    }
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        AppSurface(
          border: false,
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 26),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary.withValues(alpha: 0.20),
              scheme.tertiary.withValues(alpha: 0.06),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.battery_charging_full_rounded,
                  size: 28,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 18),
              Text('Capture your JK-BMS', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Read one telemetry session and turn it into an anonymous '
                'contribution. The app only listens and never writes to your '
                'battery.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppSurface(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Column(
            children: [
              const AssuranceRow(
                icon: Icons.visibility_off_outlined,
                title: 'Read-only',
                detail: 'Nothing is ever written to the BMS.',
              ),
              const Divider(),
              const AssuranceRow(
                icon: Icons.person_off_outlined,
                title: 'No account, no identity',
                detail:
                    'No sign-in, no device ID and no IP address are stored.',
              ),
              const Divider(),
              AssuranceRow(
                icon: Icons.timer_outlined,
                // Derived, not typed: the claim cannot drift from the capture
                // this build actually performs.
                title:
                    'About ${CaptureService.defaultDuration.inSeconds} seconds',
                detail: 'Keep the pack powered and within a few metres.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: _startScan,
          icon: const Icon(Icons.bluetooth_searching_rounded),
          label: const Text('Scan for JK-BMS'),
        ),
        const SizedBox(height: 14),
        Text(
          'Bluetooth must be on. Nothing leaves this phone until you press '
          'Contribute. · v${AppInfo.version}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildScanning(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary.withValues(alpha: 0.08),
                ),
                child: _scanComplete
                    ? Icon(Icons.bluetooth_searching_rounded,
                        size: 30, color: scheme.primary)
                    : SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: scheme.primary,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                _scanComplete ? 'Scan complete' : 'Looking for your battery',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _scanComplete && _devices.isEmpty
                    ? 'No JK-BMS answered. Make sure the pack is powered and '
                        'within a few metres.'
                    : 'Make sure the pack is powered and Bluetooth is on.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            itemCount: _devices.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _DeviceCard(
              device: _devices[i],
              onTap: () => _capture(_devices[i]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          child: TextButton(
            onPressed: _startScan,
            child: const Text('Scan again'),
          ),
        ),
      ],
    );
  }

  Widget _buildCapturing(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = _progress;

    return AnimatedBuilder(
      animation: _bar,
      builder: (context, _) {
        // Hold just short of full until the outcome actually arrives: the
        // logbook read and disconnect happen after the capture window, and a bar
        // sitting at 100% while work continues is a lie.
        final value = _bar.value.clamp(0.0, 0.97);
        final finishing = _bar.value >= 0.97;

        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: ConstrainedBox(
                    // Fills the viewport so the instrument sits in the middle of
                    // the screen instead of hugging the top with a dead half
                    // below it, while still scrolling when text is large.
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight > 40
                          ? constraints.maxHeight - 40
                          : 0,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _CaptureOrb(progress: _bar.value),
                        const SizedBox(height: 28),
                        Text(
                          _status,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Keep this screen open and stay near the pack.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _CaptureBar(value: value, finishing: finishing),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStat(
                                icon: Icons.timeline_rounded,
                                value: '${progress?.sampleCount ?? 0}',
                                label: 'Samples',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _MiniStat(
                                icon: Icons.layers_rounded,
                                value: '${progress?.frameCount ?? 0}',
                                label: 'Frames',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: TextButton(
                onPressed: () => setState(() => _cancelled = true),
                child: const Text('Stop early'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bluetoothOff = _errorKind == BleScanFailureKind.bluetoothOff ||
        _captureErrorKind == BleCaptureFailureKind.bluetoothOff;

    final String hint;
    if (bluetoothOff) {
      hint = 'Turn Bluetooth on, then try again.';
    } else if (_errorKind == BleScanFailureKind.permissionDenied) {
      hint = 'Allow the Bluetooth permission, then try again.';
    } else if (_captureErrorKind == BleCaptureFailureKind.outOfRange) {
      hint = 'Move closer to the pack and keep it powered.';
    } else {
      hint = 'Nothing was recorded. Trying again is safe.';
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.error.withValues(alpha: 0.10),
              ),
              child: Icon(
                bluetoothOff
                    ? Icons.bluetooth_disabled_rounded
                    : Icons.error_outline_rounded,
                size: 40,
                color: scheme.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton(onPressed: _startScan, child: const Text('Try again')),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// The device row on the scan list.
class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.onTap});

  final BleScanResult device;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.battery_charging_full_rounded,
              size: 22,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name.isEmpty ? '(unnamed device)' : device.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${device.rssi} dBm · ${device.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: scheme.outline),
        ],
      ),
    );
  }
}

/// The orb: three concentric rings with the changing glyph at the centre.
class _CaptureOrb extends StatelessWidget {
  const _CaptureOrb({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 188,
      height: 188,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 188,
            height: 188,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.05),
            ),
          ),
          Container(
            width: 146,
            height: 146,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.08),
            ),
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accent[0].withValues(alpha: 0.28),
                  AppTheme.accent[1].withValues(alpha: 0.20),
                ],
              ),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.28)),
            ),
            child: Center(
              child: RotatingGlyph(progress: progress, size: 52),
            ),
          ),
        ],
      ),
    );
  }
}

/// The determinate progress bar, with its own label and percentage.
class _CaptureBar extends StatelessWidget {
  const _CaptureBar({required this.value, required this.finishing});

  /// 0 to 1, already clamped short of full while work remains.
  final double value;
  final bool finishing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = (value * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                finishing ? 'Finishing up…' : 'Capturing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$percent%',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 12,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(color: scheme.surfaceContainerHighest),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: constraints.maxWidth * value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One live counter under the bar.
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSurface(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
