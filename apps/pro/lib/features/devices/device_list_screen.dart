import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../services/cache_service.dart';
import '../../services/device_groups_service.dart';
import '../../models/device.dart';
import '../../models/alert.dart';
import '../../models/telemetry_history_point.dart';
import '../../utils/device_id.dart';
import '../../utils/error_messages.dart';
import '../../utils/haptics.dart';
import '../../widgets/shared/design_system/device_card_background_chart.dart';
import 'widgets/device_group_filter_chips.dart';

class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({Key? key}) : super(key: key);

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  final APIClient _apiClient = APIClient();
  List<Device> _devices = [];
  String _deviceQuery = '';
  bool _isLoading = true;
  String? _error;
  DateTime? _dataAsOf;

  // Multi-select mode for the fleet Compare action — toggled by long-press
  // on a gateway card. At least 2 devices are needed before Compare enables.
  final Set<String> _selectedForCompare = {};
  bool get _isCompareMode => _selectedForCompare.isNotEmpty;

  // Device groups — locally-persisted organization ("House", "Workshop").
  // Filter chip row above the list; null means "All" (no group filter).
  final DeviceGroupsService _groupsService = DeviceGroupsService.instance;
  List<DeviceGroup> _groups = [];
  String? _selectedGroupId;

  // Fleet summary (stat tiles + Recent Alerts + Alert Summary chart) — a
  // secondary, account-wide overview above the device list. Loaded
  // independently of _devices: a failure here shouldn't block the gateway
  // list itself, which is this screen's primary job.
  List<Alert> _alerts = [];
  bool _alertsLoading = true;
  String _alertPeriod = 'today'; // 'today' | 'week' | 'month'

  // Decorative Current/Power wave behind each gateway card — keyed by device
  // id, filled in as each device's history call resolves (see
  // _loadCardHistory). Absence just means the plain card renders with no
  // background, never a loading state.
  final Map<String, List<TelemetryHistoryPoint>> _history = {};

  // getDevices() re-stamps the cache's timestamp only on a genuinely live
  // fetch; a silent fallback to a stale cache (network error, but a cached
  // list still exists) leaves that timestamp old. A gap under this floor is
  // just normal request latency, not staleness worth flagging.
  static const _staleThreshold = Duration(seconds: 45);

  bool get _isShowingStaleData =>
      _dataAsOf != null &&
      DateTime.now().difference(_dataAsOf!) > _staleThreshold;

  @override
  void initState() {
    super.initState();
    _groupsService.load().then((_) {
      if (mounted) setState(() => _groups = _groupsService.groups);
    });
    _loadDevices();
    _loadAlerts();
  }

  // status: 'all' (not the default 'active') so the same fetch feeds both
  // Recent Alerts (any state) and the Alert Summary chart's Resolved slice.
  // Capped at the API's 100-row max — for very high alert volume accounts
  // this makes the Month bucket a most-recent-100 approximation rather than
  // an exact count; Today/Week rarely hit that ceiling in practice.
  Future<void> _loadAlerts() async {
    setState(() => _alertsLoading = true);
    try {
      final result = await _apiClient.getAlerts(status: 'all', limit: 100);
      if (!mounted) return;
      setState(() {
        _alerts = result.alerts;
        _alertsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _alertsLoading = false);
    }
  }

  int get _onlineCount =>
      _devices.where((d) => d.status.toLowerCase() != 'offline').length;
  int get _offlineCount =>
      _devices.where((d) => d.status.toLowerCase() == 'offline').length;
  int get _activeAlertsCount => _alerts.where((a) => !a.isResolved).length;

  DateTime? _parseAlertTime(String createdAt) {
    return DateTime.tryParse(createdAt.contains('T')
            ? createdAt
            : '${createdAt.replaceFirst(' ', 'T')}Z')
        ?.toLocal();
  }

  Duration _alertPeriodDuration() {
    switch (_alertPeriod) {
      case 'week':
        return const Duration(days: 7);
      case 'month':
        return const Duration(days: 30);
      default:
        return const Duration(days: 1);
    }
  }

  List<Device> get _visibleDevices {
    Iterable<Device> list = _devices;
    if (_selectedGroupId != null) {
      final group = _groupsService.getGroup(_selectedGroupId!);
      if (group != null) {
        list = list.where((d) => group.deviceIds.contains(d.id));
      }
    }
    final q = _deviceQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((d) =>
          d.name.toLowerCase().contains(q) || d.id.toLowerCase().contains(q));
    }
    return list.toList();
  }

  List<Alert> get _alertsInSelectedPeriod {
    final cutoff = DateTime.now().subtract(_alertPeriodDuration());
    return _alerts.where((a) {
      final t = _parseAlertTime(a.createdAt);
      return t != null && t.isAfter(cutoff);
    }).toList();
  }

  ({int critical, int warning, int resolved}) get _alertSeverityBreakdown {
    final scoped = _alertsInSelectedPeriod;
    return (
      critical:
          scoped.where((a) => !a.isResolved && a.severity == 'critical').length,
      warning:
          scoped.where((a) => !a.isResolved && a.severity == 'warning').length,
      resolved: scoped.where((a) => a.isResolved).length,
    );
  }

  Future<void> _loadDevices() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final list = await _apiClient.getDevices();
      final cachedAt = await CacheService.instance.getCachedAt('device_list');
      setState(() {
        _devices = list;
        _dataAsOf = cachedAt;
        _isLoading = false;
      });
      _loadCardHistory(list);
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load gateways',
          isError: true);
    }
  }

  // Background gateway-card charts are decorative — fetch per device in
  // parallel, after the list itself is ready, and never let a slow or
  // failed history call hold up the page or take down the rest of the list.
  void _loadCardHistory(List<Device> devices) {
    for (final device in devices) {
      _apiClient
          .getRecentTelemetryHistory(device.id, hours: 24, limit: 24)
          .then((points) {
        if (!mounted) return;
        setState(() => _history[device.id] = points);
      }).catchError((_) {});
    }
  }

  Future<void> _openClaimScreen() async {
    final claimed = await context.push<bool>('/devices/claim');
    if (claimed == true) {
      _loadDevices();
    }
  }

  String _formatAge(DateTime since) {
    final elapsed = DateTime.now().difference(since);
    if (elapsed.inMinutes < 1) return 'moments ago';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} hr ago';
    return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
  }

  Future<void> _showCreateGroupDialog() async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New device group'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Group name',
            hintText: 'e.g. House, Workshop, RV',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || name.isEmpty) return;

    await _groupsService.createGroup(name: name);
    if (mounted) setState(() => _groups = _groupsService.groups);
  }

  // Long-press a group chip to manage it: rename, pick which gateways
  // belong to it, or delete the group. Membership edits don't touch the
  // gateways themselves — groups are a local organizational layer only.
  Future<void> _showEditGroupDialog(DeviceGroup group) async {
    final selected = Set<String>.from(group.deviceIds);
    await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit "${group.name}"'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final device in _devices)
                  CheckboxListTile(
                    title: Text(device.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    value: selected.contains(device.id),
                    onChanged: (checked) {
                      setDialogState(() {
                        if (checked == true) {
                          selected.add(device.id);
                        } else {
                          selected.remove(device.id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _groupsService.deleteGroup(group.id);
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Delete group'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _groupsService.updateGroup(DeviceGroup(
                  id: group.id,
                  name: group.name,
                  color: group.color,
                  deviceIds: selected.toList(),
                ));
                if (context.mounted) Navigator.pop(context, false);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _groups = _groupsService.groups;
        // The edited (or deleted) group may no longer exist — drop the
        // filter rather than showing a stale empty list.
        if (_selectedGroupId != null && _groupsService.getGroup(_selectedGroupId!) == null) {
          _selectedGroupId = null;
        }
      });
    }
  }

  void _toggleCompareSelection(String deviceId) {
    setState(() {
      if (_selectedForCompare.contains(deviceId)) {
        _selectedForCompare.remove(deviceId);
      } else {
        _selectedForCompare.add(deviceId);
      }
    });
    JKBMSRHaptics.lightImpact();
  }

  void _openComparison() {
    if (_selectedForCompare.length < 2) return;
    final ids = _selectedForCompare.join(',');
    context.push('/devices/compare?ids=${Uri.encodeComponent(ids)}');
    setState(() => _selectedForCompare.clear());
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
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          JKBMSRHaptics.mediumImpact();
          await Future.wait([_loadDevices(), _loadAlerts()]);
        },
        color: context.colors.accent,
        backgroundColor: context.colors.panel,
        child: ListView(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('My Gateways', style: JKBMSRTypography.sectionHeading),
                ElevatedButton.icon(
                  onPressed: _openClaimScreen,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Gateway'),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            TextField(
              onChanged: (v) => setState(() => _deviceQuery = v),
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search gateways',
                isDense: true,
              ),
            ),
            if (_isShowingStaleData) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: JKBMSRTokens.space12,
                  vertical: JKBMSRTokens.space8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                  border: Border.all(
                      color: context.colors.warning.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 16, color: context.colors.warning),
                    const SizedBox(width: JKBMSRTokens.space8),
                    Expanded(
                      child: Text(
                        'Showing last-known data from ${_formatAge(_dataAsOf!)}. Pull to refresh once back online.',
                        style: JKBMSRTypography.label
                            .copyWith(color: context.colors.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (!_isLoading && _groups.isNotEmpty) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              DeviceGroupFilterChips(
                groups: _groups,
                selectedGroupId: _selectedGroupId,
                onSelected: (id) => setState(() => _selectedGroupId = id),
                onCreateGroup: _showCreateGroupDialog,
                onEditGroup: _showEditGroupDialog,
              ),
            ],
            if (_isCompareMode) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: JKBMSRTokens.space12,
                  vertical: JKBMSRTokens.space8,
                ),
                decoration: BoxDecoration(
                  color: context.colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                  border: Border.all(
                      color: context.colors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.compare_arrows,
                        size: 16, color: context.colors.accent),
                    const SizedBox(width: JKBMSRTokens.space8),
                    Expanded(
                      child: Text(
                        _selectedForCompare.length < 2
                            ? 'Select at least 2 gateways to compare'
                            : '${_selectedForCompare.length} gateways selected',
                        style: JKBMSRTypography.label
                            .copyWith(color: context.colors.accent),
                      ),
                    ),
                    TextButton(
                      onPressed: _selectedForCompare.length >= 2
                          ? _openComparison
                          : null,
                      child: const Text('Compare'),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedForCompare.clear()),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: JKBMSRTokens.space16),
            if (!_isLoading && _devices.isNotEmpty) ...[
              _fleetStatTiles(),
              const SizedBox(height: JKBMSRTokens.space24),
              _recentAlertsSection(),
              const SizedBox(height: JKBMSRTokens.space24),
              _alertSummarySection(),
              const SizedBox(height: JKBMSRTokens.space24),
            ],
            if (_isLoading)
              ...List.generate(
                  3,
                  (index) => const Padding(
                        padding: EdgeInsets.only(bottom: JKBMSRTokens.space12),
                        child: _DeviceCardSkeleton(),
                      ))
            else if (_error != null && _devices.isEmpty)
              JKBMSREmptyState(
                icon: Icons.error_outline,
                title: 'Could not load gateways',
                description: _error!,
                action: OutlinedButton(
                  onPressed: _loadDevices,
                  child: const Text('Try Again'),
                ),
              )
            else if (_devices.isEmpty)
              JKBMSREmptyState(
                icon: Icons.battery_alert_outlined,
                title: 'No gateways found',
                description: 'You have not added any gateway monitors yet.',
                action: ElevatedButton(
                  onPressed: _openClaimScreen,
                  child: const Text('Pair ESP32 Gateway'),
                ),
              )
            else
              ..._visibleDevices.map((device) {
                return Container(
                  margin: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        JKBMSRHaptics.lightImpact();
                        // In compare mode, taps toggle selection instead of
                        // navigating; long-press anywhere enters compare mode.
                        if (_isCompareMode) {
                          _toggleCompareSelection(device.id);
                          return;
                        }
                        // push (not go) so the back button returns to this
                        // list instead of exiting the app -- go() replaces
                        // the current stack entry rather than adding to it.
                        context.push(
                            '/dashboard?deviceId=${Uri.encodeComponent(device.id)}');
                      },
                      onLongPress: () => _toggleCompareSelection(device.id),
                      borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                      child: Stack(
                        children: [
                          if (_history[device.id] != null)
                            Positioned.fill(
                              child: DeviceCardBackgroundChart(
                                  points: _history[device.id]!),
                            ),
                          if (_isCompareMode)
                            Positioned(
                              top: JKBMSRTokens.space8,
                              right: JKBMSRTokens.space8,
                              child: Icon(
                                _selectedForCompare.contains(device.id)
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 22,
                                color: _selectedForCompare.contains(device.id)
                                    ? context.colors.accent
                                    : context.colors.textMuted,
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.all(JKBMSRTokens.space16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              device.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  JKBMSRTypography.cardHeading,
                                            ),
                                          ),
                                          if (!device.isOwner) ...[
                                            const SizedBox(
                                                width: JKBMSRTokens.space8),
                                            _SharedBadge(),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(
                                          height: JKBMSRTokens.space4),
                                      if (!device.isOwner &&
                                          device.ownerEmail != null)
                                        Text(
                                          'Shared by ${device.ownerEmail}',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style:
                                              JKBMSRTypography.label.copyWith(
                                            color: context.colors.textMuted,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        )
                                      else if (device.name != device.id)
                                        Text(
                                          formatGatewayId(device.id),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: JKBMSRTypography.monoTechnical
                                              .copyWith(
                                            color: context.colors.textMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: JKBMSRTokens.space12),
                                Row(
                                  children: [
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          'SOC: ${device.soc.toStringAsFixed(1)}%',
                                          style: JKBMSRTypography.body.copyWith(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(
                                            height: JKBMSRTokens.space4),
                                        Text(
                                          '${device.voltage.toStringAsFixed(1)} V',
                                          style: JKBMSRTypography.bodySecondary,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: JKBMSRTokens.space16),
                                    JKBMSRStatusBadge(
                                        status: _mapStatus(device.status)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _fleetStatTiles() {
    return Row(
      children: [
        Expanded(
          child: _FleetStatTile(
            label: 'Online',
            value: '$_onlineCount',
            icon: Icons.wifi_tethering,
            color: context.colors.accent,
          ),
        ),
        const SizedBox(width: JKBMSRTokens.space12),
        Expanded(
          child: _FleetStatTile(
            label: 'Active Alerts',
            value: '$_activeAlertsCount',
            icon: Icons.warning_amber_rounded,
            color: context.colors.critical,
            onTap: () => context.go('/alerts'),
          ),
        ),
        const SizedBox(width: JKBMSRTokens.space12),
        Expanded(
          child: _FleetStatTile(
            label: 'Offline',
            value: '$_offlineCount',
            icon: Icons.cloud_off_outlined,
            color: context.colors.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _recentAlertsSection() {
    // getAlerts() already orders by created_at DESC server-side.
    final recent = _alerts.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Alerts', style: JKBMSRTypography.cardHeading),
            TextButton(
              onPressed: () => context.go('/alerts'),
              child: const Text('See All'),
            ),
          ],
        ),
        if (_alertsLoading)
          Column(
            children: List.generate(
              3,
              (index) => const _RecentAlertSkeleton(),
            ),
          )
        else if (recent.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space8),
            child: Text('No alerts recorded yet.',
                style: JKBMSRTypography.bodySecondary),
          )
        else
          ...recent.map((alert) => _RecentAlertTile(alert: alert)),
      ],
    );
  }

  Widget _alertSummarySection() {
    final breakdown = _alertSeverityBreakdown;
    final total = breakdown.critical + breakdown.warning + breakdown.resolved;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: context.colors.panel,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: context.colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Alert Summary', style: JKBMSRTypography.cardHeading),
          const SizedBox(height: JKBMSRTokens.space12),
          JKBMSRSegmentedControl<String>(
            options: const {'today': 'Today', 'week': 'Week', 'month': 'Month'},
            selectedValue: _alertPeriod,
            onSelected: (value) => setState(() => _alertPeriod = value),
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          if (_alertsLoading) ...[
            const JKBMSRSkeleton(
                height: 12, borderRadius: JKBMSRTokens.radiusFull),
            const SizedBox(height: JKBMSRTokens.space16),
            // Three legend rows (Critical / Warning / Resolved): swatch, label
            // and count, matching _AlertLegendRow.
            for (var i = 0; i < 3; i++) ...[
              Row(
                children: const [
                  JKBMSRSkeleton(
                      width: 10,
                      height: 10,
                      borderRadius: JKBMSRTokens.radiusFull),
                  SizedBox(width: JKBMSRTokens.space8),
                  Expanded(
                    child: JKBMSRSkeleton(
                        height: 14, borderRadius: JKBMSRTokens.radius4),
                  ),
                  SizedBox(width: JKBMSRTokens.space12),
                  JKBMSRSkeleton(
                      width: 56, height: 14, borderRadius: JKBMSRTokens.radius4),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space8),
            ],
          ] else if (total == 0)
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: JKBMSRTokens.space8),
              child: Text('No alerts in this period.',
                  style: JKBMSRTypography.bodySecondary),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    if (breakdown.critical > 0) ...[
                      Expanded(
                          flex: breakdown.critical,
                          child: Container(color: context.colors.critical)),
                      if (breakdown.warning > 0 || breakdown.resolved > 0)
                        const SizedBox(width: 2),
                    ],
                    if (breakdown.warning > 0) ...[
                      Expanded(
                          flex: breakdown.warning,
                          child: Container(color: context.colors.warning)),
                      if (breakdown.resolved > 0) const SizedBox(width: 2),
                    ],
                    if (breakdown.resolved > 0)
                      Expanded(
                          flex: breakdown.resolved,
                          child: Container(color: context.colors.accent)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            _AlertLegendRow(
                label: 'Critical',
                count: breakdown.critical,
                total: total,
                color: context.colors.critical),
            const SizedBox(height: JKBMSRTokens.space8),
            _AlertLegendRow(
                label: 'Warning',
                count: breakdown.warning,
                total: total,
                color: context.colors.warning),
            const SizedBox(height: JKBMSRTokens.space8),
            _AlertLegendRow(
                label: 'Resolved',
                count: breakdown.resolved,
                total: total,
                color: context.colors.accent),
          ],
        ],
      ),
    );
  }
}

/// Loading silhouette of one gateway [Card]: the name and id lines on the
/// left, the SOC/voltage pair and a status pill on the right — the same 16dp
/// padding and corner radius the loaded card uses, so the list does not jump
/// when the gateways arrive.
class _DeviceCardSkeleton extends StatelessWidget {
  const _DeviceCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return JKBMSRSkeletonCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  JKBMSRSkeleton(height: 16, width: 150),
                  SizedBox(height: JKBMSRTokens.space4),
                  JKBMSRSkeleton(height: 12, width: 104),
                ],
              ),
            ),
            const SizedBox(width: JKBMSRTokens.space12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                JKBMSRSkeleton(height: 14, width: 64),
                SizedBox(height: JKBMSRTokens.space4),
                JKBMSRSkeleton(height: 12, width: 44),
              ],
            ),
            const SizedBox(width: JKBMSRTokens.space16),
            const JKBMSRSkeleton(
                width: 60, height: 22, borderRadius: JKBMSRTokens.radiusFull),
          ],
        ),
      ],
    );
  }
}

/// One row of the Recent Alerts mini-list: severity mark, device + message
/// lines and a timestamp — mirroring [_RecentAlertTile]'s inset surface.
class _RecentAlertSkeleton extends StatelessWidget {
  const _RecentAlertSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
      ),
      child: const JKBMSRSkeletonListRow(
        leadingSize: 20,
        leadingIsCircle: false,
        trailingWidth: 72,
      ),
    );
  }
}

