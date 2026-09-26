import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../widgets/shared/design_system/cell_voltage_grid.dart';
import '../../services/api_client.dart';
import '../../models/telemetry.dart';
import '../../utils/error_messages.dart';

const _kMinPollInterval = Duration(seconds: 5);

class CellVoltagesScreen extends StatefulWidget {
  final String? deviceId;

  const CellVoltagesScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<CellVoltagesScreen> createState() => _CellVoltagesScreenState();
}

class _CellVoltagesScreenState extends State<CellVoltagesScreen> with WidgetsBindingObserver {
  final APIClient _apiClient = APIClient();
  bool _isLoading = true;
  List<CellVoltage> _cells = [];
  String? _error;
  String? _resolvedDeviceId;
  Timer? _pollTimer;
  bool _batteryAnimationsEnabled = true;

  double _current = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCellData();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Pause polling while backgrounded (timers aren't reliable there anyway)
  // and catch up with an immediate silent refresh on return, rather than
  // waiting out whatever's left of the last poll interval.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (_resolvedDeviceId != null) {
        _loadCellData(silent: true);
      }
    }
  }

  // Keeps cell readings close to real-time without hammering the API faster
  // than the gateway actually reports: polls at the device's own entitled
  // telemetry interval (server-resolved from its Cloud Service tier, not
  // user-settable), not a fixed guess.
  Future<void> _schedulePolling(String deviceId) async {
    if (_pollTimer != null) return;
    var intervalSeconds = 30;
    try {
      final config = await _apiClient.getDeviceConfig(deviceId);
      intervalSeconds = (config['telemetryIntervalSeconds'] as num? ?? 30).toInt();
      final animationsEnabled = config['batteryAnimationsEnabled'] as bool? ?? true;
      if (mounted) {
        setState(() => _batteryAnimationsEnabled = animationsEnabled);
      }
    } catch (_) {
      // Fall back to the default interval; a silent refresh failure here
      // shouldn't block the screen the user is already looking at.
    }
    final interval = Duration(seconds: intervalSeconds);
    _pollTimer = Timer.periodic(
      interval < _kMinPollInterval ? _kMinPollInterval : interval,
      (_) => _loadCellData(silent: true),
    );
  }

  Future<void> _loadCellData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      String? targetId = widget.deviceId ?? _resolvedDeviceId;

      // If no deviceId is provided, get the first device from the list
      if (targetId == null || targetId.isEmpty) {
        final devices = await _apiClient.getDevices();
        if (devices.isNotEmpty) {
          targetId = devices.first.id;
        } else {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }
      _resolvedDeviceId = targetId;

      final details = await _apiClient.getDeviceDetails(targetId);
      final telemetry = details['telemetry'] as Telemetry;

      setState(() {
        _cells = telemetry.cells;
        _current = telemetry.current;
        _isLoading = false;
      });

      unawaited(_schedulePolling(targetId));
    } catch (e) {
      if (silent) return; // don't surface a toast for a background refresh
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load cells', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: RefreshIndicator(
        onRefresh: _loadCellData,
        color: context.colors.accent,
        backgroundColor: context.colors.panel,
        child: ListView(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          children: [
            if (_isLoading) ...[
              const JKBMSRSkeleton(height: 80),
              const SizedBox(height: JKBMSRTokens.space16),
              const JKBMSRSkeleton(height: 40, width: 200),
              const SizedBox(height: JKBMSRTokens.space16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: JKBMSRTokens.space12,
                  mainAxisSpacing: JKBMSRTokens.space12,
                  childAspectRatio: 2.8,
                ),
                itemCount: 8,
                itemBuilder: (context, index) => const JKBMSRSkeleton(height: 60),
              )
            ] else if (_error != null && _cells.isEmpty) ...[
              JKBMSREmptyState(
                icon: Icons.error_outline,
                title: 'Could not load cell voltages',
                description: _error!,
                action: OutlinedButton(
                  onPressed: _loadCellData,
                  child: const Text('Try Again'),
                ),
              )
            ] else if (_cells.isEmpty) ...[
              const JKBMSREmptyState(
                icon: Icons.battery_alert_outlined,
                title: 'No cell telemetry data',
                description: 'Gateway telemetry data is not currently returning cell voltage information.',
              )
            ] else ...[
              Text('Individual Cell Voltages', style: JKBMSRTypography.cardHeading),
              const SizedBox(height: JKBMSRTokens.space12),
              JKBMSRCellVoltageGrid(
                cells: _cells,
                isCharging: _current > 0.05,
                isDischarging: _current < -0.05,
                animationsEnabled: _batteryAnimationsEnabled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
