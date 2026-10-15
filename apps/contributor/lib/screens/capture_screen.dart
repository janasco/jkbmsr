import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../models/contribution.dart';
import '../services/app_info.dart';
import '../services/ble_transport.dart';
import '../services/capture_service.dart';
import '../services/consent_controller.dart';
import '../services/flutter_blue_plus_transport.dart';
import 'review_screen.dart';

/// Default app/OS provenance for a contribution, read from the platform.
AppProvenance buildAppProvenance() {
  final os = Platform.operatingSystem; // 'android' | 'ios' | ...
  return AppProvenance(
    version: AppInfo.version,
    platform: os,
    osVersion: Platform.operatingSystemVersion,
  );
}

enum _Stage { idle, scanning, capturing, done, error }

/// A minimal capture screen: scan → connect → capture → summary → review.
///
/// Capture is consent-gated (a capture cannot start without it), and the
/// summary's "Review & contribute" opens [ReviewScreen], where the user can
/// submit anonymously or export the payload to a file.
class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key, this.controller, this.captureDuration});

  /// Injected for tests; defaults to the real BLE-backed service.
  final CaptureController? controller;
  final Duration? captureDuration;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  late final CaptureController _controller =
      widget.controller ?? CaptureService(transport: FlutterBluePlusTransport());
  late final Duration _duration = widget.captureDuration ?? CaptureService.defaultDuration;

  _Stage _stage = _Stage.idle;
  String _status = '';
  String? _error;

  /// Set only for a scan that failed for a user-fixable reason (Bluetooth off,
  /// a denied permission, Location Services off). Drives the icon on the error
  /// view; a capture failure leaves it null.
  BleScanFailureKind? _errorKind;
  List<BleScanResult> _devices = const [];
  StreamSubscription<List<BleScanResult>>? _scanSubscription;
  bool _scanComplete = false;
  CaptureProgress? _progress;
  CaptureOutcome? _outcome;
  bool _cancelled = false;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }

  Future<void> _startScan() async {
    await _scanSubscription?.cancel();
    setState(() {
      _stage = _Stage.scanning;
      _status = 'Scanning for a JK-BMS…';
      _devices = const [];
      _error = null;
      _errorKind = null;
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
      _outcome = null;
      _errorKind = null;
    });

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
    setState(() {
      _outcome = outcome;
      if (outcome.success) {
        _stage = _Stage.done;
      } else {
        _stage = _Stage.error;
        _error = outcome.error;
      }
    });
  }

  /// Fills the Phase 3 seam: open the review screen with the real payload, the
  /// device serial (for the opt-in toggle) and the consent to stamp. Submit and
  /// export happen there (Phase 5).
  void _onReviewPressed() {
    final contribution = _outcome?.contribution;
    if (contribution == null) return;
    final consent = ConsentScope.maybeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          contribution: contribution,
          rawSerial: _outcome?.session?.deviceInfo?.serialNumber,
          consent: consent?.record,
        ),
      ),
    );
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
            Icon(Icons.shield_outlined, size: 56, color: theme.colorScheme.primary),
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
      case _Stage.done:
        return _buildSummary(context);
      case _Stage.error:
        return _buildError(context);
    }
  }

  Widget _buildIdle(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_searching_rounded, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Capture a JK-BMS session',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This reads your battery\'s device information and telemetry and '
              'builds an anonymous contribution. It never writes to the BMS.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.search_rounded),
              label: const Text('Scan for JK-BMS'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanning(BuildContext context) {
    return Column(
      children: [
        if (!_scanComplete)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(_status, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _devices.isEmpty
              ? const SizedBox.shrink()
              : ListView.builder(
                  itemCount: _devices.length,
                  itemBuilder: (context, i) {
                    final d = _devices[i];
                    return ListTile(
                      leading: const Icon(Icons.battery_charging_full_rounded),
                      title: Text(d.name.isEmpty ? '(unnamed device)' : d.name),
                      subtitle: Text('${d.rssi} dBm · ${d.id}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _capture(d),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCapturing(BuildContext context) {
    final p = _progress;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            p == null
                ? ''
                : 'Frames: ${p.frameCount}  ·  Samples: ${p.sampleCount}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => setState(() => _cancelled = true),
            child: const Text('Stop early'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final outcome = _outcome!;
    final c = outcome.contribution!;
    final theme = Theme.of(context);
    final bms = c.bms;

    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(label, style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              Expanded(
                child: Text(value, style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Text('Captured', style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 16),
        row('Model', bms.modelName.isEmpty ? 'Unknown' : bms.modelName),
        row('Hardware', bms.hardwareVersion.isEmpty ? '—' : bms.hardwareVersion),
        row('Firmware', bms.softwareVersion.isEmpty ? '—' : bms.softwareVersion),
        row('Layout', bms.layout),
        row('Cells reported', '${bms.cellCountReported ?? c.samples.last.cellVoltagesV.length}'),
        row('Samples', '${c.samples.length}'),
        row('Raw frames', '${c.rawFrames.length}'),
        row('Payload size', '${c.encodedBytes()} bytes'),
        row('Serial number', c.redaction.serialNumber == 'shared' ? 'shared' : 'withheld'),
        const SizedBox(height: 24),
        // Opens the review screen (Phase 4); submit/export is the Phase 5 seam.
        FilledButton(
          onPressed: _onReviewPressed,
          child: const Text('Review & contribute'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _startScan,
          child: const Text('Capture again'),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _errorKind == BleScanFailureKind.bluetoothOff
                  ? Icons.bluetooth_disabled_rounded
                  : Icons.error_outline_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: _startScan, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