/// One fleet-level KPI card: colored tint, icon, label, headline count, and
/// an optional chevron only when [onTap] actually goes somewhere (Active
/// Alerts drills into /alerts; Online/Offline are glanceable-only — there's
/// no dedicated filtered-device screen to send them to).
class _FleetStatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _FleetStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
      child: InkWell(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 22, color: color),
                  if (onTap != null)
                    Icon(Icons.chevron_right, size: 16, color: color),
                ],
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Text(label,
                  style: JKBMSRTypography.label
                      .copyWith(color: context.colors.textMuted)),
              const SizedBox(height: JKBMSRTokens.space4),
              Text(
                value,
                style: JKBMSRTypography.pageHeading.copyWith(
                    color: context.colors.textPrimary, fontSize: 26.0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One row in the Recent Alerts mini-list — status color + icon (never
/// color alone), device name, message, and a compact timestamp.
class _RecentAlertTile extends StatelessWidget {
  final Alert alert;

  const _RecentAlertTile({required this.alert});

  Color _severityColor(BuildContext context) {
    if (alert.isResolved) return context.colors.accent;
    return alert.severity == 'critical'
        ? context.colors.critical
        : context.colors.warning;
  }

  IconData get _severityIcon {
    if (alert.isResolved) return Icons.check_circle_outline;
    return alert.severity == 'critical'
        ? Icons.error_outline
        : Icons.warning_amber_rounded;
  }

  String _formatTime(String createdAt) {
    final parsed = DateTime.tryParse(createdAt.contains('T')
            ? createdAt
            : '${createdAt.replaceFirst(' ', 'T')}Z')
        ?.toLocal();
    if (parsed == null) return createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(parsed.hour)}:${two(parsed.minute)} · ${parsed.year}-${two(parsed.month)}-${two(parsed.day)}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(context);
    return Container(
      margin: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
      ),
      child: Row(
        children: [
          Icon(_severityIcon, size: 20, color: color),
          const SizedBox(width: JKBMSRTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.deviceName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JKBMSRTypography.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  alert.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: JKBMSRTypography.bodySecondary,
                ),
              ],
            ),
          ),
          const SizedBox(width: JKBMSRTokens.space8),
          Text(_formatTime(alert.createdAt),
              style: JKBMSRTypography.label
                  .copyWith(color: context.colors.textMuted)),
        ],
      ),
    );
  }
}

/// A swatch + label + count/percentage row under the Alert Summary bar —
/// identity carried by the icon-less colored dot plus the text label, never
/// color alone, matching _RecentAlertTile's icon-plus-color pairing above.
class _AlertLegendRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;

  const _AlertLegendRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0 : (count / total * 100).round();
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: JKBMSRTokens.space8),
        Expanded(child: Text(label, style: JKBMSRTypography.body)),
        Text(
          '$count ($pct%)',
          style: JKBMSRTypography.monoTechnical.copyWith(
              color: context.colors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Marks a gateway shared to this account by another owner (view-only —
/// settings/rename/delete/sharing stay owner-only both here and server-side).
class _SharedBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Shared, view only',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: JKBMSRTokens.space8, vertical: JKBMSRTokens.space2),
        decoration: BoxDecoration(
          color: context.colors.signal.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
          border: Border.all(
              color: context.colors.signal.withValues(alpha: 0.4), width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined,
                size: 11, color: context.colors.signal),
            const SizedBox(width: JKBMSRTokens.space4),
            Text(
              'Shared',
              style: JKBMSRTypography.label
                  .copyWith(color: context.colors.signal, fontSize: 11.0),
            ),
          ],
        ),
      ),
    );
  }
}
