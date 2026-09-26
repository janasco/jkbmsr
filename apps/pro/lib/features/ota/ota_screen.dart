import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../models/ota_event.dart';
import '../../utils/device_id.dart';
import '../../utils/error_messages.dart';

class OTAScreen extends StatefulWidget {
  final String? deviceId;

  const OTAScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<OTAScreen> createState() => _OTAScreenState();
}

class _OTAScreenState extends State<OTAScreen> {
  final APIClient _apiClient = APIClient();
  bool _isLoading = true;
  bool _isChecking = false;
  bool _updateAvailable = false;
  String _currentVersion = '—';
  String _latestVersion = '—';
  String? _activeDeviceId;
  List<OtaEvent> _events = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOtaData();
  }

  Future<void> _loadOtaData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String? targetId = widget.deviceId;
      
      // Fetch devices if no deviceId was passed
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

      final config = await _apiClient.getDeviceConfig(targetId);
      final history = await _apiClient.getOtaHistory(targetId);

      setState(() {
        _activeDeviceId = targetId;
        _currentVersion = config['firmwareVersion'] as String? ?? '0.1.2';
        _latestVersion = config['latestFirmwareVersion'] as String? ?? '0.1.2';
        _updateAvailable = config['updateAvailable'] as bool? ?? false;
        _events = history;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load OTA details', isError: true);
    }
  }

  Future<void> _checkUpdate() async {
    if (_activeDeviceId == null) return;

    setState(() {
      _isChecking = true;
    });

    try {
      await _apiClient.requestOtaCheck(_activeDeviceId!);
      // Reload configuration after queuing a live server query.
      final config = await _apiClient.getDeviceConfig(_activeDeviceId!);
      setState(() {
        _latestVersion = config['latestFirmwareVersion'] as String? ?? _latestVersion;
        _updateAvailable = config['updateAvailable'] as bool? ?? false;
      });
      if (_updateAvailable) {
        JKBMSRToast.show(context, 'New firmware update $_latestVersion is available!');
      } else {
        JKBMSRToast.show(context, 'Gateway is currently up to date');
      }
    } catch (e) {
      JKBMSRToast.show(context, 'Check failed: ${friendlyErrorMessage(e)}', isError: true);
    } finally {
      setState(() {
        _isChecking = false;
      });
    }
  }

  void _triggerOTAUpdate() {
    if (_activeDeviceId == null) return;

    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Check for firmware update',
          content: 'Ask the ESP32 gateway to check for a new firmware version. If one is available it will download and install it, and monitoring will pause for 1-2 minutes.',
          confirmText: 'Check now',
          onConfirm: () async {
            Navigator.pop(context);
            setState(() {
              _isChecking = true;
            });
            try {
              await _apiClient.requestOtaCheck(_activeDeviceId!);
              JKBMSRToast.show(context, 'Update check requested — the gateway will install it if one is available');
              _loadOtaData();
            } catch (e) {
              JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
            } finally {
              setState(() {
                _isChecking = false;
              });
            }
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  JKBMSRStatus _mapResultStatus(String result) {
    switch (result.toLowerCase()) {
      case 'success':
      case 'succeeded':
        return JKBMSRStatus.online;
      case 'failed':
      case 'error':
        return JKBMSRStatus.critical;
      case 'checking':
        return JKBMSRStatus.warning;
      default:
        return JKBMSRStatus.offline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: _isLoading
          ? const Padding(
              padding: EdgeInsets.all(JKBMSRTokens.space16),
              child: JKBMSRSkeleton(height: 280, borderRadius: JKBMSRTokens.radius8),
            )
          : RefreshIndicator(
              onRefresh: _loadOtaData,
              color: context.colors.accent,
              backgroundColor: context.colors.panel,
              child: ListView(
                padding: const EdgeInsets.all(JKBMSRTokens.space16),
                children: [
                  if (_error != null && _activeDeviceId == null)
                    JKBMSREmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load OTA details',
                      description: _error!,
                      action: OutlinedButton(
                        onPressed: _loadOtaData,
                        child: const Text('Try Again'),
                      ),
                    )
                  else if (_activeDeviceId == null)
                    JKBMSREmptyState(
                      icon: Icons.battery_alert_outlined,
                      title: 'No battery gateway found',
                      description: 'Please pair a gateway first.',
                      action: ElevatedButton(
                        onPressed: () => context.go('/devices'),
                        child: const Text('View Gateways'),
                      ),
                    )
                  else ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(JKBMSRTokens.space24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'OTA Firmware Updates (${_activeDeviceId != null ? formatGatewayId(_activeDeviceId!) : ''})',
                              style: JKBMSRTypography.cardHeading,
                            ),
                            const SizedBox(height: JKBMSRTokens.space8),
                            Text(
                              'Configure gateway firmware updates over the air securely from Cloudflare R2.',
                              style: JKBMSRTypography.bodySecondary,
                            ),
                            const SizedBox(height: JKBMSRTokens.space24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Current Version', style: JKBMSRTypography.body),
                                Text(
                                  _currentVersion,
                                  style: JKBMSRTypography.monoTechnical.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: JKBMSRTokens.space12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Latest Server Version', style: JKBMSRTypography.body),
                                _isChecking
                                    ? const JKBMSRSkeleton(width: 40, height: 16)
                                    : Text(
                                        _latestVersion,
                                        style: JKBMSRTypography.monoTechnical.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: _updateAvailable ? context.colors.warning : context.colors.textSecondary,
                                        ),
                                      ),
                              ],
                            ),
                            const SizedBox(height: JKBMSRTokens.space12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                // push (not go) so back returns to OTA settings instead of exiting.
                                onPressed: () => context.push(
                                  '/firmware${_activeDeviceId != null ? '?deviceId=${Uri.encodeComponent(_activeDeviceId!)}' : ''}',
                                ),
                                icon: const Icon(Icons.fact_check_outlined, size: 18),
                                label: const Text('View Firmware Releases'),
                              ),
                            ),
                            Divider(height: JKBMSRTokens.space32, color: context.colors.line),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                _isChecking
                                    ? CircularProgressIndicator(color: context.colors.accent)
                                    : OutlinedButton(
                                        onPressed: _checkUpdate,
                                        child: const Text('Check Update'),
                                      ),
                                if (_updateAvailable) ...[
                                  const SizedBox(width: JKBMSRTokens.space12),
                                  ElevatedButton(
                                    onPressed: _triggerOTAUpdate,
                                    style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent),
                                    child: const Text('Update Now'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: JKBMSRTokens.space24),
                    Text('Firmware Flash Logs', style: JKBMSRTypography.cardHeading),
                    const SizedBox(height: JKBMSRTokens.space12),
                    if (_events.isEmpty)
                      const JKBMSREmptyState(
                        icon: Icons.history,
                        title: 'No update records',
                        description: 'No OTA flash actions have been completed yet.',
                      )
                    else
                      ..._events.map((event) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(JKBMSRTokens.space16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Version: ${event.offeredVersion}',
                                        style: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      JKBMSRStatusBadge(status: _mapResultStatus(event.lastResult)),
                                    ],
                                  ),
                                  const SizedBox(height: JKBMSRTokens.space8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Status: ${event.lastResult}',
                                        style: JKBMSRTypography.bodySecondary.copyWith(fontSize: 13.0),
                                      ),
                                      Text(
                                        event.createdAt,
                                        style: JKBMSRTypography.label,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                  ]
                ],
              ),
            ),
    );
  }
}
