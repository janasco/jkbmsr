import 'dart:async';
import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../widgets/shared/design_system/next_update_countdown.dart';
import '../../services/api_client.dart';
import '../../models/device.dart';
import '../../models/device_wifi_target.dart';
import '../../models/telemetry.dart';
import '../../models/ble_history_event.dart';
import '../../models/telemetry_history_point.dart';
import '../../widgets/shared/design_system/battery_metrics_card.dart';
import '../../widgets/shared/design_system/bms_info_card.dart';
import '../../widgets/shared/design_system/dashboard_templates/classic_dark_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/energy_flow_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/gauge_sparkline_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/icon_tiles_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/status_pills_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/terminal_readout_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/severity_gauge_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/mosaic_grid_template.dart';
import '../../widgets/shared/design_system/dashboard_templates/at_a_glance_strip_template.dart';
import '../../utils/error_messages.dart';
import '../../utils/haptics.dart';
import 'widgets/bms_link_banner.dart';
import 'widgets/offline_alert_controls.dart';

// All 8 of jkbmsr-web's dashboard templates are now ported, plus the
// mobile-only hero 'Energy Flow' renderer used for the 'default' key. A
// device's dashboardTemplateMobile can still be a future key this build
// predates — _buildDashboardTemplate()'s switch falls back to the default
// card for anything it doesn't recognize, rather than crashing or
// rendering nothing.
const _templatesNeedingHistory = {'gauge-sparkline', 'icon-tiles', 'terminal-readout', 'default'};

const _kMinPollInterval = Duration(seconds: 5);

class BatteryDashboardScreen extends StatefulWidget {
  final String? deviceId;

  const BatteryDashboardScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<BatteryDashboardScreen> createState() => _BatteryDashboardScreenState();
}

