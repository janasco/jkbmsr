import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../widgets/shared/design_system/animated_counter.dart';
import '../../services/api_client.dart';
import '../../models/device.dart';
import '../../models/telemetry.dart';
import '../../utils/error_messages.dart';
import '../../utils/haptics.dart';

/// Device comparison screen that shows multiple gateways side by side.
/// Useful for multi-gateway accounts to quickly compare battery states,
/// voltages, temperatures, and alerts across their fleet.
class DeviceComparisonScreen extends StatefulWidget {
  final List<String> deviceIds;

  const DeviceComparisonScreen({Key? key, required this.deviceIds}) : super(key: key);

  @override
  State<DeviceComparisonScreen> createState() => _DeviceComparisonScreenState();
}

class _DeviceComparisonScreenState extends State<DeviceComparisonScreen> {
  final APIClient _apiClient = APIClient();
  bool _isLoading = true;
  String? _error;
  List<DeviceWithTelemetry> _devices = [];
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait(
        widget.deviceIds.map((id) async {
          try {
            final details = await _apiClient.getDeviceDetails(id);
            return DeviceWithTelemetry(
              device: details['device'] as Device,
              telemetry: details['telemetry'] as Telemetry,
            );
          } catch (_) {
            return null;
          }
        }),
      );

      if (!mounted) return;
      setState(() {
        _devices = results.whereType<DeviceWithTelemetry>().toList();
        _isLoading = false;
      });

      // Start polling for updates
      _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _loadDevicesSilently();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDevicesSilently() async {
    try {
      final results = await Future.wait(
        widget.deviceIds.map((id) async {
          try {
            final details = await _apiClient.getDeviceDetails(id);
            return DeviceWithTelemetry(
              device: details['device'] as Device,
              telemetry: details['telemetry'] as Telemetry,
            );
          } catch (_) {
            return null;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _devices = results.whereType<DeviceWithTelemetry>().toList();
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: AppBar(
        title: Text('Compare Devices', style: JKBMSRTypography.sectionHeading),
        backgroundColor: context.colors.canvas,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.colors.textSecondary),
            tooltip: 'Refresh devices',
            onPressed: () {
              JKBMSRHaptics.lightImpact();
              _loadDevices();
            },
          ),
        ],
      ),
      body: _isLoading
          ? _buildComparisonSkeleton()
          : _error != null
              ? JKBMSREmptyState(
                  icon: Icons.error_outline,
                  title: 'Could not load devices',
                  description: _error!,
                  action: OutlinedButton(
                    onPressed: _loadDevices,
                    child: const Text('Try Again'),
                  ),
                )
              : _devices.isEmpty
                  ? const JKBMSREmptyState(
                      icon: Icons.devices_other,
                      title: 'No devices to compare',
                      description: 'Select at least two gateways to compare.',
                    )
                  : _buildComparisonView(),
    );
  }

  Widget _buildComparisonView() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _devices.map((item) => _buildDeviceColumn(item)).toList(),
      ),
    );
  }

  // Loading placeholder mirroring the real comparison layout: a horizontally
  // scrollable row of device-column cards (same 200dp width and spacing as
  // _buildDeviceColumn) so the content doesn't jump when the fetch lands.
  // Three columns is the typical comparison size; the loader is scrollable so
  // it matches the real row rather than clipping on a narrow phone.
  Widget _buildComparisonSkeleton() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(3, (_) => _buildDeviceColumnSkeleton()),
      ),
    );
  }

  Widget _buildDeviceColumnSkeleton() {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: JKBMSRTokens.space12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Name line + status badge.
              Row(
                children: const [
                  Expanded(child: JKBMSRSkeleton(height: 18)),
                  SizedBox(width: JKBMSRTokens.space8),
                  JKBMSRSkeleton(width: 56, height: 20, borderRadius: 999),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              // Four label/value metric blocks (SOC, Voltage, Current, Temp),
              // each mirroring a _ComparisonMetric.
              for (var i = 0; i < 4; i++) ...[
                const JKBMSRSkeleton(width: 48, height: 10),
                const SizedBox(height: 6),
                const JKBMSRSkeleton(width: 120, height: 18),
                const SizedBox(height: JKBMSRTokens.space8),
              ],
              const SizedBox(height: JKBMSRTokens.space4),
              // "View Dashboard" button.
              const JKBMSRSkeleton(height: 36),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceColumn(DeviceWithTelemetry item) {
    final device = item.device;
    final t = item.telemetry;
    final soc = t.soc;
    final socColor = soc < 20
        ? context.colors.critical
        : soc < 50
            ? context.colors.warning
            : context.colors.accent;

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: JKBMSRTokens.space12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device name and status
              Row(
                children: [
                  Expanded(
                    child: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.cardHeading,
                    ),
                  ),
                  JKBMSRStatusBadge(
                    status: device.status.toLowerCase() == 'online'
                        ? JKBMSRStatus.online
                        : JKBMSRStatus.offline,
                  ),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),

              // SOC
              _ComparisonMetric(
                label: 'SOC',
                child: JKBMSRAnimatedCounter(
                  value: soc,
                  decimalPlaces: 0,
                  suffix: '%',
                  color: socColor,
                  style: JKBMSRTypography.pageHeading.copyWith(color: socColor),
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),

              // Voltage
              _ComparisonMetric(
                label: 'Voltage',
                child: JKBMSRAnimatedCounterCompact(
                  value: t.voltage,
                  suffix: ' V',
                  decimalPlaces: 2,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),

              // Current
              _ComparisonMetric(
                label: 'Current',
                child: JKBMSRAnimatedCounterCompact(
                  value: t.current,
                  suffix: ' A',
                  decimalPlaces: 1,
                  color: t.current > 0.05
                      ? context.colors.accent
                      : t.current < -0.05
                          ? context.colors.signal
                          : context.colors.textMuted,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),

              // Temperature
              _ComparisonMetric(
                label: 'Temp',
                child: JKBMSRAnimatedCounterCompact(
                  value: [t.temperature1, t.temperature2, t.bms.mosfetTemperature]
                      .reduce((a, b) => a > b ? a : b),
                  suffix: '°C',
                  decimalPlaces: 1,
                  color: t.temperature1 > 50 ? context.colors.critical : null,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),

              // Cell imbalance
              _ComparisonMetric(
                label: 'Imbalance',
                child: Text(
                  '${((t.bms.deltaCellVoltage) * 1000).round()} mV',
                  style: JKBMSRTypography.monoTechnical.copyWith(
                    color: t.bms.deltaCellVoltage > 0.03
                        ? context.colors.warning
                        : context.colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space12),

              // View button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    JKBMSRHaptics.lightImpact();
                    context.push('/dashboard?deviceId=${Uri.encodeComponent(device.id)}');
                  },
                  child: const Text('View Dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComparisonMetric extends StatelessWidget {
  final String label;
  final Widget child;

  const _ComparisonMetric({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, fontSize: 11.0),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
  }
}

class DeviceWithTelemetry {
  final Device device;
  final Telemetry telemetry;

  const DeviceWithTelemetry({required this.device, required this.telemetry});
}
