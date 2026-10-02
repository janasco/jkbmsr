import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../models/cloud_history_point.dart';
import '../../utils/error_messages.dart';

class TelemetryHistoryScreen extends StatefulWidget {
  final String? deviceId;

  const TelemetryHistoryScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<TelemetryHistoryScreen> createState() => _TelemetryHistoryScreenState();
}

class _TelemetryHistoryScreenState extends State<TelemetryHistoryScreen> {
  final APIClient _apiClient = APIClient();
  bool _isLoading = true;
  bool _isExporting = false;
  String? _error;
  String? _resolvedDeviceId;
  int _selectedDays = 30;
  List<CloudHistoryPoint> _points = [];
  bool _downsampled = false;
  bool _fromCache = false;
  DateTime? _cachedAt;
  bool _cloudServiceRequired = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String? targetId = widget.deviceId ?? _resolvedDeviceId;
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

      final to = DateTime.now().toUtc();
      final from = to.subtract(Duration(days: _selectedDays));
      final result = await _apiClient.getTelemetryHistory(
        targetId,
        from: from.toIso8601String(),
        to: to.toIso8601String(),
      );

      setState(() {
        _points = result.points;
        _downsampled = result.downsampled;
        _fromCache = result.fromCache;
        _cachedAt = result.cachedAt;
        _cloudServiceRequired = false;
        _isLoading = false;
      });
    } on CloudServiceRequiredException {
      setState(() {
        _cloudServiceRequired = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      if (mounted) JKBMSRToast.show(context, _error ?? 'Failed to load history', isError: true);
    }
  }

  Future<void> _handleExport() async {
    final targetId = _resolvedDeviceId;
    if (targetId == null) return;

    setState(() {
      _isExporting = true;
    });
    try {
      final to = DateTime.now().toUtc();
      final from = to.subtract(Duration(days: _selectedDays));
      final result = await _apiClient.downloadTelemetryExportBytes(
        targetId,
        from: from.toIso8601String(),
        to: to.toIso8601String(),
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${result.filename}');
      await file.writeAsBytes(result.bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'JKBMSR telemetry export');
    } catch (e) {
      if (mounted) {
        JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  String _cacheAgeLabel(DateTime cachedAt) {
    final elapsed = DateTime.now().difference(cachedAt);
    if (elapsed.inMinutes < 1) return 'moments ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
    return '${elapsed.inDays}d ago';
  }

  List<FlSpot> _spots(List<double?> values) {
    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value != null) spots.add(FlSpot(i.toDouble(), value));
    }
    return spots;
  }

  Widget _chart(BuildContext context, String label, List<double?> values, Color color) {
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: JKBMSRTypography.label),
          const SizedBox(height: JKBMSRTokens.space8),
          SizedBox(
            height: 100,
            child: _spots(values).length < 2
                ? Center(child: Text('Not enough data', style: JKBMSRTypography.bodySecondary))
                : LineChart(
                    LineChartData(
                      lineBarsData: [
                        LineChartBarData(
                          spots: _spots(values),
                          isCurved: true,
                          color: color,
                          barWidth: 2,
                          dotData: const FlDotData(show: false),
                        ),
                      ],
                      titlesData: const FlTitlesData(show: false),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: RefreshIndicator(
        onRefresh: _loadHistory,
        color: context.colors.accent,
        backgroundColor: context.colors.panel,
        child: ListView(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          children: [
            JKBMSRBreadcrumb(
              paths: const ['Gateways', 'History'],
              onTap: (index) {
                if (index == 0) context.go('/devices');
              },
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Text('Cloud Service History', style: JKBMSRTypography.sectionHeading),
            const SizedBox(height: JKBMSRTokens.space12),
            if (_isLoading) ...[
              const JKBMSRSkeleton(height: 40, width: 240),
              const SizedBox(height: JKBMSRTokens.space16),
              const JKBMSRSkeleton(height: 200),
            ] else if (_cloudServiceRequired) ...[
              JKBMSREmptyState(
                icon: Icons.lock_outline,
                title: 'Cloud Service required',
                description: 'An active Cloud Service subscription is required to '
                    'browse historical data for this gateway. Cloud Service '
                    'subscriptions are managed on our website.',
              ),
            ] else if (_error != null && _points.isEmpty) ...[
              JKBMSREmptyState(
                icon: Icons.error_outline,
                title: 'Could not load history',
                description: _error!,
                action: OutlinedButton(
                  onPressed: _loadHistory,
                  child: const Text('Try Again'),
                ),
              ),
            ] else ...[
              JKBMSRSegmentedControl<int>(
                options: const {7: '7d', 30: '30d', 90: '90d', 365: '365d'},
                selectedValue: _selectedDays,
                onSelected: (days) {
                  setState(() {
                    _selectedDays = days;
                  });
                  _loadHistory();
                },
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space12, vertical: JKBMSRTokens.space8),
                decoration: BoxDecoration(
                  color: context.colors.inset,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                ),
                child: Text(
                  'Historical data is retained for 365 days — anything older is deleted automatically. '
                  'Export a CSV backup anytime using the button below.',
                  style: JKBMSRTypography.bodySecondary,
                ),
              ),
              if (_fromCache && _cachedAt != null) ...[
                const SizedBox(height: JKBMSRTokens.space8),
                Row(
                  children: [
                    Icon(Icons.cloud_off_outlined, size: 14, color: context.colors.textMuted),
                    const SizedBox(width: JKBMSRTokens.space4),
                    Text('Showing cached data from ${_cacheAgeLabel(_cachedAt!)}', style: JKBMSRTypography.label),
                  ],
                ),
              ],
              const SizedBox(height: JKBMSRTokens.space16),
              if (_points.isEmpty) ...[
                JKBMSREmptyState(
                  icon: Icons.show_chart,
                  title: 'No history in this range yet',
                  description: 'Telemetry will appear here once this gateway has reported for a while.',
                ),
              ] else ...[
                if (_downsampled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
                    child: Text('Showing averaged trend for readability', style: JKBMSRTypography.label),
                  ),
                _chart(context, 'Voltage (V)', _points.map((p) => p.voltage).toList(), context.colors.accent),
                const SizedBox(height: JKBMSRTokens.space12),
                _chart(context, 'Current (A)', _points.map((p) => p.current).toList(), context.colors.warning),
                const SizedBox(height: JKBMSRTokens.space12),
                _chart(context, 'State of Charge (%)', _points.map((p) => p.soc).toList(), context.colors.signal),
                const SizedBox(height: JKBMSRTokens.space12),
                _chart(context, 'Power (W)', _points.map((p) => p.power).toList(), context.colors.critical),
                const SizedBox(height: JKBMSRTokens.space16),
                _isExporting
                    ? const Center(child: CircularProgressIndicator())
                    : OutlinedButton.icon(
                        onPressed: () => unawaited(_handleExport()),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share CSV'),
                      ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
