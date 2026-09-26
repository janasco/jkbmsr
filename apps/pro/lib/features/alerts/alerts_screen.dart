import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../models/alert.dart';
import '../../utils/error_messages.dart';
import '../../utils/haptics.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({Key? key}) : super(key: key);

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  final APIClient _apiClient = APIClient();
  static const int _pageSize = 20;

  int _selectedTab = 0; // 0 = Active, 1 = History
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

  bool _historyLoaded = false;
  bool _isHistoryLoading = true;
  bool _isHistoryLoadingMore = false;
  String? _historyError;
  List<Alert> _historyAlerts = [];
  bool _historyHasMore = false;

  // History deletion (permanent — distinct from resolve). `_deletingAlertId`
  // disables that row's button while in flight; `_deletingAllHistory` covers
  // the bulk action.
  String? _deletingAlertId;
  bool _deletingAllHistory = false;

  @override
  void initState() {
    super.initState();
    _loadActiveAlerts();
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

  Future<void> _loadHistory({bool refresh = false}) async {
    setState(() {
      _isHistoryLoading = true;
      _historyError = null;
      if (refresh) {
        _historyAlerts = [];
      }
    });

    try {
      final result = await _apiClient.getAlerts(status: 'resolved', limit: _pageSize, offset: 0);
      setState(() {
        _historyAlerts = result.alerts;
        _historyHasMore = result.hasMore;
        _historyLoaded = true;
        _isHistoryLoading = false;
      });
    } catch (e) {
      setState(() {
        _historyError = friendlyErrorMessage(e);
        _isHistoryLoading = false;
      });
      JKBMSRToast.show(context, _historyError ?? 'Failed to load alert history', isError: true);
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isHistoryLoadingMore || !_historyHasMore) return;
    setState(() {
      _isHistoryLoadingMore = true;
    });

    try {
      final result = await _apiClient.getAlerts(
        status: 'resolved',
        limit: _pageSize,
        offset: _historyAlerts.length,
      );
      setState(() {
        _historyAlerts = [..._historyAlerts, ...result.alerts];
        _historyHasMore = result.hasMore;
        _isHistoryLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        _isHistoryLoadingMore = false;
      });
      JKBMSRToast.show(
        context,
        friendlyErrorMessage(e),
        isError: true,
      );
    }
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedTab = index;
    });
    if (index == 1 && !_historyLoaded) {
      _loadHistory();
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
      await _loadHistory(refresh: true);
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
            'Permanently remove every resolved alert across your gateways. This cannot be undone; active alarms are not affected.',
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
      await _loadHistory(refresh: true);
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
          // overflowing (a no-op at the default scale).
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryPill('Active Alarms', '${_activeAlerts.length}', context.colors.textPrimary),
                Container(width: 1, height: 28, color: context.colors.line),
                _buildSummaryPill('Critical', '$criticalCount', context.colors.critical),
                Container(width: 1, height: 28, color: context.colors.line),
                _buildSummaryPill('Warnings', '$warningCount', context.colors.warning),
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

  Widget _buildSummaryPill(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: JKBMSRTypography.label.copyWith(fontSize: 11.0)),
        const SizedBox(height: 2),
        Text(
          value,
          style: JKBMSRTypography.monoTechnical.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }

  Widget _buildAlertCard(BuildContext context, Alert alert, {VoidCallback? onDelete}) {
    final isCritical = alert.severity.toLowerCase() == 'critical';
    final accentColor = alert.isResolved
        ? context.colors.accent
        : isCritical
            ? context.colors.critical
            : context.colors.warning;

    // Only allow swiping on unresolved alerts
    if (alert.isResolved) {
      return _buildAlertCardContent(context, alert, isCritical, accentColor, onDelete: onDelete);
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
      child: _buildAlertCardContent(context, alert, isCritical, accentColor, onDelete: onDelete),
    );
  }

  Widget _buildAlertCardContent(
    BuildContext context,
    Alert alert,
    bool isCritical,
    Color accentColor, {
    VoidCallback? onDelete,
  }) {
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
              // Delete is only offered on the History (resolved) tab — active
              // alarms keep Resolve/Clear, which is a non-destructive state
              // change, so a destructive affordance never sits next to it.
              if (onDelete != null) ...[
                const SizedBox(height: JKBMSRTokens.space12),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: _deletingAlertId == alert.id ? null : onDelete,
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
            tabTitles: const ['Active Alarms', 'Alert History'],
            selectedIndex: _selectedTab,
            onTabSelected: _onTabSelected,
          ),
          if (_selectedTab == 0 && !_isLoading && _error == null) _buildSummaryHeader(),
          Expanded(
            child: _selectedTab == 0 ? _buildActiveTab(context) : _buildHistoryTab(context),
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

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16, vertical: JKBMSRTokens.space8),
          child: Column(
            children: [
              // Search input
              TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: 'Search alerts by message or gateway...',
                  prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: context.colors.textMuted),
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
                      onSelected: (val) => setState(() => _severityFilter = val),
                    ),
                  ),
                  if (_selectedDate != null) ...[
                    const SizedBox(width: JKBMSRTokens.space8),
                    IconButton(
                      onPressed: () => setState(() => _selectedDate = null),
                      icon: Icon(Icons.calendar_today, color: context.colors.accent),
                      tooltip: 'Clear date filter',
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
                  itemCount: 3,
                  itemBuilder: (context, index) => const Padding(
                    padding: EdgeInsets.only(bottom: JKBMSRTokens.space12),
                    child: JKBMSRSkeleton(height: 120, borderRadius: JKBMSRTokens.radius8),
                  ),
                )
              : _error != null && _activeAlerts.isEmpty
                  ? JKBMSREmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load alerts',
                      description: _error!,
                      action: OutlinedButton(
                        onPressed: _loadActiveAlerts,
                        child: const Text('Try Again'),
                      ),
                    )
                  : filteredAlerts.isEmpty
                      ? const JKBMSREmptyState(
                          icon: Icons.notifications_off_outlined,
                          title: 'No active alarms',
                          description: 'All battery systems are operating within normal parameters.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            JKBMSRHaptics.mediumImpact();
                            await _loadActiveAlerts();
                          },
                          color: context.colors.accent,
                          backgroundColor: context.colors.panel,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16),
                            itemCount: displayAlerts.length,
                            itemBuilder: (context, index) {
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
                                              style: JKBMSRTypography.label.copyWith(
                                                  fontWeight: FontWeight.bold),
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
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context) {
    if (_isHistoryLoading && !_historyLoaded) {
      return ListView.builder(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        itemCount: 3,
        itemBuilder: (context, index) => const Padding(
          padding: EdgeInsets.only(bottom: JKBMSRTokens.space12),
          child: JKBMSRSkeleton(height: 120, borderRadius: JKBMSRTokens.radius8),
        ),
      );
    }

    if (_historyError != null && _historyAlerts.isEmpty) {
      return JKBMSREmptyState(
        icon: Icons.error_outline,
        title: 'Could not load alert history',
        description: _historyError!,
        action: OutlinedButton(
          onPressed: () => _loadHistory(refresh: true),
          child: const Text('Try Again'),
        ),
      );
    }

    if (_historyAlerts.isEmpty) {
      return const JKBMSREmptyState(
        icon: Icons.history,
        title: 'No resolved alerts yet',
        description: 'Alerts that clear will show up here with when they were resolved.',
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            JKBMSRTokens.space16,
            JKBMSRTokens.space4,
            JKBMSRTokens.space16,
            0,
          ),
          child: Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _deletingAllHistory ? null : _confirmDeleteAllHistory,
              icon: _deletingAllHistory
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('Delete all history'),
              style: TextButton.styleFrom(foregroundColor: context.colors.critical),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              JKBMSRHaptics.mediumImpact();
              await _loadHistory(refresh: true);
            },
            color: context.colors.accent,
            backgroundColor: context.colors.panel,
            child: ListView.builder(
              padding: const EdgeInsets.all(JKBMSRTokens.space16),
              itemCount: _historyAlerts.length + (_historyHasMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= _historyAlerts.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: JKBMSRTokens.space8),
                    child: Center(
                      child: _isHistoryLoadingMore
                          ? CircularProgressIndicator(color: context.colors.accent)
                          : OutlinedButton(
                              onPressed: _loadMoreHistory,
                              child: const Text('Load More'),
                            ),
                    ),
                  );
                }
                final alert = _historyAlerts[index];
                return _buildAlertCard(
                  context,
                  alert,
                  onDelete: () => _confirmDeleteAlert(alert),
                );
              },
            ),
          ),
        ),
      ],
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
