import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import 'discovered_gateway.dart';
import 'gateway_scan_source.dart';
import 'gateway_setup_flow.dart';
import 'widgets/detected_gateway_tile.dart';
import 'widgets/radar_pulse.dart';

/// Finding an unconfigured gateway.
///
/// Only a gateway that is **not** configured advertises its setup service, so
/// this screen never has to explain which of the results is the new one: every
/// result is a gateway that wants setting up.
class GatewayScanScreen extends StatefulWidget {
  const GatewayScanScreen({
    super.key,
    this.scanSource,
    this.emptyAfter = const Duration(seconds: 20),
  });

  /// Injected in tests, and the seam the radio plugs into. Defaults to a source
  /// that reports the BLE stack as unavailable rather than pretending the room
  /// is empty.
  final GatewayScanSource? scanSource;

  /// How long to look before saying nothing was found. Injectable because a
  /// test that waits twenty real seconds is a test nobody runs.
  final Duration emptyAfter;

  @override
  State<GatewayScanScreen> createState() => _GatewayScanScreenState();
}

class _GatewayScanScreenState extends State<GatewayScanScreen> {
  late final GatewayScanSource _source =
      widget.scanSource ?? UnavailableGatewayScanSource();
  late final bool _ownsSource = widget.scanSource == null;

  StreamSubscription<List<DiscoveredGateway>>? _subscription;
  Timer? _emptyTimer;

  List<DiscoveredGateway> _gateways = const [];
  ScanFailure? _failure;
  bool _scanning = false;
  bool _nothingFound = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _emptyTimer?.cancel();
    _subscription?.cancel();
    _source.stop();
    if (_ownsSource) _source.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _emptyTimer?.cancel();
    // Not awaited: cancelling the previous subscription does not have to finish
    // before a new scan begins, and awaiting it delayed the restart by a
    // scheduling turn that is invisible in production and fatal to a test.
    _subscription?.cancel();
    _subscription = null;
    setState(() {
      _failure = null;
      _scanning = true;
      _nothingFound = false;
      _gateways = const [];
    });

    _subscription = _source.results.listen((gateways) {
      if (!mounted) return;
      setState(() {
        _gateways = gateways;
        if (gateways.isNotEmpty) _nothingFound = false;
      });
    });

    final failure = await _source.start();
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _failure = failure;
        _scanning = false;
      });
      return;
    }

    _emptyTimer = Timer(widget.emptyAfter, () async {
      if (!mounted || _gateways.isNotEmpty) return;
      await _source.stop();
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _nothingFound = true;
      });
    });
  }

  void _openSetup(DiscoveredGateway gateway) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GatewaySetupFlow(gateway: gateway),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a gateway'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            JKBMSRTokens.space24,
            JKBMSRTokens.space8,
            JKBMSRTokens.space24,
            JKBMSRTokens.space24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _headline,
                style: text.displayMedium?.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Text(
                _subline,
                style: text.bodyMedium?.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              SizedBox(
                height: 340,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Semantics(
                      label: _scanning
                          ? 'Scanning for a nearby gateway'
                          : 'Scanner idle',
                      child: RadarPulse(
                        active: _scanning,
                        size: 300,
                        child: Icon(
                          Icons.bluetooth_searching,
                          size: 44,
                          color: colors.accent,
                        ),
                      ),
                    ),
                    if (_gateways.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Column(
                          children: [
                            for (final gateway in _gateways)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: DetectedGatewayTile(
                                  gateway: gateway,
                                  onTap: () => _openSetup(gateway),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              _StatusBlock(
                scanning: _scanning,
                failure: _failure,
                nothingFound: _nothingFound,
              ),
              if (_failure == ScanFailure.bluetoothOff ||
                  _failure == ScanFailure.permissionDenied) ...[
                const SizedBox(height: JKBMSRTokens.space16),
                FilledButton(
                  onPressed: _start,
                  child: const Text('Try again'),
                ),
              ],
              if (_nothingFound) ...[
                const SizedBox(height: JKBMSRTokens.space16),
                OutlinedButton(
                  onPressed: _start,
                  child: const Text('Scan again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _headline {
    if (_failure == ScanFailure.unsupported) return 'Bluetooth setup is not ready';
    if (_gateways.isNotEmpty) return 'Gateway found';
    if (_nothingFound) return 'No gateway found';
    return 'Looking for a gateway';
  }

  String get _subline {
    if (_failure == ScanFailure.unsupported) {
      return 'This build cannot find a gateway over Bluetooth yet. Use the setup portal for now.';
    }
    if (_failure == ScanFailure.bluetoothOff) {
      return 'Bluetooth is off. Turn it on in Android settings, then try again.';
    }
    if (_failure == ScanFailure.permissionDenied) {
      return 'JK BMS Remote needs Bluetooth permission to find your gateway. Allow it when Android asks.';
    }
    if (_gateways.isNotEmpty) {
      return 'Tap the gateway you want to set up.';
    }
    if (_nothingFound) {
      return 'Check that the gateway is powered on. Only a gateway that has never been set up appears here.';
    }
    return 'Keep the gateway close and powered on. Nothing else is needed.';
  }
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    required this.scanning,
    required this.failure,
    required this.nothingFound,
  });

  final bool scanning;
  final ScanFailure? failure;
  final bool nothingFound;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;
    if (failure != null || nothingFound || scanning) return const SizedBox.shrink();

    return Row(
      children: [
        Icon(Icons.lightbulb_outline, size: 18, color: colors.textSubtle),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(
          child: Text(
            'The setup service switches off once the gateway is connected, so a gateway already on Wi-Fi will not appear here.',
            style: text.bodySmall?.copyWith(color: colors.textSubtle),
          ),
        ),
      ],
    );
  }
}