class _BatteryDashboardScreenState extends State<BatteryDashboardScreen> with WidgetsBindingObserver {
  final APIClient _apiClient = APIClient();
  String _timeRange = '24h';
  bool _isLoading = true;
  Device? _device;
  Telemetry? _telemetry;
  String? _error;
  List<BleHistoryEvent> _bleHistory = [];
  String? _resolvedDeviceId;
  Timer? _pollTimer;
  bool _batteryAnimationsEnabled = true;
  List<TelemetryHistoryPoint> _templateHistory = [];
  // The owner's per-gateway offline-alert episode plus its ack/mute controls.
  // Null until loaded (or when the route is unavailable), which the controls
  // render as "nothing" rather than a false healthy state.
  WifiAlertState? _wifiAlert;
  bool _alertActionBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboardData();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Without this, a screen left open in the foreground for a long stretch
  // just goes stale forever — initState() only fetches once, and the poll
  // timer below is what actually keeps it live. On top of that, backgrounding
  // the app (switching apps, locking the phone) doesn't reliably keep timers
  // firing on schedule, so coming back needs an explicit catch-up fetch
  // rather than waiting for whatever's left of the last poll interval.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pollTimer?.cancel();
      _pollTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      final targetId = _resolvedDeviceId;
      if (targetId != null) {
        _loadDashboardData(silent: true);
      }
    }
  }

  // Polls at the device's own entitled telemetry interval (server-resolved
  // from its Cloud Service tier, not user-settable) rather than a fixed
  // guess, same reasoning as CellVoltagesScreen's identical pattern.
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
      (_) => _loadDashboardData(silent: true, refreshHistory: false),
    );
  }

  Future<void> _loadDashboardData({bool silent = false, bool refreshHistory = true}) async {
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
          if (!silent) {
            setState(() {
              _isLoading = false;
            });
          }
          return;
        }
      }
      _resolvedDeviceId = targetId;

      final details = await _apiClient.getDeviceDetails(targetId);
      if (!mounted) return;
      setState(() {
        _device = details['device'] as Device;
        _telemetry = details['telemetry'] as Telemetry;
        _isLoading = false;
      });

      unawaited(_schedulePolling(targetId));

      // Owner-only offline-alert state. It changes on the alert cadence, not
      // the telemetry one, so like the BLE history it is fetched on the full
      // load / pull-to-refresh and skipped on the periodic silent polls. A
      // shared viewer never sees it — the endpoints are owner-only, and so is
      // the card.
      if (refreshHistory && (_device?.isOwner ?? false)) {
        unawaited(_loadWifiAlertState(targetId));
      }

      // BLE connection history changes far less often than telemetry, so
      // periodic silent polls skip it — only the initial load, a manual
      // pull-to-refresh, and coming back from the background refresh it.
      if (refreshHistory) {
        try {
          final history = await _apiClient.getBleHistory(targetId);
          if (mounted) {
            setState(() {
              _bleHistory = history;
            });
          }
        } catch (_) {
          // Leave _bleHistory as-is; the accordion shows its own empty state.
        }
        // Only fetched for templates that actually draw a trend line — no
        // point spending the request for 'default'/'classic-dark'.
        // The dashboard's time-range selector maps onto [hours] here, so
        // switching 1 Hour/24 Hours/7 Days genuinely re-queries a different
        // window instead of re-fetching the same default slice.
        final resolvedTemplate = _device?.dashboardTemplateMobile ?? 'default';
        if (_templatesNeedingHistory.contains(resolvedTemplate)) {
          try {
            final history = await _apiClient.getRecentTelemetryHistory(
              targetId,
              hours: _historyHoursForRange(_timeRange),
              limit: _historyLimitForRange(_timeRange),
            );
            if (mounted) {
              setState(() {
                _templateHistory = history;
              });
            }
          } catch (_) {
            // Leave _templateHistory as-is; the sparkline shows its own "not enough data" state.
          }
        }
      }
    } catch (e) {
      if (silent) return; // don't surface a toast for a background refresh
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load battery details', isError: true);
    }
  }

  // Loads the gateway's offline-alert episode and the owner's ack/mute state.
  // A failure (route absent on an older API, a shared viewer, or a transient
  // network error) leaves the previous value in place; the controls
  // self-suppress when the state is unknown, so this can never fabricate a
  // "not muted / not acknowledged" claim it did not measure.
  Future<void> _loadWifiAlertState(String deviceId) async {
    try {
      final state = await _apiClient.getDeviceWifiTarget(deviceId);
      if (!mounted) return;
      setState(() {
        _wifiAlert = state.alert;
      });
    } catch (_) {
      // Intentionally silent: this is secondary chrome on a screen that
      // already loaded, not a reason to blank the dashboard or toast.
    }
  }

  // The acknowledgement has no client-side timestamp, so a non-null marker is
  // enough for the controls' null/non-null check. The next full refresh
  // replaces it with the server's authoritative value.
  String _alertAckMarker() => DateTime.now().toUtc().toIso8601String();

  // Each action adopts the server's echoed value rather than assuming success,
  // and never flips the control optimistically — on failure the UI still shows
  // exactly what the server last confirmed.

  Future<void> _acknowledgeOfflineAlert() async {
    final deviceId = _device?.id;
    if (deviceId == null || _alertActionBusy) return;
    JKBMSRHaptics.mediumImpact();
    setState(() => _alertActionBusy = true);
    try {
      final acknowledged = await _apiClient.acknowledgeDeviceOfflineAlerts(deviceId);
      if (!mounted) return;
      setState(() {
        _wifiAlert = _wifiAlert?.copyWith(
          acknowledgedAt: acknowledged ? _alertAckMarker() : null,
          clearAcknowledgedAt: !acknowledged,
        );
      });
      JKBMSRToast.show(context, "Acknowledged. We'll stop alerting you about this outage.");
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _alertActionBusy = false);
    }
  }

  Future<void> _reenableOfflineAlerts() async {
    final deviceId = _device?.id;
    if (deviceId == null || _alertActionBusy) return;
    JKBMSRHaptics.mediumImpact();
    setState(() => _alertActionBusy = true);
    try {
      final acknowledged = await _apiClient.clearDeviceOfflineAlertsAcknowledge(deviceId);
      if (!mounted) return;
      setState(() {
        _wifiAlert = _wifiAlert?.copyWith(
          acknowledgedAt: acknowledged ? _alertAckMarker() : null,
          clearAcknowledgedAt: !acknowledged,
        );
      });
      JKBMSRToast.show(context, 'Offline alerts re-enabled.');
    } on AlertActionUnavailableException catch (e) {
      // The re-enable route may not be deployed yet: say so rather than
      // claiming alerts are back on, or surfacing a bare "API Call Failed".
      if (!mounted) return;
      JKBMSRToast.show(context, e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _alertActionBusy = false);
    }
  }

  Future<void> _setOfflineAlertsMuted(bool muted) async {
    final deviceId = _device?.id;
    if (deviceId == null || _alertActionBusy) return;
    JKBMSRHaptics.lightImpact();
    setState(() => _alertActionBusy = true);
    try {
      final echoed = await _apiClient.setDeviceOfflineAlertsMuted(deviceId, muted: muted);
      if (!mounted) return;
      setState(() {
        _wifiAlert = _wifiAlert?.copyWith(muted: echoed);
      });
      JKBMSRToast.show(
        context,
        echoed ? 'Offline alerts muted for this gateway.' : 'Offline alerts unmuted.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _alertActionBusy = false);
    }
  }

  // A real, connected pack never sits at exactly 0.00V — the API sends
  // voltage/current/soc as 0 (rather than omitting them) when no telemetry
  // row exists yet for this device, so treating "voltage is essentially
  // zero" as the no-data signal is safe and doesn't require an API change.
  bool _hasTelemetry(Telemetry? telemetry) {
    if (telemetry == null) return false;
    return telemetry.voltage > 0.5 || telemetry.soc > 0;
  }

  // Maps the dashboard time-range selector onto the history query window.
  // 7d at one-point-per-hour would be a very sparse line, so the limit is
  // scaled up alongside the window; the server clamps both.
  int _historyHoursForRange(String range) {
    switch (range) {
      case '1h':
        return 1;
      case '7d':
        return 24 * 7;
      case '24h':
      default:
        return 24;
    }
  }

  int _historyLimitForRange(String range) {
    switch (range) {
      case '1h':
        return 60;
      case '7d':
        return 168; // hourly points across 7 days
      case '24h':
      default:
        return 96; // ~15-min resolution across a day
    }
  }

  // 'default' and any of the 5 web-only template keys mobile hasn't ported
  // a renderer for fall back to the original card, rather than the
  // dashboard crashing or going blank. dashboardTemplateMobile is its own
  // field independent of jkbmsr-web's dashboardTemplateWeb, so this only
  // matters if a future mobile release ever sets a value an older release
  // doesn't know how to render — not a day-to-day case anymore now that
  // picking a template in one app can't set the other platform's field.
  Widget _buildDashboardTemplate(String deviceName) {
    final lastSeen = _device?.lastSeen ?? '';
    final status = _device?.status ?? 'offline';
    switch (_device?.dashboardTemplateMobile) {
      case 'classic-dark':
        return JKBMSRClassicDarkTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'gauge-sparkline':
        return JKBMSRGaugeSparklineTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          history: _templateHistory,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'icon-tiles':
        return JKBMSRIconTilesTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          history: _templateHistory,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'status-pills':
        return JKBMSRStatusPillsTemplate(
          telemetry: _telemetry,
          deviceName: deviceName,
          deviceStatus: status,
          lastSeen: lastSeen,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'terminal-readout':
        return JKBMSRTerminalReadoutTemplate(
          telemetry: _telemetry,
          deviceStatus: status,
          lastSeen: lastSeen,
          history: _templateHistory,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'severity-gauge':
        return JKBMSRSeverityGaugeTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'mosaic-grid':
        return JKBMSRMosaicGridTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'at-a-glance-strip':
        return JKBMSRAtAGlanceStripTemplate(
          telemetry: _telemetry,
          deviceName: deviceName,
          deviceStatus: status,
          lastSeen: lastSeen,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      case 'default':
        // The hero renderer: SOC ring + animated energy flow + live stats
        // + balance strip. Uses the same time-range-scoped history the
        // template sparklines get (see _historyHoursForRange).
        return JKBMSREnergyFlowTemplate(
          telemetry: _telemetry,
          lastSeen: lastSeen,
          history: _templateHistory,
          animationsEnabled: _batteryAnimationsEnabled,
        );
      default:
        return JKBMSRBatteryMetricsCard(telemetry: _telemetry, deviceName: deviceName);
    }
  }

  JKBMSRStatus _mapStatus(String statusStr) {
    switch (statusStr.toLowerCase()) {
      case 'online':
        return JKBMSRStatus.online;
      case 'warning':
        return JKBMSRStatus.warning;
      case 'critical':
        return JKBMSRStatus.critical;
      default:
        return JKBMSRStatus.offline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final devName = _device?.name ?? 'Main Solar Bank';
    final linkDown = _telemetry?.linkDiagnostics.isDown ?? false;

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          JKBMSRHaptics.mediumImpact();
          await _loadDashboardData();
        },
        color: context.colors.accent,
        backgroundColor: context.colors.panel,
        child: ListView(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          children: [
            JKBMSRBreadcrumb(
              paths: ['Gateways', devName, 'Dashboard'],
              onTap: (index) {
                if (index == 0) context.go('/devices');
              },
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            if (_isLoading) ...[
              // Device name + status pill, matching the loaded header row.
              Row(
                children: const [
                  Expanded(child: JKBMSRSkeleton(height: 20)),
                  SizedBox(width: JKBMSRTokens.space12),
                  JKBMSRSkeleton(
                      width: 72,
                      height: 24,
                      borderRadius: JKBMSRTokens.radiusFull),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space16),
              const _DashboardSkeleton(),
            ] else if (_error != null && _device == null) ...[
              JKBMSREmptyState(
                icon: Icons.error_outline,
                title: 'Could not load details',
                description: _error!,
                action: OutlinedButton(
                  onPressed: _loadDashboardData,
                  child: const Text('Try Again'),
                ),
              )
            ] else if (_device == null) ...[
              JKBMSREmptyState(
                icon: Icons.battery_alert_outlined,
                title: 'No battery gateway selected',
                description: 'Please go back and select a gateway to monitor.',
                action: ElevatedButton(
                  onPressed: () => context.go('/devices'),
                  child: const Text('View Gateways'),
                ),
              )
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      devName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.sectionHeading,
                    ),
                  ),
                  const SizedBox(width: JKBMSRTokens.space12),
                  JKBMSRStatusBadge(status: _mapStatus(_device!.status)),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space16),

              // Live countdown to the gateway's next expected check-in. The
              // forward-facing half of the same cadence as the "Last update"
              // line that lives inside each dashboard template. Rendered once
              // here rather than threaded through all 9 templates so it is
              // consistent regardless of which template the device uses and
              // no template has to grow a new required parameter.
              if (JKBMSRNextUpdateCountdown.shouldShow(
                secondsUntilNextExpectedCheckIn: _device!.secondsUntilNextExpectedCheckIn,
                deviceStatus: _device!.status,
              )) ...[
                JKBMSRNextUpdateCountdown(
                  secondsUntilNextExpectedCheckIn: _device!.secondsUntilNextExpectedCheckIn,
                  deviceStatus: _device!.status,
                ),
                const SizedBox(height: JKBMSRTokens.space16),
              ],

              // Owner-only acknowledge / mute controls for the gateway-offline
              // alert. Self-suppresses for a healthy, un-muted gateway, so it
              // sits beside the countdown as the per-gateway counterpart to
              // the cross-device Alerts list rather than permanent chrome.
              if (_device!.isOwner && OfflineAlertControls.shouldShow(_wifiAlert)) ...[
                OfflineAlertControls(
                  alert: _wifiAlert!,
                  busy: _alertActionBusy,
                  onAcknowledge: _acknowledgeOfflineAlert,
                  onReenable: _reenableOfflineAlerts,
                  onToggleMute: _setOfflineAlertsMuted,
                ),
                const SizedBox(height: JKBMSRTokens.space16),
              ],

              // Only renders when the gateway explicitly reports its BMS link
              // down — the healthy/unknown case contributes nothing, so there
              // is no permanent banner on a working gateway.
              if (linkDown) ...[
                BmsLinkBanner(telemetry: _telemetry),
                const SizedBox(height: JKBMSRTokens.space16),
              ],

              if (_hasTelemetry(_telemetry)) ...[
                _buildDashboardTemplate(devName),
                const SizedBox(height: JKBMSRTokens.space16),
                JKBMSRBmsInfoCard(telemetry: _telemetry),
              ] else ...[
                // The API returns voltage/current/soc as 0 (not null) when
                // this gateway has never posted a telemetry row yet — a
                // brand-new pairing, or a reconnect before the first BLE
                // poll lands. JKBMSRBatteryMetricsCard can't tell that
                // apart from a real 0V/0% reading, so it would otherwise
                // render a full "dead battery" dashboard for a gateway
                // that's simply Online and waiting for its first poll.
                JKBMSREmptyState(
                  icon: linkDown ? Icons.link_off : Icons.hourglass_empty,
                  title: linkDown ? 'No data from the BMS' : 'Waiting for telemetry',
                  description: linkDown
                      ? 'The gateway is online but is not receiving battery '
                          'data. See the note above for what to check — '
                          'readings return on their own once the link is back.'
                      : 'This gateway is online but hasn\'t reported any BMS data yet. '
                          'This is normal right after pairing or a reconnect — '
                          'pull to refresh in a moment.',
                ),
              ],
              const SizedBox(height: JKBMSRTokens.space16),

              // Segmented control to select time range — drives the
              // template history query window (see _historyHoursForRange).
              // A silent refresh avoids the full-screen skeleton flash on
              // what should be an in-place chart update.
              JKBMSRSegmentedControl<String>(
                options: const {
                  '1h': '1 Hour',
                  '24h': '24 Hours',
                  '7d': '7 Days',
                },
                selectedValue: _timeRange,
                onSelected: (value) {
                  if (value == _timeRange) return;
                  JKBMSRHaptics.lightImpact();
                  setState(() {
                    _timeRange = value;
                  });
                  _loadDashboardData(silent: true, refreshHistory: true);
                },
              ),
              const SizedBox(height: JKBMSRTokens.space12),

              // Cloud Service long-term history (up to 365 days, works
              // offline via cache) — a separate screen rather than a 5th
              // bottom-nav tab, since the nav bar has exactly 4 fixed slots.
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final targetId = _device?.id;
                    context.push(
                      targetId != null ? '/history?deviceId=${Uri.encodeComponent(targetId)}' : '/history',
                    );
                  },
                  icon: Icon(Icons.show_chart, size: 18, color: context.colors.accent),
                  label: Text('Cloud Service history', style: JKBMSRTypography.body.copyWith(color: context.colors.accent)),
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space16),

              // Per-cell voltages and the detailed metrics table now live on
              // the Cells tab, so the dashboard keeps only the summary panels.

              // Bluetooth connection history — latest 10 successful BLE
              // polls, reused from telemetry server-side (same data
              // jkbmsr-web's device page shows), not a live-scanning view.
              JKBMSRAccordion(
                title: 'Bluetooth Connection History',
                content: _bleHistory.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(JKBMSRTokens.space16),
                        child: Text(
                          'No successful Bluetooth polls recorded yet.',
                          style: JKBMSRTypography.bodySecondary,
                        ),
                      )
                    : Column(
                        children: [
                          for (final event in _bleHistory) _BleHistoryTile(event: event),
                        ],
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BleHistoryTile extends StatelessWidget {
  final BleHistoryEvent event;

  const _BleHistoryTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final connectedAt = DateTime.tryParse('${event.timestamp}Z')?.toLocal();
    final connectedLabel = connectedAt != null ? _formatDateTime(connectedAt) : event.timestamp;
    final signalLabel = event.rssi > -128 ? '${event.rssi} dBm' : 'Unknown';
    final firmwareLabel =
        '${event.hardwareVersion.isEmpty ? '—' : event.hardwareVersion} / ${event.softwareVersion.isEmpty ? '—' : event.softwareVersion}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16, vertical: JKBMSRTokens.space12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.line, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(connectedLabel, style: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Read-only',
                  style: JKBMSRTypography.label.copyWith(color: context.colors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${event.advertisedName.isEmpty ? 'JK-BMS' : event.advertisedName} · ${event.address.isEmpty ? 'Auto' : event.address}',
            style: JKBMSRTypography.bodySecondary,
          ),
          const SizedBox(height: 2),
          Text(
            'Signal: $signalLabel  •  Firmware: $firmwareLabel  •  Frames: ${event.framesDecoded}',
            style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} ${two(dt.hour)}:${two(dt.minute)}';
  }
}

/// Loading silhouette of the dashboard body: the primary metrics card (SOC
/// banner, a 2x2 metric grid and the cell-imbalance footer) followed by the
/// Battery & BMS info panel. Mirrors [JKBMSRBatteryMetricsCard] and
/// [JKBMSRBmsInfoCard] so the page does not jump when telemetry arrives.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        JKBMSRSkeletonCard(
          borderRadius: JKBMSRTokens.radius16,
          children: [
            // Header: status dot + device name + power-state pill.
            Row(
              children: const [
                JKBMSRSkeleton(
                    width: 8,
                    height: 8,
                    borderRadius: JKBMSRTokens.radiusFull),
                SizedBox(width: JKBMSRTokens.space8),
                Expanded(child: JKBMSRSkeleton(height: 16)),
                SizedBox(width: JKBMSRTokens.space8),
                JKBMSRSkeleton(
                    width: 76,
                    height: 22,
                    borderRadius: JKBMSRTokens.radiusFull),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            // SOC banner: label, headline value and progress bar.
            JKBMSRSkeletonCard(
              borderRadius: JKBMSRTokens.radius12,
              color: context.colors.inset,
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              children: const [
                JKBMSRSkeleton(width: 116, height: 11),
                SizedBox(height: JKBMSRTokens.space8),
                JKBMSRSkeleton(width: 120, height: 30),
                SizedBox(height: JKBMSRTokens.space12),
                JKBMSRSkeleton(
                    height: 8, borderRadius: JKBMSRTokens.radiusFull),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            // 2x2 headline metric grid.
            Row(
              children: const [
                Expanded(child: JKBMSRSkeletonStat()),
                SizedBox(width: JKBMSRTokens.space12),
                Expanded(child: JKBMSRSkeletonStat()),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Row(
              children: const [
                Expanded(child: JKBMSRSkeletonStat()),
                SizedBox(width: JKBMSRTokens.space12),
                Expanded(child: JKBMSRSkeletonStat()),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            // Cell-imbalance footer.
            JKBMSRSkeletonCard(
              borderRadius: JKBMSRTokens.radius12,
              color: context.colors.inset,
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              children: const [
                JKBMSRSkeletonListRow(
                    leadingSize: 18, leadingIsCircle: false, trailingWidth: 0),
              ],
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        // Battery & BMS info panel: heading plus a label/value list.
        const JKBMSRSkeleton(width: 150, height: 18),
        const SizedBox(height: JKBMSRTokens.space8),
        JKBMSRSkeletonCard(
          borderRadius: JKBMSRTokens.radius16,
          padding: const EdgeInsets.symmetric(
              horizontal: JKBMSRTokens.space16, vertical: 4),
          children: [
            for (var i = 0; i < 7; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: const [
                    JKBMSRSkeleton(width: 110, height: 12),
                    Spacer(),
                    JKBMSRSkeleton(width: 64, height: 12),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
