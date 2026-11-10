import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../models/alert.dart';
import '../../models/ble_history_event.dart';
import '../../models/device.dart';
import '../../models/ota_event.dart';
import '../../models/telemetry.dart';
import '../../utils/error_messages.dart';
import '../../utils/haptics.dart';
import 'event_log.dart';
import 'event_log_timeline.dart';
import 'pack_check.dart';
import 'pack_check_card.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final APIClient _apiClient = APIClient();
  static const int _pageSize = 20;

  int _selectedTab = 0; // 0 = Active, 1 = Event log
  DateTime? _selectedDate;
  String _severityFilter = 'all'; // 'all', 'critical', 'warning'
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _error;
  List<Alert> _activeAlerts = [];
  bool _clearingAll = false;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  // The Event log merges three independent sources into one timeline. Each is
  // fetched separately so one failure narrows the log instead of emptying it;
  // `_eventLogFailures` names whatever could not be read.
  bool _eventLogLoaded = false;
  bool _isEventLogLoading = true;
  bool _isEventLogLoadingMore = false;
  List<EventLogEntry> _eventLog = [];
  List<String> _eventLogFailures = [];
  List<Alert> _resolvedAlerts = [];
  List<BleSessionRecord> _bleSessions = [];
  List<OtaEventRecord> _otaEvents = [];
  bool _eventLogHasMoreAlerts = false;

  // The pack check is additive chrome at the top of the Active tab. Its own
  // fetch is kept separate from the alert fetch so a slow telemetry call can
  // never delay or replace the alarm list.
  bool _packCheckLoading = true;
  PackCheckReport? _packCheckReport;

  // History deletion (permanent — distinct from resolve). `_deletingAlertId`
  // disables that row's button while in flight; `_deletingAllHistory` covers
  // the bulk action.
  String? _deletingAlertId;
  bool _deletingAllHistory = false;

  @override
  void initState() {
    super.initState();
    _loadActiveAlerts();
    unawaited(_loadPackCheck());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadActiveAlerts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _apiClient.getAlerts(status: 'active', limit: 50);
      setState(() {
        _activeAlerts = result.alerts;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load alerts', isError: true);
    }
  }

  // Reads each gateway's latest telemetry and reduces it to the card's plain
  // findings. A per-gateway failure is isolated: the other gateways still get
  // checked, and the card says the readings could not be loaded rather than
  // claiming a healthy pack.
  Future<void> _loadPackCheck() async {
    if (!_packCheckLoading) {
      setState(() => _packCheckLoading = true);
    }
    try {
      final devices = await _apiClient.getDevices();
      final inputs = <PackCheckInput>[];
      var failed = 0;

      for (final device in devices) {
        try {
          final details = await _apiClient.getDeviceDetails(device.id);
          final telemetry = details['telemetry'] as Telemetry?;
          if (telemetry == null) {
            failed++;
            continue;
          }
          inputs.add(_packCheckInputFor(device, telemetry));
        } catch (_) {
          failed++;
        }
      }

      PackCheckReport report;
      if (inputs.isEmpty && devices.isNotEmpty) {
        report = PackCheckReport.noData(
          failed == devices.length
              ? (devices.length == 1
                  ? 'The latest readings could not be loaded from this gateway.'
                  : 'The latest readings could not be loaded from these gateways.')
              : 'The latest readings did not include enough values to check.',
        );
      } else {
        report = evaluatePackCheck(
          inputs,
          coverageNote: failed == 0
              ? null
              : '$failed of ${devices.length} gateways could not be read.',
        );
      }

      if (!mounted) return;
      setState(() {
        _packCheckReport = report;
        _packCheckLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _packCheckReport = const PackCheckReport.noData(
          'The latest readings could not be loaded.',
        );
        _packCheckLoading = false;
      });
    }
  }

  PackCheckInput _packCheckInputFor(Device device, Telemetry telemetry) {
    // Same no-data signal the dashboard uses: the API sends voltage/SOC as 0
    // when no telemetry row exists, and a real connected pack never sits at
    // exactly 0 V.
    final hasTelemetry = telemetry.voltage > 0.5 || telemetry.soc > 0;
    final link = telemetry.linkDiagnostics;

    return PackCheckInput(
      deviceName: device.name,
      hasTelemetry: hasTelemetry,
      cellVoltages: hasTelemetry
          ? [for (final cell in telemetry.cells) cell.voltage]
          : const [],
      temperature1C: telemetry.temperature1,
      temperature2C: telemetry.temperature2,
      socPercent: hasTelemetry ? telemetry.soc : null,
      currentAmps: hasTelemetry ? telemetry.current : null,
      fullCapacityAh:
          telemetry.bms.fullCapacityAh > 0 ? telemetry.bms.fullCapacityAh : null,
      isCharging: telemetry.bms.charging,
      isDischarging: telemetry.bms.discharging,
      bmsLinkUp: link.bmsLinkUp,
      secondsSinceLastTelemetry: device.secondsSinceLastTelemetry,
      expectedIntervalSeconds: device.expectedIntervalSeconds,
    );
  }

  // Fetches all three sources independently. A failed source becomes a stated
  // gap in the log rather than an empty screen, and a failed gateway only
  // removes that gateway's rows.
  Future<void> _loadEventLog({bool refresh = false}) async {
    setState(() {
      _isEventLogLoading = true;
      _eventLogFailures = const [];
      if (refresh) {
        _eventLog = const [];
        _resolvedAlerts = const [];
        _bleSessions = const [];
        _otaEvents = const [];
        _eventLogLoaded = false;
      }
    });

    final failures = <String>[];
    var alerts = <Alert>[];
    var hasMoreAlerts = false;
    var bleSessions = <BleSessionRecord>[];
    var otaEvents = <OtaEventRecord>[];

    try {
      final result = await _apiClient.getAlerts(
        status: 'resolved',
        limit: _pageSize,
        offset: 0,
      );
      alerts = result.alerts;
      hasMoreAlerts = result.hasMore;
    } catch (e) {
      failures.add(
          'Resolved alerts could not be read: ${friendlyErrorMessage(e)}');
    }

    List<Device>? devices;
    try {
      devices = await _apiClient.getDevices();
    } catch (e) {
      final reason = friendlyErrorMessage(e);
      // Both per-gateway sources are unreadable without the device list, so
      // say so for each rather than reporting one vague failure.
      failures.add('Gateway connections could not be read: $reason');
      failures.add('Firmware update events could not be read: $reason');
    }

    if (devices != null) {
      var bleFailures = 0;
      var otaFailures = 0;
      String? bleReason;
      String? otaReason;

      final results = await Future.wait(devices.map((device) async {
        List<BleHistoryEvent>? ble;
        List<OtaEvent>? ota;
        String? bleError;
        String? otaError;
        try {
          ble = await _apiClient.getBleHistory(device.id);
        } catch (e) {
          bleError = friendlyErrorMessage(e);
        }
        try {
          ota = await _apiClient.getOtaHistory(device.id);
        } catch (e) {
          otaError = friendlyErrorMessage(e);
        }
        return (
          device: device,
          ble: ble,
          bleError: bleError,
          ota: ota,
          otaError: otaError,
        );
      }));

      for (final result in results) {
        final ble = result.ble;
        if (ble == null) {
          bleFailures++;
          bleReason ??= result.bleError;
        } else {
          for (final event in ble) {
            bleSessions.add(BleSessionRecord(
              deviceId: result.device.id,
              deviceName: result.device.name,
              event: event,
            ));
          }
        }

        final ota = result.ota;
        if (ota == null) {
          otaFailures++;
          otaReason ??= result.otaError;
        } else {
          for (final event in ota) {
            otaEvents.add(OtaEventRecord(
              deviceId: result.device.id,
              deviceName: result.device.name,
              event: event,
            ));
          }
        }
      }

      if (bleFailures > 0) {
        failures.add(_sourceFailure(
            'Gateway connections', bleFailures, devices.length, bleReason));
      }
      if (otaFailures > 0) {
        failures.add(_sourceFailure(
            'Firmware update events', otaFailures, devices.length, otaReason));
      }
    }

    if (!mounted) return;
    setState(() {
      _resolvedAlerts = alerts;
      _bleSessions = bleSessions;
      _otaEvents = otaEvents;
      _eventLogHasMoreAlerts = hasMoreAlerts;
      _eventLogFailures = failures;
      _eventLog = buildEventLog(
        resolvedAlerts: alerts,
        bleSessions: bleSessions,
        otaEvents: otaEvents,
      );
      _eventLogLoaded = true;
      _isEventLogLoading = false;
    });
  }

  String _sourceFailure(
      String label, int failed, int total, String? reason) {
    final scope = total > 1 ? ' from $failed of $total gateways' : '';
    final detail = reason == null ? '' : ' $reason';
    return '$label could not be read$scope.$detail';
  }

  // Only the alert source is paged; the label says so rather than implying
  // the whole log has been fetched.
  Future<void> _loadMoreEventLogAlerts() async {
    if (_isEventLogLoadingMore || !_eventLogHasMoreAlerts) return;
    setState(() => _isEventLogLoadingMore = true);

    try {
      final result = await _apiClient.getAlerts(
        status: 'resolved',
        limit: _pageSize,
        offset: _resolvedAlerts.length,
      );
      if (!mounted) return;
      setState(() {
        _resolvedAlerts = [..._resolvedAlerts, ...result.alerts];
        _eventLogHasMoreAlerts = result.hasMore;
        _eventLog = buildEventLog(
          resolvedAlerts: _resolvedAlerts,
          bleSessions: _bleSessions,
          otaEvents: _otaEvents,
        );
        _isEventLogLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isEventLogLoadingMore = false);
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedTab = index;
    });
    if (index == 1 && !_eventLogLoaded) {
      _loadEventLog();
    }
  }

  JKBMSRStatus _mapSeverity(String severityStr) {
    switch (severityStr.toLowerCase()) {
      case 'critical':
        return JKBMSRStatus.critical;
      case 'warning':
        return JKBMSRStatus.warning;
      default:
        return JKBMSRStatus.offline;
    }
  }

  List<Alert> _getFilteredActiveAlerts() {
    var filtered = _activeAlerts;

    if (_severityFilter != 'all') {
      filtered = filtered.where((a) => a.severity.toLowerCase() == _severityFilter).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered
          .where((a) => a.message.toLowerCase().contains(q) || a.deviceName.toLowerCase().contains(q))
          .toList();
    }

    if (_selectedDate != null) {
      final dateStr =
          "${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}";
      filtered = filtered.where((alert) => alert.createdAt.contains(dateStr)).toList();
    }

    return filtered;
  }

  // Real server acknowledge: POST /alerts/:id/resolve (jkbmsr-api
  // dashboard.ts). Optimistic — the alert vanishes instantly — but rolled
  // back with an error toast if the server rejects it, so a swipe can't
  // silently lose an alert that's still active server-side.
  Future<void> _acknowledgeAlert(Alert alert) async {
    JKBMSRHaptics.mediumImpact();
    final index = _activeAlerts.indexWhere((a) => a.id == alert.id);
    if (index == -1) return;
    setState(() {
      _activeAlerts.removeAt(index);
    });
    try {
      await _apiClient.resolveAlert(alert.id);
      if (mounted) {
        JKBMSRToast.show(context, 'Alert acknowledged');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _activeAlerts.insert(index.clamp(0, _activeAlerts.length), alert);
      });
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all alarms?'),
        content: const Text(
            'Mark every active alarm across your gateways as resolved. This cannot be undone from the app.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear all')),
        ],
      ),
    );
    if (confirmed == true) await _clearAllAlarms();
  }

  Future<void> _clearAllAlarms() async {
    setState(() => _clearingAll = true);
    try {
      final count = await _apiClient.resolveAllAlerts();
      await _loadActiveAlerts();
      if (!mounted) return;
      JKBMSRToast.show(
        context,
        count > 0
            ? 'Cleared $count alarm${count == 1 ? '' : 's'}.'
            : 'No active alarms to clear.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  Future<void> _confirmClearGateway(String deviceId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear alarms for $name?'),
        content: const Text('Mark all active alarms for this gateway as resolved.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Clear')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _clearingAll = true);
    try {
      final count = await _apiClient.resolveAllAlerts(deviceId: deviceId);
      await _loadActiveAlerts();
      if (!mounted) return;
      JKBMSRToast.show(
        context,
        count > 0
            ? 'Cleared $count alarm${count == 1 ? '' : 's'} for $name.'
            : 'No active alarms for $name.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  Future<void> _resolveSelected() async {
    if (_selected.isEmpty) return;
    setState(() => _clearingAll = true);
    try {
      var resolved = 0;
      for (final id in _selected.toList()) {
        await _apiClient.resolveAlert(id);
        resolved++;
      }
      _selected.clear();
      _selectionMode = false;
      await _loadActiveAlerts();
      if (!mounted) return;
      JKBMSRToast.show(
          context, 'Resolved $resolved alarm${resolved == 1 ? '' : 's'}.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _clearingAll = false);
    }
  }

  // Permanently removes one resolved alert. Deliberately separate from the
  // resolve flow: resolving only clears the active alarm, deleting destroys the
  // history record, so both the affordance and the confirmation say so.
  void _confirmDeleteAlert(Alert alert) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteHistoryDialog(
        title: 'Delete this alert permanently?',
        message:
            'This removes it from your alert history for good. Unlike resolving an alarm, deleting cannot be undone or recovered.',
        confirmText: 'Delete',
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    ).then((confirmed) {
      if (confirmed == true) _deleteAlert(alert);
    });
  }

  Future<void> _deleteAlert(Alert alert) async {
    setState(() => _deletingAlertId = alert.id);
    try {
      await _apiClient.deleteAlert(alert.id);
      await _loadEventLog(refresh: true);
      if (!mounted) return;
      JKBMSRToast.show(context, 'Alert deleted');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _deletingAlertId = null);
    }
  }

  Future<void> _confirmDeleteAllHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteHistoryDialog(
        title: 'Delete all alert history?',
        message:
            'Permanently remove every resolved alert from the event log. Gateway connections and firmware events are kept. This cannot be undone; active alarms are not affected.',
        confirmText: 'Delete all',
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (confirmed == true) await _deleteAllHistory();
  }

  Future<void> _deleteAllHistory() async {
    setState(() => _deletingAllHistory = true);
    try {
      final count = await _apiClient.deleteResolvedAlerts();
      await _loadEventLog(refresh: true);
      if (!mounted) return;
      JKBMSRToast.show(
        context,
        count > 0
            ? 'Deleted $count resolved alert${count == 1 ? '' : 's'}.'
            : 'No alert history to delete.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _deletingAllHistory = false);
    }
  }

  Widget _buildSummaryHeader() {    final criticalCount = _activeAlerts.where((a) => a.severity.toLowerCase() == 'critical').length;
    final warningCount = _activeAlerts.where((a) => a.severity.toLowerCase() == 'warning').length;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        JKBMSRTokens.space16,
        JKBMSRTokens.space12,
        JKBMSRTokens.space16,
        JKBMSRTokens.space4,
      ),
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        children: [
          // The three pills sit in a fixed row; at large OS text scales they
          // outgrow a narrow phone, so scale the row down to fit rather than
          // overflowing (a no-op at the default scale). Each pill carries its
          // own horizontal padding so the labels never touch the dividers (or
          // each other) once `scaleDown` has removed the free space that
          // `spaceAround` would otherwise distribute.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryPill('Active Alarms', '${_activeAlerts.length}', context.colors.textPrimary,
                    key: const ValueKey('alerts-summary-active')),
                Container(width: 1, height: 28, color: context.colors.line),
                _buildSummaryPill('Critical', '$criticalCount', context.colors.critical,
                    key: const ValueKey('alerts-summary-critical')),
                Container(width: 1, height: 28, color: context.colors.line),
                _buildSummaryPill('Warnings', '$warningCount', context.colors.warning,
                    key: const ValueKey('alerts-summary-warnings')),
              ],
            ),
          ),
          if (_activeAlerts.isNotEmpty) ...[
            const SizedBox(height: JKBMSRTokens.space8),
            if (_selectionMode)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _selected.isEmpty || _clearingAll
                        ? null
                        : _resolveSelected,
                    icon: const Icon(Icons.done_all, size: 18),
                    label: Text('Resolve selected (${_selected.length})'),
                  ),
                  TextButton(
                    onPressed: _clearingAll
                        ? null
                        : () => setState(() {
                              _selectionMode = false;
                              _selected.clear();
                            }),
                    child: const Text('Cancel'),
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: JKBMSRTokens.space8,
                runSpacing: JKBMSRTokens.space4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _clearingAll ? null : _confirmClearAll,
                    icon: _clearingAll
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.done_all, size: 18),
                    label: const Text('Clear all alarms'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectionMode = true),
                    child: const Text('Select'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryPill(String label, String value, Color color, {Key? key}) {
    return Padding(
      key: key,
      // Horizontal breathing room around each pill. The row sits in a
      // FittedBox, so the separator line and its neighbours would otherwise be
      // flush; the padding scales down with the row at large text scales.
      padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space12),
      child: Column(
        children: [
          Text(label, style: JKBMSRTypography.label.copyWith(fontSize: 11.0)),
          const SizedBox(height: JKBMSRTokens.space2),
          Text(
            value,
            style: JKBMSRTypography.monoTechnical.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(BuildContext context, Alert alert) {
    final isCritical = alert.severity.toLowerCase() == 'critical';
    final accentColor = alert.isResolved
        ? context.colors.accent
        : isCritical
            ? context.colors.critical
            : context.colors.warning;

    // Only allow swiping on unresolved alerts
    if (alert.isResolved) {
      return _buildAlertCardContent(context, alert, isCritical, accentColor);
    }

    return Dismissible(
      key: Key('alert_${alert.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        // Show confirmation dialog
        return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Acknowledge Alert'),
            content: Text('Dismiss alert: ${alert.message}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Acknowledge'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        _acknowledgeAlert(alert);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: JKBMSRTokens.space24),
        decoration: BoxDecoration(
          color: context.colors.accent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Icon(Icons.check_circle_outline, color: context.colors.accent),
            const SizedBox(width: JKBMSRTokens.space8),
            Text(
              'Acknowledge',
              style: JKBMSRTypography.body.copyWith(color: context.colors.accent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      child: _buildAlertCardContent(context, alert, isCritical, accentColor),
    );
  }

  Widget _buildAlertCardContent(
    BuildContext context,
    Alert alert,
    bool isCritical,
    Color accentColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: accentColor.withValues(alpha: 0.35)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        child: Container(
          decoration: BoxDecoration(
            color: context.colors.panel,
            border: Border(left: BorderSide(color: accentColor, width: 4.5)),
          ),
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      alert.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.cardHeading.copyWith(
                        color: isCritical ? context.colors.critical : context.colors.textPrimary,
                        fontSize: 15.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: JKBMSRTokens.space8),
                  JKBMSRStatusBadge(status: _mapSeverity(alert.severity)),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Row(
                children: [
                  Icon(Icons.router, size: 14, color: context.colors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Gateway: ${alert.deviceName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.body.copyWith(
                        color: context.colors.textMuted,
                        fontSize: 13.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      'ID: #${alert.id}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.monoTechnical.copyWith(fontSize: 12.0, color: context.colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: JKBMSRTokens.space8),
                  Flexible(
                    child: Text(
                      alert.isResolved && alert.resolvedAt != null
                          ? 'Resolved ${alert.resolvedAt}'
                          : alert.createdAt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: JKBMSRTypography.label,
                    ),
                  ),
                ],
              ),
              if (!alert.isResolved) ...[
                const SizedBox(height: JKBMSRTokens.space12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: () => _acknowledgeAlert(alert),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Acknowledge'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: Column(
        children: [
          JKBMSRTabs(
            tabTitles: const ['Active Alarms', 'Event log'],
            selectedIndex: _selectedTab,
            onTabSelected: _onTabSelected,
          ),
          Expanded(
            child: _selectedTab == 0 ? _buildActiveTab(context) : _buildEventLogTab(context),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTab(BuildContext context) {
    final filteredAlerts = _getFilteredActiveAlerts();
    // Group by gateway: sort by gateway name so each gateway's alerts are
    // contiguous, then draw a section header when the gateway changes.
    final displayAlerts = [...filteredAlerts]
      ..sort((a, b) =>
          a.deviceName.toLowerCase().compareTo(b.deviceName.toLowerCase()));

    // The pack card and the search/filter row live in the same scroll view as
    // the alert rows. At large OS text scales the three together are taller
    // than a phone, so keeping them as a fixed header would push the alert
    // list off-screen; scrolling them keeps every control reachable without
    // hiding anything.
    return RefreshIndicator(
      onRefresh: () async {
        JKBMSRHaptics.mediumImpact();
        await Future.wait<void>([
          _loadActiveAlerts(),
          _loadPackCheck(),
        ]);
      },
      color: context.colors.accent,
      backgroundColor: context.colors.panel,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: PackCheckCard(
              report: _packCheckReport,
              isLoading: _packCheckLoading,
            ),
          ),
          if (!_isLoading && _error == null)
            SliverToBoxAdapter(child: _buildSummaryHeader()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: JKBMSRTokens.space16,
                vertical: JKBMSRTokens.space8,
              ),
              child: Column(
                children: [
                  // Search input
                  TextField(
                    controller: _searchController,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    decoration: InputDecoration(
                      hintText: 'Search alerts by message or gateway...',
                      prefixIcon:
                          Icon(Icons.search, color: context.colors.textMuted),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: context.colors.textMuted),
                              tooltip: 'Clear search',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: JKBMSRTokens.space8),
                  // Filter bar
                  Row(
                    children: [
                      Expanded(
                        child: JKBMSRSegmentedControl<String>(
                          options: const {
                            'all': 'All',
                            'critical': 'Critical',
                            'warning': 'Warning',
                          },
                          selectedValue: _severityFilter,
                          onSelected: (val) =>
                              setState(() => _severityFilter = val),
                        ),
                      ),
                      if (_selectedDate != null) ...[
                        const SizedBox(width: JKBMSRTokens.space8),
                        IconButton(
                          onPressed: () =>
                              setState(() => _selectedDate = null),
                          icon: Icon(Icons.calendar_today,
                              color: context.colors.accent),
                          tooltip: 'Clear date filter',
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => const Padding(
                    padding: EdgeInsets.only(bottom: JKBMSRTokens.space12),
                    child: _AlertCardSkeleton(),
                  ),
                  childCount: 3,
                ),
              ),
            )
          else if (_error != null && _activeAlerts.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: JKBMSREmptyState(
                icon: Icons.error_outline,
                title: 'Could not load alerts',
                description: _error!,
                action: OutlinedButton(
                  onPressed: _loadActiveAlerts,
                  child: const Text('Try Again'),
                ),
              ),
            )
          else if (filteredAlerts.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: JKBMSREmptyState(
                icon: Icons.notifications_off_outlined,
                title: 'No active alarms',
                description:
                    'All battery systems are operating within normal parameters.',
              ),
            )
          else
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final alert = displayAlerts[index];
                    final showHeader = index == 0 ||
                        displayAlerts[index - 1].deviceName != alert.deviceName;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showHeader)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 6),
                            child: Row(
                              children: [
                                Icon(Icons.dns_outlined,
                                    size: 14, color: context.colors.textMuted),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    alert.deviceName,
                                    style: JKBMSRTypography.label
                                        .copyWith(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (alert.deviceId.isNotEmpty)
                                  TextButton(
                                    onPressed: _clearingAll
                                        ? null
                                        : () => _confirmClearGateway(
                                            alert.deviceId, alert.deviceName),
                                    child: const Text('Clear'),
                                  ),
                              ],
                            ),
                          ),
                        if (_selectionMode)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Checkbox(
                                value: _selected.contains(alert.id),
                                onChanged: (_) => _toggleSelected(alert.id),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => _toggleSelected(alert.id),
                                  child: AbsorbPointer(
                                    child: _buildAlertCard(context, alert),
                                  ),
                                ),
                              ),
                            ],
                          )
                        else
                          _buildAlertCard(context, alert),
                      ],
                    );
                  },
                  childCount: displayAlerts.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEventLogTab(BuildContext context) {
    if (_isEventLogLoading && !_eventLogLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        itemCount: 3,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: JKBMSRTokens.space12),
          child: _AlertCardSkeleton(),
        ),
      );
    }

    if (_eventLog.isEmpty) {
      if (_eventLogFailures.isNotEmpty) {
        return JKBMSREmptyState(
          icon: Icons.error_outline,
          title: 'No events could be loaded',
          description: _eventLogFailures.join('\n\n'),
          action: OutlinedButton(
            onPressed: () => _loadEventLog(refresh: true),
            child: const Text('Try Again'),
          ),
        );
      }
      return const JKBMSREmptyState(
        icon: Icons.history,
        title: 'Nothing has happened yet',
        description:
            'Resolved alarms, gateway connections and firmware updates appear here as they occur.',
      );
    }

    return Column(
      children: [
        if (_resolvedAlerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              JKBMSRTokens.space16,
              JKBMSRTokens.space4,
              JKBMSRTokens.space16,
              0,
            ),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed:
                    _deletingAllHistory ? null : _confirmDeleteAllHistory,
                style: TextButton.styleFrom(
                    foregroundColor: context.colors.critical),
                child: _deletingAllHistory
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete alert history'),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              JKBMSRHaptics.mediumImpact();
              await _loadEventLog(refresh: true);
            },
            color: context.colors.accent,
            backgroundColor: context.colors.panel,
            child: EventLogTimeline(
              entries: _eventLog,
              header: _eventLogFailures.isEmpty
                  ? null
                  : _buildEventLogFailureBanner(context),
              footer: _eventLogHasMoreAlerts
                  ? _buildEventLogFooter(context)
                  : null,
              actionBuilder: (entry) {
                final alert = entry.alert;
                if (alert == null) return null;
                return _buildEventLogDeleteAction(alert);
              },
            ),
          ),
        ),
      ],
    );
  }

  // The one place the log admits it is short. A source that could not be read
  // is named here; an unreadable gateway narrows its source's coverage instead
  // of removing the other gateways' rows.
  Widget _buildEventLogFailureBanner(BuildContext context) {
    return Container(
      key: const ValueKey('event-log-source-failure'),
      margin: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.critical.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border:
            Border.all(color: context.colors.critical.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: context.colors.critical),
          const SizedBox(width: JKBMSRTokens.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This log is incomplete',
                  style: JKBMSRTypography.cardHeading.copyWith(
                    fontSize: 14.0,
                    color: context.colors.textPrimary,
                  ),
                ),
                for (final failure in _eventLogFailures)
                  Padding(
                    padding: const EdgeInsets.only(top: JKBMSRTokens.space4),
                    child: Text(
                      failure,
                      style: JKBMSRTypography.bodySecondary.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventLogFooter(BuildContext context) {
    if (_isEventLogLoadingMore) {
      return CircularProgressIndicator(color: context.colors.accent);
    }
    return OutlinedButton(
      onPressed: _loadMoreEventLogAlerts,
      child: const Text('Load older alerts'),
    );
  }

  Widget _buildEventLogDeleteAction(Alert alert) {
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: _deletingAlertId == alert.id
            ? null
            : () => _confirmDeleteAlert(alert),
        icon: _deletingAlertId == alert.id
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_outline, size: 16),
        label: const Text('Delete'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.critical,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          minimumSize: const Size(0, 48),
        ),
      ),
    );
  }
}

/// Confirmation for a permanent history deletion. Deliberately styled and
/// worded apart from the resolve dialogs: the confirm action is destructive
/// (critical red) and the copy states that it can't be undone.
class _DeleteHistoryDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _DeleteHistoryDialog({
    required this.title,
    required this.message,
    required this.confirmText,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: context.colors.critical),
          onPressed: onConfirm,
          child: Text(confirmText),
        ),
      ],
    );
  }
}

/// Loading silhouette of one alert card: message + severity pill, the gateway
/// line, the id/timestamp pair and the acknowledge button — mirroring
/// [_AlertCardContent]'s row order, padding and accent-bordered radius so the
/// alert list does not jump when the fetch lands.
class _AlertCardSkeleton extends StatelessWidget {
  const _AlertCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return JKBMSRSkeletonCard(
      borderRadius: JKBMSRTokens.radius12,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      children: [
        Row(
          children: const [
            Expanded(
              child: JKBMSRSkeleton(
                  height: 16, borderRadius: JKBMSRTokens.radius4),
            ),
            SizedBox(width: JKBMSRTokens.space8),
            JKBMSRSkeleton(
                width: 72,
                height: 22,
                borderRadius: JKBMSRTokens.radiusFull),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        const JKBMSRSkeleton(
            height: 12, width: 180, borderRadius: JKBMSRTokens.radius4),
        const SizedBox(height: JKBMSRTokens.space12),
        Row(
          children: const [
            JKBMSRSkeleton(
                width: 80, height: 12, borderRadius: JKBMSRTokens.radius4),
            Spacer(),
            JKBMSRSkeleton(
                width: 120, height: 12, borderRadius: JKBMSRTokens.radius4),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        Align(
          alignment: Alignment.centerRight,
          child: const JKBMSRSkeleton(
              width: 144, height: 40, borderRadius: JKBMSRTokens.radius8),
        ),
      ],
    );
  }
}
