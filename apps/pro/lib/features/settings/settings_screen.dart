import 'dart:async';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/shared/design_system/colors.dart';
import 'package:go_router/go_router.dart';
import '../../app/back_intent.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../services/auth_store.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/notification_service.dart';
import '../../services/secure_credential_store.dart';
import '../../models/device.dart';
import '../../models/device_share.dart';
import '../../models/device_wifi.dart';
import '../../models/device_wifi_target.dart';
import '../../models/recent_session.dart';
import '../../models/user.dart';
import '../../models/bms_vendor.dart';
import '../../main.dart';
import '../../widgets/app_update_prompt.dart';
import '../../utils/error_messages.dart';

class _SettingsCategory {
  final String key;
  final String label;
  final IconData icon;
  const _SettingsCategory(this.key, this.label, this.icon);
}

// Groups the old 15+-card scrolling list into an icon grid (2026 redesign)
// so finding one setting doesn't mean scrolling through every other one.
// Device-scoped categories show the same "pair a gateway"/error empty
// state their cards used to share, instead of their cards, when there's no
// active device. wifi/sharing are owner-only and filtered out of the grid
// entirely for a shared viewer, same as their cards were hidden before.
const List<_SettingsCategory> _settingsCategories = [
  _SettingsCategory('appearance', 'Appearance', Icons.palette_outlined),
  _SettingsCategory('account', 'Account', Icons.person_outline),
  _SettingsCategory('gateway', 'Gateway', Icons.dns_outlined),
  _SettingsCategory('wifi', 'WiFi', Icons.wifi),
  _SettingsCategory('firmware', 'Firmware & OTA', Icons.cloud_sync_outlined),
  _SettingsCategory('dashboard', 'Dashboard Display', Icons.dashboard_customize_outlined),
  _SettingsCategory('bms', 'BMS Hardware', Icons.memory_outlined),
  _SettingsCategory('advanced', 'Advanced & Limits', Icons.tune_outlined),
  _SettingsCategory('notifications', 'Notifications', Icons.notifications_outlined),
  _SettingsCategory('sharing', 'Sharing', Icons.group_outlined),
  _SettingsCategory('about', 'About', Icons.info_outline),
];

const Set<String> _deviceScopedSettingsCategories = {
  'gateway', 'wifi', 'firmware', 'dashboard', 'bms', 'advanced', 'notifications', 'sharing',
};

const Set<String> _ownerOnlySettingsCategories = {'wifi', 'sharing'};

class _SettingsGroup {
  final String title;
  final List<String> categoryKeys;
  const _SettingsGroup(this.title, this.categoryKeys);
}

// Purely a display grouping over _settingsCategories (2026 icon-grid style)
// — every key here must exist there, and visibility filtering (owner-only,
// device-scoped) still comes from that single source of truth via
// _visibleSettingsCategories. A whole group is skipped if none of its
// categories are visible for the current viewer.
const List<_SettingsGroup> _settingsGroups = [
  _SettingsGroup('Account', ['appearance', 'account']),
  _SettingsGroup('Gateway & Hardware', ['gateway', 'wifi', 'firmware', 'bms', 'advanced', 'sharing']),
  _SettingsGroup('Preferences', ['dashboard', 'notifications']),
  _SettingsGroup('Support', ['about']),
];

class SettingsScreen extends StatefulWidget {
  final String? deviceId;

  const SettingsScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final APIClient _apiClient = APIClient();
  final NotificationService _notificationService = NotificationService.instance;
  final TextEditingController _deviceNameController = TextEditingController();

  bool _otaEnabled = true;
  final _minCellVoltageController = TextEditingController(text: '2.5');
  final _maxCellVoltageController = TextEditingController(text: '3.65');
  final _maxCellDeltaController = TextEditingController(text: '0.10');
  final _maxTemperatureController = TextEditingController(text: '55');
  final _minTemperatureController = TextEditingController(text: '0');
  final _maxCurrentController = TextEditingController(text: '100');
  final _minSocController = TextEditingController(text: '10');
  bool _isLoading = true;
  String? _error;
  String? _activeDeviceId;
  Device? _activeDevice;

  // Each card below saves itself independently — a save only touches its
  // own fields (the config PUT endpoint accepts a partial payload) and only
  // that card shows a busy state, instead of one giant save nuking the
  // whole screen into a skeleton.
  bool _savingName = false;
  bool _savingOta = false;
  bool _savingDisplay = false;
  bool _savingBms = false;
  bool _savingAdvanced = false;
  bool _savingThresholds = false;

  // Notification toggles
  bool _criticalBattery = true;
  bool _highTemp = true;
  bool _offlineGateway = false;
  bool _warningAlerts = true;

  String _appVersion = '';

  // About → "Check for updates": true only while the manual check is in
  // flight, so the row can show a spinner and refuse a double-tap.
  bool _checkingForUpdate = false;

  // Sharing (owner-only — the API refuses these for a shared viewer too)
  List<DeviceShare> _shares = [];
  int _maxShares = 5;
  bool _sharesLoading = false;
  bool _addingShare = false;
  final _shareEmailController = TextEditingController();

  // Recent sign-ins — account-wide, not per-device. Loaded independently of
  // the device config so it still shows even with no gateway configured yet.
  List<RecentSession> _sessions = [];
  bool _sessionsLoading = true;
  String? _revokingSessionId;
  bool _revokingAllSessions = false;
  bool _clearingExpiredSessions = false;
  bool _clearingHistorySessions = false;

  // Delete Account — busy only while fetching how this session authenticated
  // (to decide whether the confirmation dialog needs a password field); the
  // dialog itself tracks its own busy/error state for the actual deletion.
  bool _fetchingAuthMethod = false;

  // Biometric Unlock (Security card, Account category) — whether the user has
  // opted into fingerprint/face re-login and whether a password dialog /
  // biometric prompt is currently in flight.
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

  // Settings hub — null shows the grouped list; set to a category key to show
  // that category's cards instead of the old single 15+-card scrolling list.
  String? _selectedCategory;

  // Back inside a category returns to the list. That detail level is internal
  // state, not a route, so the shell's single back guard can't see it —
  // register an inner back handler while (and only while) a category is open.
  // Stored as a field so register/clear use the same tear-off identity.
  late final BackIntentHandler _backIntentHandler = _handleBackIntent;

  bool _handleBackIntent() {
    if (_selectedCategory == null) return false;
    _closeCategory();
    return true;
  }

  void _openCategory(String key) {
    BackIntentRegistry.register(_backIntentHandler);
    setState(() => _selectedCategory = key);
  }

  void _closeCategory() {
    BackIntentRegistry.clear();
    setState(() => _selectedCategory = null);
  }

  // WiFi — owner-only, same as Sharing. Scan and change are both async on
  // the gateway's own poll cycle, so this section polls itself while a
  // request is in flight (see DeviceWifiState.isPending).
  DeviceWifiState? _wifi;
  bool _wifiActionBusy = false;
  bool _wifiPasswordVisible = false;
  Timer? _wifiPollTimer;
  final _wifiSsidController = TextEditingController();
  final _wifiPasswordController = TextEditingController();

  // Persistent remote WiFi target — the "set it and forget it" counterpart to
  // the interactive change above. Loaded alongside _wifi for the owner.
  DeviceWifiTargetState? _wifiTarget;
  bool _wifiTargetLoading = false;
  bool _wifiTargetBusy = false;
  bool _wifiTargetOpen = false;
  bool _wifiTargetPasswordVisible = false;
  final _wifiTargetSsidController = TextEditingController();
  final _wifiTargetPasswordController = TextEditingController();

  // Dashboard & Display Settings
  bool _batteryAnimationsEnabled = true;
  String _dashboardTemplate = 'default';
  bool _savingTemplate = false;

  // All 8 of jkbmsr-web's dashboard templates now have a mobile renderer —
  // see battery_dashboard_screen.dart's _buildDashboardTemplate. Labels/
  // descriptions match jkbmsr-web's DASHBOARD_TEMPLATES (src/lib/api.ts)
  // exactly, so the same template reads the same way in both apps.
  static const _dashboardTemplateOptions = <String, ({String label, String description})>{
    'default': (
      label: 'Default',
      description: 'The standard panel-based layout — light or dark, follows your theme toggle.',
    ),
    'classic-dark': (
      label: 'Classic Readout',
      description: 'A dense terminal-style readout inspired by classic JK-BMS dashboard cards; follows your light or dark theme.',
    ),
    'gauge-sparkline': (
      label: 'Gauge & Sparkline',
      description: 'A themed readout with a voltage trend graph and a remaining-capacity gauge up top.',
    ),
    'icon-tiles': (
      label: 'Icon Tiles',
      description: 'A dense grid of small icon tiles — one per metric — instead of label/value rows.',
    ),
    'status-pills': (
      label: 'Status Pills',
      description: 'Connectivity, error, and balancing status pills up top, with SoC and SoH shown side by side.',
    ),
    'terminal-readout': (
      label: 'Terminal Readout',
      description: 'A monospace terminal-style readout with a state-of-charge gauge, voltage trend, and dense stat grid.',
    ),
    'severity-gauge': (
      label: 'Severity Gauge',
      description: 'A state-of-charge gauge that shifts red/yellow/blue by danger zone, so low charge stands out at a glance.',
    ),
    'mosaic-grid': (
      label: 'Mosaic Grid',
      description: 'A mixed-size tile grid — a couple of large hero numbers and a big gauge, smaller tiles for everything else.',
    ),
    'at-a-glance-strip': (
      label: 'At-a-Glance Strip',
      description: 'Status, electricals, cells, and thermal shown as separate stacked panels.',
    ),
  };

  // Firmware & OTA
  String _currentVersion = '—';
  String _latestVersion = '—';
  bool _updateAvailable = false;
  bool _isOtaChecking = false;

  // BMS Hardware & Communication
  String _bmsVendor = 'jk';
  final _bmsRxPinController = TextEditingController(text: '16');
  final _bmsTxPinController = TextEditingController(text: '17');
  bool _bmsBleEnabled = false;
  final _bmsBleAddressController = TextEditingController();

  // Advanced Gateway Controls
  String _ledMode = 'normal';
  bool _localWebEnabled = true;
  final _emergencyRelayPinController = TextEditingController(text: '0');
  bool _lowPowerModeEnabled = false;
  final _lowPowerSocController = TextEditingController(text: '5');

  @override
  void initState() {
    super.initState();
    _loadConfigAndNotifications();
    _loadAppVersion();
    _loadSessions();
    _loadBiometricPreference();
    _wifiSsidController.addListener(_onWifiSsidChanged);
  }

  void _onWifiSsidChanged() => setState(() {});

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version} (${info.buildNumber})';
    });
  }

  // Manual update check from the About card. Reuses the exact startup path
  // (`promptForAppUpdate`) rather than a second mechanism: Play installs still
  // go through Play In-App Updates, sideloads still get the direct-APK prompt.
  // `manual: true` only adds feedback for the nothing-to-offer case.
  Future<void> _checkForAppUpdate() async {
    if (_checkingForUpdate) return;
    setState(() => _checkingForUpdate = true);
    try {
      await promptForAppUpdate(
        contextProvider: () => mounted ? context : null,
        manual: true,
      );
    } finally {
      if (mounted) setState(() => _checkingForUpdate = false);
    }
  }

  Future<void> _loadBiometricPreference() async {
    final enabled = await BiometricAuthService.instance.isEnabled;
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
  }

  // Custom Tabs (Android) / SFSafariViewController (iOS) — a real browser
  // chrome (its own URL bar, back/forward, sign-in cookies), just presented
  // as a sheet over the app instead of switching away to a separate app.
  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (!launched && mounted) {
      JKBMSRToast.show(context, 'Could not open $url', isError: true);
    }
  }

  @override
  void dispose() {
    _deviceNameController.dispose();
    _minCellVoltageController.dispose();
    _maxCellVoltageController.dispose();
    _maxCellDeltaController.dispose();
    _maxTemperatureController.dispose();
    _minTemperatureController.dispose();
    _maxCurrentController.dispose();
    _minSocController.dispose();
    _shareEmailController.dispose();
    _wifiSsidController.removeListener(_onWifiSsidChanged);
    _wifiSsidController.dispose();
    _wifiPasswordController.dispose();
    _wifiTargetSsidController.dispose();
    _wifiTargetPasswordController.dispose();
    _bmsRxPinController.dispose();
    _bmsTxPinController.dispose();
    _bmsBleAddressController.dispose();
    _emergencyRelayPinController.dispose();
    _lowPowerSocController.dispose();
    _wifiPollTimer?.cancel();
    // Never leave a stale "return to the settings list" handler installed once
    // this screen is gone — the shell's back guard would keep consuming back.
    BackIntentRegistry.clear();
    super.dispose();
  }

  Future<void> _loadConfigAndNotifications() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String? targetId = widget.deviceId;
      final devices = await _apiClient.getDevices();

      // Use the first account device when settings were opened globally.
      if (targetId == null || targetId.isEmpty) {
        if (devices.isNotEmpty) {
          targetId = devices.first.id;
        } else {
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      Device? matchedDevice;
      for (final device in devices) {
        if (device.id == targetId) {
          matchedDevice = device;
          _deviceNameController.text = device.name;
          break;
        }
      }

      final config = await _apiClient.getDeviceConfig(targetId);
      final critical = await _notificationService.isCriticalAlertsEnabled();
      final temp = await _notificationService.isTempWarningsEnabled();
      final offline = await _notificationService.isOfflineGatewaysEnabled();
      final warning = await _notificationService.isWarningsEnabled();

      setState(() {
        _activeDeviceId = targetId;
        _activeDevice = matchedDevice;
        _otaEnabled = config['otaEnabled'] as bool? ?? true;
        _minCellVoltageController.text = (config['minCellVoltageV'] as num? ?? 2.5).toString();
        _maxCellVoltageController.text = (config['maxCellVoltageV'] as num? ?? 3.65).toString();
        _maxCellDeltaController.text = (config['maxCellDeltaV'] as num? ?? 0.10).toString();
        _maxTemperatureController.text = (config['maxTemperatureC'] as num? ?? 55).toString();
        _minTemperatureController.text = (config['minTemperatureC'] as num? ?? 0).toString();
        _maxCurrentController.text = (config['maxCurrentA'] as num? ?? 100).toString();
        _minSocController.text = (config['minSocPercent'] as num? ?? 10).toString();
        _criticalBattery = critical;
        _highTemp = temp;
        _offlineGateway = offline;
        _warningAlerts = warning;
        _batteryAnimationsEnabled = config['batteryAnimationsEnabled'] as bool? ?? true;
        _dashboardTemplate = config['dashboardTemplateMobile'] as String? ?? 'default';
        _currentVersion = config['firmwareVersion'] as String? ?? '—';
        _latestVersion = config['latestFirmwareVersion'] as String? ?? '—';
        _updateAvailable = config['updateAvailable'] as bool? ?? false;
        _bmsVendor = config['bmsVendor'] as String? ?? 'jk';
        _bmsRxPinController.text = (config['bmsUartRxPin'] as num? ?? 16).toString();
        _bmsTxPinController.text = (config['bmsUartTxPin'] as num? ?? 17).toString();
        _bmsBleEnabled = config['bmsBleEnabled'] as bool? ?? false;
        _bmsBleAddressController.text = config['bmsBleAddress'] as String? ?? '';
        _ledMode = config['ledMode'] as String? ?? 'normal';
        _localWebEnabled = config['localWebEnabled'] as bool? ?? true;
        _emergencyRelayPinController.text = (config['emergencyRelayPin'] as num? ?? 0).toString();
        _lowPowerModeEnabled = config['lowPowerModeEnabled'] as bool? ?? false;
        _lowPowerSocController.text = (config['lowPowerSocPercent'] as num? ?? 5).toString();
        _isLoading = false;
      });

      if (matchedDevice?.isOwner ?? false) {
        _loadShares();
        _loadWifi();
        _loadWifiTarget();
      }
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load configuration', isError: true);
    }
  }

  // Shared by every section save below — the config PUT endpoint accepts a
  // partial payload and fills in everything else from what's already
  // stored, so each card only ever sends its own fields.
  Future<bool> _updateConfigFields(Map<String, dynamic> fields) async {
    if (_activeDeviceId == null) return false;
    try {
      await _apiClient.updateDeviceConfig(_activeDeviceId!, fields);
      return true;
    } catch (e) {
      if (!mounted) return false;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
      return false;
    }
  }

  Future<void> _saveGatewayName() async {
    if (_activeDeviceId == null) return;
    final name = _deviceNameController.text.trim();
    if (name.isEmpty || name.length > 80) {
      JKBMSRToast.show(context, 'Gateway name must be between 1 and 80 characters', isError: true);
      return;
    }
    setState(() => _savingName = true);
    try {
      final savedName = await _apiClient.updateDeviceName(_activeDeviceId!, name);
      if (!mounted) return;
      _deviceNameController.text = savedName;
      JKBMSRToast.show(context, 'Gateway name updated');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _savingName = false);
    }
  }

  Future<void> _saveOtaSettings() async {
    setState(() => _savingOta = true);
    final ok = await _updateConfigFields({'otaEnabled': _otaEnabled});
    if (!mounted) return;
    setState(() => _savingOta = false);
    if (ok) {
      JKBMSRToast.show(context, 'OTA settings updated');
    } else {
      JKBMSRToast.show(context, 'Could not update OTA settings', isError: true);
    }
  }

  // Saves immediately on selection rather than batching into "Save Display
  // Settings" below — picking a template is a single, self-contained
  // choice, and immediate feedback matters more here than for the fields
  // that button covers. Mirrors jkbmsr-web's handleTemplateSelect.
  Future<void> _selectDashboardTemplate(String template) async {
    if (template == _dashboardTemplate || _savingTemplate) return;
    final previous = _dashboardTemplate;
    setState(() {
      _dashboardTemplate = template;
      _savingTemplate = true;
    });
    final ok = await _updateConfigFields({'dashboardTemplateMobile': template});
    if (!mounted) return;
    setState(() => _savingTemplate = false);
    if (ok) {
      JKBMSRToast.show(context, 'Dashboard template updated');
    } else {
      setState(() => _dashboardTemplate = previous);
      JKBMSRToast.show(context, 'Could not update dashboard template', isError: true);
    }
  }

  Future<void> _saveDisplaySettings() async {
    setState(() => _savingDisplay = true);
    final ok = await _updateConfigFields({
      'batteryAnimationsEnabled': _batteryAnimationsEnabled,
    });
    if (!mounted) return;
    setState(() => _savingDisplay = false);
    if (ok) JKBMSRToast.show(context, 'Dashboard & display settings updated');
  }

  Future<void> _saveBmsSettings() async {
    final rxPin = int.tryParse(_bmsRxPinController.text.trim());
    final txPin = int.tryParse(_bmsTxPinController.text.trim());
    if (rxPin == null || txPin == null) {
      JKBMSRToast.show(context, 'UART pins must be valid numbers', isError: true);
      return;
    }
    setState(() => _savingBms = true);
    final ok = await _updateConfigFields({
      'bmsVendor': _bmsVendor,
      'bmsUartRxPin': rxPin,
      'bmsUartTxPin': txPin,
      'bmsBleEnabled': _bmsBleEnabled,
      'bmsBleAddress': _bmsBleAddressController.text.trim(),
    });
    if (!mounted) return;
    setState(() => _savingBms = false);
    if (ok) JKBMSRToast.show(context, 'BMS hardware settings updated');
  }

  Future<void> _saveAdvancedSettings() async {
    final relayPin = int.tryParse(_emergencyRelayPinController.text.trim());
    final lowPowerSoc = double.tryParse(_lowPowerSocController.text.trim());
    if (relayPin == null || lowPowerSoc == null) {
      JKBMSRToast.show(context, 'Advanced fields must be valid numbers', isError: true);
      return;
    }
    setState(() => _savingAdvanced = true);
    final ok = await _updateConfigFields({
      'ledMode': _ledMode,
      'localWebEnabled': _localWebEnabled,
      'emergencyRelayPin': relayPin,
      'lowPowerModeEnabled': _lowPowerModeEnabled,
      'lowPowerSocPercent': lowPowerSoc,
    });
    if (!mounted) return;
    setState(() => _savingAdvanced = false);
    if (ok) JKBMSRToast.show(context, 'Advanced gateway settings updated');
  }

  Future<void> _saveAlertThresholds() async {
    final minCellVoltage = double.tryParse(_minCellVoltageController.text.trim());
    final maxCellVoltage = double.tryParse(_maxCellVoltageController.text.trim());
    final maxCellDelta = double.tryParse(_maxCellDeltaController.text.trim());
    final maxTemperature = double.tryParse(_maxTemperatureController.text.trim());
    final minTemperature = double.tryParse(_minTemperatureController.text.trim());
    final maxCurrent = double.tryParse(_maxCurrentController.text.trim());
    final minSoc = double.tryParse(_minSocController.text.trim());
    if (minCellVoltage == null ||
        maxCellVoltage == null ||
        maxCellDelta == null ||
        maxTemperature == null ||
        minTemperature == null ||
        maxCurrent == null ||
        minSoc == null) {
      JKBMSRToast.show(context, 'Alert thresholds must be valid numbers', isError: true);
      return;
    }
    if (minCellVoltage >= maxCellVoltage) {
      JKBMSRToast.show(context, 'Min cell voltage must be less than max cell voltage', isError: true);
      return;
    }
    setState(() => _savingThresholds = true);
    final ok = await _updateConfigFields({
      'minCellVoltageV': minCellVoltage,
      'maxCellVoltageV': maxCellVoltage,
      'maxCellDeltaV': maxCellDelta,
      'maxTemperatureC': maxTemperature,
      'minTemperatureC': minTemperature,
      'maxCurrentA': maxCurrent,
      'minSocPercent': minSoc,
    });
    if (!mounted) return;
    setState(() => _savingThresholds = false);
    if (ok) JKBMSRToast.show(context, 'Alert thresholds updated');
  }

  Future<void> _checkOtaUpdate() async {
    if (_activeDeviceId == null) return;
    setState(() => _isOtaChecking = true);
    try {
      await _apiClient.requestOtaCheck(_activeDeviceId!);
      final config = await _apiClient.getDeviceConfig(_activeDeviceId!);
      if (!mounted) return;
      setState(() {
        _latestVersion = config['latestFirmwareVersion'] as String? ?? _latestVersion;
        _updateAvailable = config['updateAvailable'] as bool? ?? false;
        _isOtaChecking = false;
      });
      if (_updateAvailable) {
        JKBMSRToast.show(context, 'New firmware update $_latestVersion is available!');
      } else {
        JKBMSRToast.show(context, 'Gateway is currently up to date');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOtaChecking = false);
      JKBMSRToast.show(context, 'Check failed: ${friendlyErrorMessage(e)}', isError: true);
    }
  }

  void _triggerOtaUpdate() {
    if (_activeDeviceId == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Check for firmware update',
          content: 'Ask the gateway to check for a new firmware version. If one is available it will download and install it, and monitoring will pause for 1-2 minutes.',
          confirmText: 'Check now',
          onConfirm: () async {
            Navigator.pop(context);
            setState(() => _isOtaChecking = true);
            try {
              await _apiClient.requestOtaCheck(_activeDeviceId!);
              if (!mounted) return;
              JKBMSRToast.show(context, 'Update check requested — the gateway will install it if one is available');
            } catch (e) {
              if (!mounted) return;
              JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
            } finally {
              if (mounted) setState(() => _isOtaChecking = false);
            }
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _loadWifi() async {
    if (_activeDeviceId == null) return;
    try {
      final wifi = await _apiClient.getDeviceWifi(_activeDeviceId!);
      if (!mounted) return;
      setState(() => _wifi = wifi);
      _scheduleWifiPollIfNeeded();
    } catch (e) {
      // WiFi is a secondary section of this screen — a load failure here
      // (e.g. transient network error) shouldn't block the rest of settings.
    }
  }

  // Mirrors jkbmsr-web's 5-second poll while a scan or change is in flight —
  // the gateway only picks these requests up on its own cycle, so there's
  // no push notification for "done"; polling is the only way to know.
  void _scheduleWifiPollIfNeeded() {
    _wifiPollTimer?.cancel();
    _wifiPollTimer = null;
    if (!(_wifi?.isPending ?? false)) return;
    _wifiPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_activeDeviceId == null) return;
      try {
        final wifi = await _apiClient.getDeviceWifi(_activeDeviceId!);
        if (!mounted) return;
        setState(() => _wifi = wifi);
        if (!wifi.isPending) {
          _wifiPollTimer?.cancel();
          _wifiPollTimer = null;
        }
      } catch (_) {
        // Transient poll failure — try again on the next tick.
      }
    });
  }

  Future<void> _requestWifiScan() async {
    if (_activeDeviceId == null) return;
    setState(() => _wifiActionBusy = true);
    try {
      await _apiClient.requestWifiScan(_activeDeviceId!);
      await _loadWifi();
      if (!mounted) return;
      JKBMSRToast.show(context, 'WiFi scan requested. The gateway normally responds within one minute.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _wifiActionBusy = false);
    }
  }

  Future<void> _requestWifiChange() async {
    final ssid = _wifiSsidController.text.trim();
    if (_activeDeviceId == null || ssid.isEmpty) return;
    setState(() => _wifiActionBusy = true);
    try {
      await _apiClient.requestWifiChange(_activeDeviceId!, ssid, _wifiPasswordController.text);
      _wifiPasswordController.clear();
      await _loadWifi();
      if (!mounted) return;
      JKBMSRToast.show(context, 'WiFi change queued. Keep the gateway powered while it verifies the new network.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _wifiActionBusy = false);
    }
  }

  // Loads the persistent remote WiFi target. A failure here (route absent on an
  // older API, or a transient network error) leaves _wifiTarget null, which the
  // card renders as an "unavailable" note rather than blocking the rest of the
  // WiFi section.
  Future<void> _loadWifiTarget() async {
    if (_activeDeviceId == null) return;
    setState(() => _wifiTargetLoading = true);
    try {
      final state = await _apiClient.getDeviceWifiTarget(_activeDeviceId!);
      if (!mounted) return;
      setState(() {
        _wifiTarget = state;
        _wifiTargetLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _wifiTargetLoading = false);
    }
  }

  // Security-sensitive: a plaintext WiFi password is sent here (and stored
  // encrypted server-side), so setting one always goes through an explicit
  // confirmation that says so. Validation mirrors jkbmsr-api's route.
  void _confirmSetWifiTarget() {
    if (_activeDeviceId == null) return;
    final ssid = _wifiTargetSsidController.text.trim();
    if (ssid.isEmpty || ssid.length > 32) {
      JKBMSRToast.show(context, 'Network name must be between 1 and 32 characters', isError: true);
      return;
    }
    final isOpen = _wifiTargetOpen;
    final password = _wifiTargetPasswordController.text;
    if (!isOpen && password.isEmpty) {
      JKBMSRToast.show(context, 'Enter the WiFi password, or turn on "Open network"', isError: true);
      return;
    }
    if (password.length > 63) {
      JKBMSRToast.show(context, 'WiFi password must be 63 characters or fewer', isError: true);
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Set remote WiFi target?',
          content: isOpen
              ? 'The gateway will be told to join "$ssid", an OPEN network with no password. Anyone '
                  'nearby could also join it. It applies this on its next check-in — a gateway that is '
                  'offline or can\'t reach the cloud won\'t receive it until then. If it can\'t connect, '
                  'it keeps retrying and we\'ll alert you.'
              : 'The gateway will be told to join "$ssid". Your WiFi password is sent once and stored '
                  'encrypted on the server — it is never shown again in the app. The gateway applies '
                  'this on its next check-in; one that is offline or can\'t reach the cloud won\'t '
                  'receive it until then. If it can\'t connect, it keeps retrying and we\'ll alert you.',
          confirmText: 'Set',
          onConfirm: () async {
            Navigator.pop(context);
            await _setWifiTarget(ssid, password, isOpen);
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _setWifiTarget(String ssid, String password, bool isOpen) async {
    if (_activeDeviceId == null) return;
    setState(() => _wifiTargetBusy = true);
    try {
      await _apiClient.setDeviceWifiTarget(_activeDeviceId!, ssid: ssid, password: password, isOpen: isOpen);
      _wifiTargetPasswordController.clear();
      _wifiTargetSsidController.clear();
      await _loadWifiTarget();
      await _loadWifi();
      if (!mounted) return;
      JKBMSRToast.show(context, 'Remote WiFi target saved. The gateway applies it on its next check-in.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _wifiTargetBusy = false);
    }
  }

  void _confirmClearWifiTarget() {
    if (_activeDeviceId == null) return;
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Clear remote WiFi target?',
          content: 'The gateway will stop being told which network to join, and the unreachable alerts '
              'stop. No password is sent. The gateway keeps the network it is currently on.',
          confirmText: 'Clear',
          onConfirm: () async {
            Navigator.pop(context);
            await _clearWifiTarget();
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _clearWifiTarget() async {
    if (_activeDeviceId == null) return;
    setState(() => _wifiTargetBusy = true);
    try {
      await _apiClient.clearDeviceWifiTarget(_activeDeviceId!);
      await _loadWifiTarget();
      if (!mounted) return;
      JKBMSRToast.show(context, 'Remote WiFi target cleared.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _wifiTargetBusy = false);
    }
  }

  Future<void> _loadShares() async {
    if (_activeDeviceId == null) return;
    setState(() => _sharesLoading = true);
    try {
      final result = await _apiClient.getDeviceShares(_activeDeviceId!);
      if (!mounted) return;
      setState(() {
        _shares = result.shares;
        _maxShares = result.maxShares;
        _sharesLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sharesLoading = false);
      // Sharing is a secondary section of this screen — a load failure here
      // (e.g. transient network error) shouldn't block the rest of settings.
    }
  }

  Future<void> _addShare() async {
    if (_activeDeviceId == null) return;
    final email = _shareEmailController.text.trim();
    if (email.isEmpty) return;

    setState(() => _addingShare = true);
    try {
      final share = await _apiClient.addDeviceShare(_activeDeviceId!, email);
      if (!mounted) return;
      setState(() {
        _shares = [..._shares, share];
        _addingShare = false;
      });
      _shareEmailController.clear();
      JKBMSRToast.show(context, 'Shared with $email');
    } catch (e) {
      if (!mounted) return;
      setState(() => _addingShare = false);
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    }
  }

  void _confirmRevokeShare(DeviceShare share) {
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Revoke Access',
          content: '${share.email} will immediately lose access to this gateway.',
          confirmText: 'Revoke',
          onConfirm: () async {
            Navigator.pop(context);
            await _revokeShare(share);
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _revokeShare(DeviceShare share) async {
    if (_activeDeviceId == null) return;
    final previousShares = _shares;
    setState(() => _shares = _shares.where((s) => s.userId != share.userId).toList());
    try {
      await _apiClient.revokeDeviceShare(_activeDeviceId!, share.userId);
      if (!mounted) return;
      JKBMSRToast.show(context, 'Revoked access for ${share.email}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _shares = previousShares);
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    }
  }

  // Persists immediately on toggle (like Appearance above) — a native
  // settings switch doesn't need its own Save button, so neither does this.
  Future<void> _handleNotificationToggle(String type, bool value) async {
    if (value) {
      final granted = await _notificationService.requestPermission();
      if (!granted) {
        JKBMSRToast.show(context, 'Notification permission denied', isError: true);
        return;
      }
      // Warm up the push token exchange. This used to fail silently, which made
      // a broken Firebase setup look like "toggling did nothing" — surface the
      // reason instead.
      final token = await _notificationService.getPushToken();
      final error = _notificationService.lastPushError;
      if (!mounted) return;
      if (token == null || error != null) {
        // Reveal the persistent, selectable error card in this section.
        setState(() {});
        JKBMSRToast.show(
          context,
          'Push could not be enabled — see the message in this section',
          isError: true,
        );
        return;
      }
    }

    setState(() {
      if (type == 'critical') {
        _criticalBattery = value;
      } else if (type == 'temp') {
        _highTemp = value;
      } else if (type == 'offline') {
        _offlineGateway = value;
      } else if (type == 'warning') {
        _warningAlerts = value;
      }
    });

    switch (type) {
      case 'critical':
        await _notificationService.setCriticalAlerts(value);
        break;
      case 'temp':
        await _notificationService.setTempWarnings(value);
        break;
      case 'offline':
        await _notificationService.setOfflineGateways(value);
        break;
      case 'warning':
        await _notificationService.setWarningsEnabled(value);
        break;
    }
  }

  Future<void> _toggleBiometricUnlock(bool value) async {
    if (_biometricBusy) return;

    if (!value) {
      // Turning off — drop the preference, clear the stored token, and revoke
      // it server-side so it can't be reused even if it leaked.
      setState(() {
        _biometricEnabled = false;
        _biometricBusy = true;
      });
      await BiometricAuthService.instance.setEnabled(false);
      await SecureCredentialStore.instance.clear();
      try {
        await _apiClient.disableBiometric();
      } catch (_) {
        // Local disable already happened; a failed revoke just means the token
        // lingers server-side until it expires or a password change revokes it.
      }
      if (!mounted) return;
      setState(() => _biometricBusy = false);
      JKBMSRToast.show(context, 'Biometric unlock disabled');
      return;
    }

    // Turning on — the device must actually support biometrics first.
    if (!await BiometricAuthService.instance.isAvailable) {
      JKBMSRToast.show(
        context,
        'Biometrics are not available on this device',
        isError: true,
      );
      return;
    }

    // Prove identity with the account password OR an emailed code. Either
    // mints a long-lived unlock token (stored in the keychain) — the account
    // password itself is never stored.
    setState(() => _biometricBusy = true);

    final method = await _promptForEnableMethod();
    if (method == null) {
      if (mounted) setState(() => _biometricBusy = false);
      return;
    }

    String? password;
    String? otp;
    if (method == 'password') {
      password = await _promptForPassword();
      if (password == null || password.isEmpty) {
        if (mounted) setState(() => _biometricBusy = false);
        return;
      }
    } else {
      try {
        await _apiClient.requestBiometricOtp();
      } catch (e) {
        if (mounted) {
          setState(() => _biometricBusy = false);
          JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
        }
        return;
      }
      otp = await _promptForOtp();
      if (otp == null || otp.isEmpty) {
        if (mounted) setState(() => _biometricBusy = false);
        return;
      }
    }

    try {
      final token = await _apiClient.enableBiometric(password: password, otp: otp);
      if (token.isEmpty) throw Exception('No unlock token returned');
      await SecureCredentialStore.instance.saveToken(token);
      await BiometricAuthService.instance.setEnabled(true);
      if (!mounted) return;
      setState(() {
        _biometricEnabled = true;
        _biometricBusy = false;
      });
      JKBMSRToast.show(context, 'Biometric unlock enabled');
    } catch (e) {
      if (mounted) {
        setState(() => _biometricBusy = false);
        JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
      }
    }
  }

  Future<String?> _promptForEnableMethod() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text("Verify it's you"),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'password'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Use account password'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'otp'),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Email me a code'),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForOtp() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter the code we emailed you'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter your password'),
          content: TextField(
            controller: controller,
            obscureText: true,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => Navigator.pop(context, controller.text),
            decoration: const InputDecoration(labelText: 'Password'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Continue'),
            ),
          ],
        );
      },
    ).then((value) {
      controller.dispose();
      return value;
    });
  }

  Widget _securityCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.fingerprint, size: 20, color: context.colors.accent),
                const SizedBox(width: JKBMSRTokens.space8),
                Text('Biometric Unlock', style: JKBMSRTypography.cardHeading),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'After a session times out, unlock JK BMS Remote with your fingerprint or face instead of re-entering your password. Your password is stored in your device\'s secure keychain.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Use biometrics to re-login'),
              value: _biometricEnabled,
              onChanged: _biometricBusy ? null : _toggleBiometricUnlock,
              secondary: _biometricBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Sign Out',
          content: 'Are you sure you want to sign out of your JKBMSR account?',
          confirmText: 'Sign Out',
          onConfirm: () async {
            Navigator.pop(context);
            // Manual sign-out is explicit user intent — drop the stored
            // biometric unlock token too, so nothing lingers. Biometrics still
            // prompts on session *timeout* (idle/resume), the only biometric
            // path now that the login-screen button is gone.
            await SecureCredentialStore.instance.clear();
            await _notificationService.unregister();
            await AuthStore.instance.clearUser();
            if (mounted) {
              context.go('/login');
            }
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  // Delete Account Permanently — Account category. Fetches how this session
  // authenticated first (jkbmsr-api's DELETE /user/me only requires a
  // password re-entry for a password-authenticated session), then shows a
  // confirmation dialog that stays open through the request so a wrong
  // password / mistyped email surfaces inline instead of failing silently
  // after the dialog is already gone.
  Future<void> _showDeleteAccountDialog() async {
    setState(() => _fetchingAuthMethod = true);
    String authMethod;
    try {
      authMethod = await _apiClient.getAuthMethod();
    } catch (e) {
      if (!mounted) return;
      setState(() => _fetchingAuthMethod = false);
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
      return;
    }
    if (!mounted) return;
    setState(() => _fetchingAuthMethod = false);

    final user = await AuthStore.instance.getUser();
    final accountEmail = user?.email ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return _DeleteAccountDialog(
          accountEmail: accountEmail,
          requiresPassword: authMethod == 'password',
          onConfirm: (confirmEmail, currentPassword) async {
            await _apiClient.deleteAccount(confirmEmail: confirmEmail, currentPassword: currentPassword);
            await SecureCredentialStore.instance.clear();
            await _notificationService.unregister();
            await AuthStore.instance.clearUser();
            if (context.mounted) {
              Navigator.pop(context);
              context.go('/login');
            }
          },
        );
      },
    );
  }

  Future<void> _loadSessions() async {
    try {
      final sessions = await _apiClient.getRecentSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _sessionsLoading = false;
      });
    } catch (_) {
      // Non-critical — the rest of the settings screen still works without
      // this list, so fail silently rather than blocking on it.
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  void _confirmRevokeSession(RecentSession session) {
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Sign Out Device',
          content: 'Sign out of this device or browser?',
          confirmText: 'Sign Out',
          onConfirm: () async {
            Navigator.pop(context);
            await _revokeSession(session);
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _revokeSession(RecentSession session) async {
    setState(() => _revokingSessionId = session.id);
    try {
      final wasCurrent = await _apiClient.revokeSession(session.id);
      if (wasCurrent) {
        // No valid token survives revoking your own current session — clear
        // local auth and let GoRouter's redirect (see app/router.dart) send
        // this device back to /login, same as the manual Sign Out dialog.
        // The explicitly-revoked keychain credentials go too.
        await SecureCredentialStore.instance.clear();
        await AuthStore.instance.clearUser();
        return;
      }
      if (!mounted) return;
      setState(() {
        _sessions = [
          for (final item in _sessions)
            if (item.id == session.id)
              RecentSession(
                id: item.id,
                method: item.method,
                ipAddress: item.ipAddress,
                userAgent: item.userAgent,
                location: item.location,
                createdAt: item.createdAt,
                isCurrent: item.isCurrent,
                revoked: true,
                expired: item.expired,
              )
            else
              item,
        ];
      });
      JKBMSRToast.show(context, 'Signed out of that device.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _revokingSessionId = null);
    }
  }

  void _confirmRevokeOtherSessions() {
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Sign Out Other Devices',
          content: "Sign out of every other device and browser? You'll stay signed in here.",
          confirmText: 'Sign Out Others',
          onConfirm: () async {
            Navigator.pop(context);
            await _revokeOtherSessions();
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _revokeOtherSessions() async {
    setState(() => _revokingAllSessions = true);
    try {
      final token = await _apiClient.revokeOtherSessions();
      final user = await AuthStore.instance.getUser();
      if (user != null) {
        // Server rotated this session's token too — keep this device signed
        // in with the fresh one instead of forcing a re-login here as well.
        await AuthStore.instance.saveUser(User(id: user.id, email: user.email, token: token));
      }
      await _loadSessions();
      if (!mounted) return;
      JKBMSRToast.show(context, 'Signed out of every other device.');
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _revokingAllSessions = false);
    }
  }

  void _confirmClearExpiredSessions() {
    showDialog(
      context: context,
      builder: (context) {
        return JKBMSRDialog(
          title: 'Clear Expired Sign-ins',
          content: 'Remove every expired sign-in record from this list? Active sessions are not affected.',
          confirmText: 'Clear Expired',
          onConfirm: () async {
            Navigator.pop(context);
            await _clearExpiredSessions();
          },
          onCancel: () => Navigator.pop(context),
        );
      },
    );
  }

  Future<void> _clearExpiredSessions() async {
    setState(() => _clearingExpiredSessions = true);
    try {
      final clearedCount = await _apiClient.clearExpiredSessions();
      await _loadSessions();
      if (!mounted) return;
      JKBMSRToast.show(
        context,
        clearedCount > 0 ? 'Cleared $clearedCount expired sign-in${clearedCount == 1 ? '' : 's'}.' : 'No expired sign-ins to clear.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _clearingExpiredSessions = false);
    }
  }

  Future<void> _confirmClearHistorySessions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear sign-in history?'),
        content: const Text(
            'Remove all past sign-in records from this list. Your current session stays active.'),
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
    if (confirmed == true) await _clearAllSessions();
  }

  Future<void> _clearAllSessions() async {
    setState(() => _clearingHistorySessions = true);
    try {
      final clearedCount = await _apiClient.clearAllSessions();
      await _loadSessions();
      if (!mounted) return;
      JKBMSRToast.show(
        context,
        clearedCount > 0
            ? 'Cleared $clearedCount sign-in record${clearedCount == 1 ? '' : 's'}.'
            : 'No sign-in history to clear.',
      );
    } catch (e) {
      if (!mounted) return;
      JKBMSRToast.show(context, friendlyErrorMessage(e), isError: true);
    } finally {
      if (mounted) setState(() => _clearingHistorySessions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.canvas,
        body: const Padding(
          padding: EdgeInsets.all(JKBMSRTokens.space16),
          child: JKBMSRSkeleton(height: 280, borderRadius: JKBMSRTokens.radius8),
        ),
      );
    }
    return _selectedCategory == null ? _buildSettingsList() : _buildCategoryDetail(_selectedCategory!);
  }

  List<_SettingsCategory> get _visibleSettingsCategories {
    final isOwner = _activeDevice?.isOwner ?? false;
    return _settingsCategories.where((category) => isOwner || !_ownerOnlySettingsCategories.contains(category.key)).toList();
  }

  // Root Settings screen: grouped full-width rows (icon + title + chevron)
  // instead of the old icon grid, plus a persistent Logout action pinned at
  // the bottom so signing out never requires drilling into Account first.
  Widget _buildSettingsList() {
    final visibleKeys = _visibleSettingsCategories.map((c) => c.key).toSet();
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: ListView(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        children: [
          const SizedBox(height: JKBMSRTokens.space8),
          for (final group in _settingsGroups)
            if (group.categoryKeys.any(visibleKeys.contains)) ...[
              Padding(
                padding: const EdgeInsets.only(left: JKBMSRTokens.space4, bottom: JKBMSRTokens.space8),
                child: Text(
                  group.title.toUpperCase(),
                  style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted, letterSpacing: 0.5),
                ),
              ),
              for (final key in group.categoryKeys)
                if (visibleKeys.contains(key)) ...[
                  _settingsRow(_settingsCategories.firstWhere((c) => c.key == key)),
                  const SizedBox(height: JKBMSRTokens.space8),
                ],
              const SizedBox(height: JKBMSRTokens.space8),
            ],
          const SizedBox(height: JKBMSRTokens.space8),
          _logoutButton(),
        ],
      ),
    );
  }

  Widget _settingsRow(_SettingsCategory category) {
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: () => _openCategory(category.key),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space16, vertical: JKBMSRTokens.space16),
          child: Row(
            children: [
              Icon(category.icon, size: 22, color: context.colors.accent),
              const SizedBox(width: JKBMSRTokens.space16),
              Expanded(
                child: Text(
                  category.label,
                  style: JKBMSRTypography.body.copyWith(fontWeight: FontWeight.w500, color: context.colors.textPrimary),
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.colors.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoutButton() {
    return Material(
      color: context.colors.critical.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
      child: InkWell(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        onTap: _showLogoutDialog,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, size: 18, color: context.colors.critical),
              const SizedBox(width: JKBMSRTokens.space8),
              Text(
                'Logout',
                style: JKBMSRTypography.body.copyWith(color: context.colors.critical, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryDetail(String categoryKey) {
    final category = _settingsCategories.firstWhere((c) => c.key == categoryKey);
    final showEmptyState = _deviceScopedSettingsCategories.contains(categoryKey) && (_error != null || _activeDeviceId == null);

    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: ListView(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back to Settings',
                onPressed: _closeCategory,
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Text(category.label, style: JKBMSRTypography.sectionHeading),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space16),
          if (showEmptyState)
            _error != null
                ? JKBMSREmptyState(
                    icon: Icons.error_outline,
                    title: 'Could not load configuration',
                    description: _error!,
                    action: OutlinedButton(
                      onPressed: _loadConfigAndNotifications,
                      child: const Text('Try Again'),
                    ),
                  )
                : JKBMSREmptyState(
                    icon: Icons.battery_alert_outlined,
                    title: 'No battery gateway configured',
                    description: 'Please pair a gateway first to adjust configurations.',
                    action: ElevatedButton(
                      onPressed: () => context.go('/devices'),
                      child: const Text('View Gateways'),
                    ),
                  )
          else
            ..._cardsForCategory(categoryKey),
        ],
      ),
    );
  }

  List<Widget> _cardsForCategory(String categoryKey) {
    switch (categoryKey) {
      case 'appearance':
        return [_appearanceCard()];
      case 'account':
        return [_securityCard(), const SizedBox(height: JKBMSRTokens.space16), _recentSignInsCard(), const SizedBox(height: JKBMSRTokens.space16), _deleteAccountCard()];
      case 'gateway':
        return [_gatewayNameCard()];
      case 'wifi':
        return [
          _wifiCard(),
          const SizedBox(height: JKBMSRTokens.space16),
          _remoteWifiTargetCard(),
        ];
      case 'firmware':
        return [_firmwareOtaCard()];
      case 'dashboard':
        return [_dashboardDisplayCard()];
      case 'bms':
        return [_bmsHardwareCard()];
      case 'advanced':
        return [_advancedControlsCard(), const SizedBox(height: JKBMSRTokens.space16), _alertThresholdsCard()];
      case 'notifications':
        // The alert-type toggles below are account-wide (one FCM registration
        // per device), but which alerts fire is decided per gateway by these
        // thresholds — so surface them here, scoped to the active gateway.
        return [
          _notificationsCard(),
          const SizedBox(height: JKBMSRTokens.space16),
          _alertThresholdsCard(),
        ];
      case 'sharing':
        return [_sharingCard()];
      case 'about':
        return [_aboutCard()];
      default:
        return [];
    }
  }

  Widget _appearanceCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Theme follows your system setting unless you choose one.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            ValueListenableBuilder<ThemeMode>(
              valueListenable: themeController,
              builder: (context, mode, _) {
                return JKBMSRSegmentedControl<ThemeMode>(
                  options: const {
                    ThemeMode.system: 'System',
                    ThemeMode.light: 'Light',
                    ThemeMode.dark: 'Dark',
                  },
                  selectedValue: mode,
                  onSelected: (value) => themeController.setMode(value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _recentSignInsCard() {
    final hasExpired = _sessions.any((session) => session.expired);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recent Sign-ins', style: JKBMSRTypography.cardHeading),
                const SizedBox(height: JKBMSRTokens.space8),
                Text(
                  'Where this account has signed in recently.',
                  style: JKBMSRTypography.bodySecondary,
                ),
                const SizedBox(height: JKBMSRTokens.space4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (hasExpired)
                        TextButton(
                          onPressed: _clearingExpiredSessions ? null : _confirmClearExpiredSessions,
                          child: _clearingExpiredSessions
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Clear expired'),
                        ),
                      if (_sessions.isNotEmpty)
                        TextButton(
                          onPressed: _clearingHistorySessions ? null : _confirmClearHistorySessions,
                          child: _clearingHistorySessions
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Clear history'),
                        ),
                      TextButton(
                        onPressed: _revokingAllSessions ? null : _confirmRevokeOtherSessions,
                        child: _revokingAllSessions
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Sign out others'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            if (_sessionsLoading)
              const JKBMSRSkeleton(height: 60)
            else if (_sessions.isEmpty)
              Text('No sign-in history recorded yet.', style: JKBMSRTypography.bodySecondary)
            else
              Column(
                children: [
                  for (final session in _sessions)
                    _SessionTile(
                      session: session,
                      busy: _revokingSessionId == session.id,
                      onSignOut: () => _confirmRevokeSession(session),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _gatewayNameCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gateway Name', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Choose a recognizable name such as Home battery or Workshop bank.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              controller: _deviceNameController,
              maxLength: 80,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Gateway name'),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingName ? null : _saveGatewayName,
                child: _savingName
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Name'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wifiCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gateway WiFi', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'ESP32 and ESP8266 gateways use 2.4 GHz WiFi. The old network is restored '
              'automatically if the new connection cannot reach JKBMSR Cloud.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text(
              'Current network: ${_wifi?.currentSsid.isNotEmpty == true ? _wifi!.currentSsid : 'Waiting for gateway report'}',
              style: JKBMSRTypography.body,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            OutlinedButton(
              onPressed: _wifiActionBusy ? null : _requestWifiScan,
              child: Text(
                _wifi?.scanRequestId != null && _wifi?.scanCompletedAt == null
                    ? 'Scanning on gateway...'
                    : 'Scan 2.4 GHz networks',
              ),
            ),
            if (_wifi?.networks.isNotEmpty ?? false) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              ..._wifi!.networks.map((network) {
                final selected = _wifiSsidController.text == network.ssid;
                return Padding(
                  padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                    onTap: () {
                      setState(() {
                        _wifiSsidController.text = network.ssid;
                        _wifiPasswordController.clear();
                      });
                    },
                    child: SizedBox(
                      height: 48,
                      child: Center(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: JKBMSRTokens.space12,
                            vertical: JKBMSRTokens.space8,
                          ),
                          decoration: BoxDecoration(
                            color: selected ? context.colors.accent.withValues(alpha: 0.1) : context.colors.inset,
                            borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                            border: Border.all(
                              color: selected ? context.colors.accent : context.colors.line,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  network.ssid,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: JKBMSRTypography.body,
                                ),
                              ),
                              Icon(
                                network.secure ? Icons.lock_outline : Icons.lock_open_outlined,
                                size: 16,
                                color: context.colors.textMuted,
                              ),
                              const SizedBox(width: JKBMSRTokens.space8),
                              Icon(Icons.wifi, size: 16, color: context.colors.textMuted),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              controller: _wifiSsidController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Network name (SSID)'),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              controller: _wifiPasswordController,
              obscureText: !_wifiPasswordVisible,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(
                    _wifiPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: context.colors.textMuted,
                  ),
                  tooltip: _wifiPasswordVisible ? 'Hide password' : 'Show password',
                  onPressed: () => setState(() => _wifiPasswordVisible = !_wifiPasswordVisible),
                ),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            ElevatedButton(
              onPressed: (_wifiActionBusy ||
                      _wifiSsidController.text.trim().isEmpty ||
                      _wifi?.changeStatus == 'pending' ||
                      _wifi?.changeStatus == 'applying')
                  ? null
                  : _requestWifiChange,
              child: Text(
                _wifi?.changeStatus == 'pending' || _wifi?.changeStatus == 'applying'
                    ? 'Verifying WiFi change...'
                    : 'Change WiFi network',
              ),
            ),
            if (_wifi?.changeStatus == 'succeeded') ...[
              const SizedBox(height: JKBMSRTokens.space12),
              Text(
                'Connected and verified. The gateway restarted on ${_wifi!.currentSsid}.',
                style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.accent),
              ),
            ],
            if (_wifi?.changeStatus == 'failed') ...[
              const SizedBox(height: JKBMSRTokens.space12),
              Text(
                'Change failed: ${_wifi!.changeMessage.isNotEmpty ? _wifi!.changeMessage : 'previous network restored'}',
                style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.critical),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // SQLite stores datetime('now') as "YYYY-MM-DD HH:MM:SS" in UTC. Render a
  // short readable local form; unparseable input falls through as-is rather
  // than showing a fabricated time.
  static String _formatWhen(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final iso = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse('${iso}Z');
    if (parsed == null) return raw;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final local = parsed.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day} ${months[local.month - 1]} ${local.year}, $hh:$mm';
  }

  // The persistent "set it and forget it" remote WiFi target. Kept separate
  // from _wifiCard because it is a different lifecycle: the interactive change
  // above is a one-shot the gateway verifies and may roll back, while this
  // target is stored server-side and re-delivered on every poll until cleared.
  Widget _remoteWifiTargetCard() {
    final loaded = _wifiTarget != null;
    final target = _wifiTarget?.target;
    final reported = _wifiTarget?.reported;
    final alert = _wifiTarget?.alert;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_sync_outlined, size: 20, color: context.colors.accent),
                const SizedBox(width: JKBMSRTokens.space8),
                Expanded(child: Text('Remote WiFi target', style: JKBMSRTypography.cardHeading)),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Set the network you want this gateway on from anywhere — no need to be on site. It applies '
              'the target on its next check-in and keeps retrying.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),

            // --- What the owner asked for ---
            if (_wifiTargetLoading && !loaded)
              const JKBMSRSkeleton(height: 48, borderRadius: JKBMSRTokens.radius8)
            else if (!loaded)
              Text('Remote target settings are unavailable right now.', style: JKBMSRTypography.bodySecondary)
            else if (target == null)
              Text(
                'No remote target set. The gateway keeps using its current network.',
                style: JKBMSRTypography.bodySecondary,
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(JKBMSRTokens.space12),
                decoration: BoxDecoration(
                  color: context.colors.inset,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                  border: Border.all(color: context.colors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          target.isOpen ? Icons.lock_open_outlined : Icons.lock_outline,
                          size: 16,
                          color: context.colors.textMuted,
                        ),
                        const SizedBox(width: JKBMSRTokens.space8),
                        Expanded(
                          child: Text(
                            target.ssid,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JKBMSRTypography.body,
                          ),
                        ),
                        Text(
                          target.isOpen ? 'Open' : 'Secured',
                          style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text(
                      target.isOpen
                          ? 'No password. Anyone nearby can join this network.'
                          : 'Password stored encrypted — it is never shown again.',
                      style: JKBMSRTypography.bodySecondary,
                    ),
                    if ((target.setAt ?? '').isNotEmpty) ...[
                      const SizedBox(height: JKBMSRTokens.space4),
                      Text('Set ${_formatWhen(target.setAt)}', style: JKBMSRTypography.bodySecondary),
                    ],
                  ],
                ),
              ),
              if (alert?.active ?? false) ...[
                const SizedBox(height: JKBMSRTokens.space12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_outlined, size: 18, color: context.colors.warning),
                    const SizedBox(width: JKBMSRTokens.space8),
                    Expanded(
                      child: Text(
                        "The gateway hasn't reached this network yet. "
                        '${alert!.count > 0 ? "We've alerted you ${alert.count} time${alert.count == 1 ? '' : 's'}. " : ''}'
                        'It keeps retrying on its own.',
                        style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.warning),
                      ),
                    ),
                  ],
                ),
              ],
            ],

            // --- What the gateway last reported ---
            const SizedBox(height: JKBMSRTokens.space16),
            Text(
              'Last reported by the gateway',
              style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
            ),
            const SizedBox(height: JKBMSRTokens.space4),
            if (!loaded)
              Text('—', style: JKBMSRTypography.bodySecondary)
            else if (reported == null)
              Text("The gateway hasn't reported its WiFi state yet.", style: JKBMSRTypography.bodySecondary)
            else ...[
              Text(
                reported.ssid.isNotEmpty ? '${reported.stateLabel} — ${reported.ssid}' : reported.stateLabel,
                style: JKBMSRTypography.body,
              ),
              if ((reported.at ?? '').isNotEmpty)
                Text('at ${_formatWhen(reported.at)}', style: JKBMSRTypography.bodySecondary),
              if (reported.error.isNotEmpty)
                Text(
                  reported.error,
                  style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.critical),
                ),
              if (reported.localProvisioned)
                Text('Set up on site.', style: JKBMSRTypography.bodySecondary),
            ],

            // --- Controls ---
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              key: const ValueKey('remote-wifi-target-ssid'),
              controller: _wifiTargetSsidController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Remote network name (SSID)'),
            ),
            const SizedBox(height: JKBMSRTokens.space4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Open network'),
              subtitle: const Text('No password — anyone nearby can join.'),
              value: _wifiTargetOpen,
              onChanged: _wifiTargetBusy
                  ? null
                  : (value) => setState(() {
                        _wifiTargetOpen = value;
                        // The open-network path is explicit: there is no
                        // password field and no password to send.
                        if (value) _wifiTargetPasswordController.clear();
                      }),
            ),
            if (!_wifiTargetOpen) ...[
              TextField(
                key: const ValueKey('remote-wifi-target-password'),
                controller: _wifiTargetPasswordController,
                obscureText: !_wifiTargetPasswordVisible,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'WiFi password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _wifiTargetPasswordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                      color: context.colors.textMuted,
                    ),
                    tooltip: _wifiTargetPasswordVisible ? 'Hide password' : 'Show password',
                    onPressed: () => setState(() => _wifiTargetPasswordVisible = !_wifiTargetPasswordVisible),
                  ),
                ),
              ),
            ] else ...[
              Text(
                'No password will be sent for an open network.',
                style: JKBMSRTypography.bodySecondary,
              ),
            ],
            const SizedBox(height: JKBMSRTokens.space16),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: JKBMSRTokens.space8,
              runSpacing: JKBMSRTokens.space8,
              children: [
                if (loaded && target != null)
                  TextButton(
                    key: const ValueKey('remote-wifi-target-clear'),
                    onPressed: _wifiTargetBusy ? null : _confirmClearWifiTarget,
                    child: const Text('Clear target'),
                  ),
                ElevatedButton(
                  key: const ValueKey('remote-wifi-target-set'),
                  onPressed: (_wifiTargetBusy || !loaded) ? null : _confirmSetWifiTarget,
                  child: _wifiTargetBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Set remote target'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardDisplayCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dashboard & Display Settings', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Customize the gateway dashboard\'s layout and interactive animation preferences.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text('Dashboard Layout', style: JKBMSRTypography.label),
            const SizedBox(height: JKBMSRTokens.space8),
            JKBMSRCombobox<String>(
              items: _dashboardTemplateOptions.keys.toList(),
              // Falls back to the raw key for a template set from
              // jkbmsr-web that mobile doesn't have a renderer for yet
              // (only the 4 keys above are in _dashboardTemplateOptions) —
              // picking any option here still switches it to a supported one.
              itemToString: (key) => _dashboardTemplateOptions[key]?.label ?? key,
              selectedItem: _dashboardTemplate,
              onSelected: _selectDashboardTemplate,
            ),
            const SizedBox(height: JKBMSRTokens.space4),
            Text(
              _dashboardTemplateOptions[_dashboardTemplate]?.description ?? '',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Battery Charging Animations', style: JKBMSRTypography.body),
                      const SizedBox(height: JKBMSRTokens.space4),
                      Text(
                        'Displays dynamic progress bar charging/discharging effects on battery cells',
                        style: JKBMSRTypography.bodySecondary,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _batteryAnimationsEnabled,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => setState(() => _batteryAnimationsEnabled = val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingDisplay ? null : _saveDisplaySettings,
                child: _savingDisplay
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Display Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _firmwareOtaCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Firmware & OTA Updates', style: JKBMSRTypography.cardHeading),
                if (_updateAvailable)
                  JKBMSRStatusBadge(status: JKBMSRStatus.warning)
                else
                  JKBMSRStatusBadge(status: JKBMSRStatus.online),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Manage over-the-air firmware upgrades for your ESP32 gateway.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Current Installed Version', style: JKBMSRTypography.body),
                Text(_currentVersion, style: JKBMSRTypography.monoTechnical.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Latest Cloud Version', style: JKBMSRTypography.body),
                Text(
                  _latestVersion,
                  style: JKBMSRTypography.monoTechnical.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _updateAvailable ? context.colors.warning : context.colors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _isOtaChecking
                    ? CircularProgressIndicator(color: context.colors.accent)
                    : OutlinedButton(
                        onPressed: _checkOtaUpdate,
                        child: const Text('Check Update'),
                      ),
                if (_updateAvailable) ...[
                  const SizedBox(width: JKBMSRTokens.space12),
                  ElevatedButton(
                    onPressed: _triggerOtaUpdate,
                    style: ElevatedButton.styleFrom(backgroundColor: context.colors.accent),
                    child: const Text('Update Now'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('OTA Updates Allowed', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Allow firmware updates over-the-air', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _otaEnabled,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) {
                    setState(() {
                      _otaEnabled = val;
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingOta ? null : _saveOtaSettings,
                child: _savingOta
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save OTA Setting'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bmsHardwareCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('BMS Hardware & Communication', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Select your battery management system hardware protocol and wiring pinout.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text('BMS Hardware', style: JKBMSRTypography.label),
            const SizedBox(height: JKBMSRTokens.space8),
            JKBMSRCombobox<String>(
              // JKBMSR publicly supports JK-BMS only, so JK-BMS is the only
              // selectable option. This must stay in sync with the API's
              // PUBLIC_BMS_VENDORS (src/constants/bmsVendors.ts).
              //
              // Deliberately NOT the same as the API's ACCEPTED_BMS_VENDORS:
              // a gateway deployed with a legacy vendor still stores that
              // value, and _saveBmsSettings round-trips _bmsVendor verbatim.
              // Forcing it to 'jk' here would silently overwrite the device's
              // configuration on the next save — and a gateway switched to
              // "jk" starts sending JK02 frames at 115200 to hardware that
              // expects a different protocol at 9600.
              //
              // So the picker offers only JK-BMS, but _bmsVendor keeps
              // whatever was loaded, and itemToString below labels a legacy
              // value honestly instead of hiding it.
              items: kSelectableBmsVendors,
              itemToString: (val) {
                switch (val) {
                  case 'jk':
                    return 'JK-BMS';
                  default:
                    // A legacy value can still be stored on a deployed
                    // gateway. Say so plainly rather than presenting it as a
                    // supported option.
                    return '${bmsVendorLabel(val)} — not a supported product';
                }
              },
              selectedItem: _bmsVendor,
              onSelected: (val) => setState(() => _bmsVendor = val),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _bmsRxPinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'UART RX Pin (GPIO)'),
                  ),
                ),
                const SizedBox(width: JKBMSRTokens.space16),
                Expanded(
                  child: TextField(
                    controller: _bmsTxPinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'UART TX Pin (GPIO)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('BMS Bluetooth BLE Connection', style: JKBMSRTypography.body),
                Switch(
                  value: _bmsBleEnabled,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => setState(() => _bmsBleEnabled = val),
                ),
              ],
            ),
            if (_bmsBleEnabled) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              TextField(
                controller: _bmsBleAddressController,
                decoration: const InputDecoration(
                  labelText: 'Target BMS MAC Address (Optional)',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                ),
              ),
            ],
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingBms ? null : _saveBmsSettings,
                child: _savingBms
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save BMS Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedControlsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Advanced Gateway & Safety Controls', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Configure status LED mode, local HTTP server, and emergency disconnect relay.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text('Status LED Mode', style: JKBMSRTypography.label),
            const SizedBox(height: JKBMSRTokens.space8),
            JKBMSRCombobox<String>(
              items: const ['normal', 'silent', 'high_visibility'],
              itemToString: (val) {
                switch (val) {
                  case 'silent': return 'Silent / Stealth (LEDs Off)';
                  case 'high_visibility': return 'High Visibility (Outdoor Pulse)';
                  default: return 'Normal Status Pulse';
                }
              },
              selectedItem: _ledMode,
              onSelected: (val) => setState(() => _ledMode = val),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Local Web Portal', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Serve local HTTP status page on ESP32', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _localWebEnabled,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => setState(() => _localWebEnabled = val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Low Power Deep-Sleep Mode', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Gateway deep-sleeps below the cutoff SOC to conserve battery', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _lowPowerModeEnabled,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => setState(() => _lowPowerModeEnabled = val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emergencyRelayPinController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Emergency Relay GPIO (0=Off)'),
                  ),
                ),
                const SizedBox(width: JKBMSRTokens.space16),
                Expanded(
                  child: TextField(
                    controller: _lowPowerSocController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Deep-Sleep Cutoff SOC (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingAdvanced ? null : _saveAdvancedSettings,
                child: _savingAdvanced
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Advanced Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertThresholdsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alert Thresholds', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Applied to every telemetry reading. Defaults are LFP-appropriate — most owners never need to change these.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space24),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCellVoltageController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min cell voltage (V)'),
                  ),
                ),
                const SizedBox(width: JKBMSRTokens.space16),
                Expanded(
                  child: TextField(
                    controller: _maxCellVoltageController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Max cell voltage (V)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              controller: _maxCellDeltaController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Max cell imbalance delta (V)',
                hintText: '0.10',
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxTemperatureController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Max temp (°C)'),
                  ),
                ),
                const SizedBox(width: JKBMSRTokens.space16),
                Expanded(
                  child: TextField(
                    controller: _minTemperatureController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min temp protection (°C)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxCurrentController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Max current limit (A)'),
                  ),
                ),
                const SizedBox(width: JKBMSRTokens.space16),
                Expanded(
                  child: TextField(
                    controller: _minSocController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Min SOC (%)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: _savingThresholds ? null : _saveAlertThresholds,
                child: _savingThresholds
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save Alert Thresholds'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notification Preferences', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Select which battery alarms trigger dynamic mobile push notifications.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space24),

            // Push setup failure, shown in full and selectable so a broken
            // Firebase setup can't hide behind a transient toast.
            if (_notificationService.lastPushError != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(JKBMSRTokens.space12),
                decoration: BoxDecoration(
                  color: context.colors.critical.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                  border: Border.all(color: context.colors.critical.withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Push notifications are not working',
                      style: JKBMSRTypography.body.copyWith(
                        color: context.colors.critical,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: JKBMSRTokens.space4),
                    SelectableText(
                      _notificationService.lastPushError!,
                      style: JKBMSRTypography.bodySecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space16),
            ],

            // Critical battery alarms
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Critical Battery Alarms', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Under-voltage, over-voltage or low charge', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _criticalBattery,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => _handleNotificationToggle('critical', val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),

            // Protection warnings (cell imbalance, over-current)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Protection Warnings', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Cell imbalance or over-current warnings', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _warningAlerts,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => _handleNotificationToggle('warning', val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),

            // Temperature warnings
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Temperature Alerts', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('High or freezing temperature warnings', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _highTemp,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => _handleNotificationToggle('temp', val),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space16),

            // Gateway Offline
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gateway Disconnects', style: JKBMSRTypography.body),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text('Notify when gateway goes offline', style: JKBMSRTypography.bodySecondary),
                  ],
                ),
                Switch(
                  value: _offlineGateway,
                  activeThumbColor: context.colors.accent,
                  onChanged: (val) => _handleNotificationToggle('offline', val),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sharingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sharing', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Give up to $_maxShares other JKBMSR accounts view-only access to this gateway. You can revoke access at any time.',
              style: JKBMSRTypography.bodySecondary,
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            if (_sharesLoading)
              const JKBMSRSkeleton(height: 40)
            else if (_shares.isEmpty)
              Text('Not shared with anyone yet.', style: JKBMSRTypography.bodySecondary)
            else
              ..._shares.map((share) => Padding(
                    padding: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            share.email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: JKBMSRTypography.body,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.person_remove_outlined, size: 20, color: context.colors.critical),
                          tooltip: 'Revoke access',
                          onPressed: () => _confirmRevokeShare(share),
                        ),
                      ],
                    ),
                  )),
            const SizedBox(height: JKBMSRTokens.space8),
            if (_shares.length >= _maxShares)
              Text(
                'Maximum of $_maxShares people reached. Revoke someone to share with another.',
                style: JKBMSRTypography.label.copyWith(color: context.colors.warning, fontWeight: FontWeight.w400),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _shareEmailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addingShare ? null : _addShare(),
                      decoration: const InputDecoration(labelText: 'Email address'),
                    ),
                  ),
                  const SizedBox(width: JKBMSRTokens.space12),
                  ElevatedButton(
                    onPressed: _addingShare ? null : _addShare,
                    child: _addingShare
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Share'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _aboutCard() {
    return Card(
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          ListTile(
            leading: Icon(Icons.info_outline, color: context.colors.textMuted),
            title: Text('App Version', style: JKBMSRTypography.body),
            trailing: Text(
              _appVersion.isEmpty ? '—' : _appVersion,
              style: JKBMSRTypography.bodySecondary,
            ),
          ),
          Divider(height: 1, color: context.colors.line),
          // Manual update check — same machinery as the startup prompt (Play
          // In-App Updates for Play installs, direct-APK for sideloads).
          ListTile(
            leading: Icon(Icons.system_update_alt, color: context.colors.textMuted),
            title: Text('Check for updates', style: JKBMSRTypography.body),
            trailing: _checkingForUpdate
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.chevron_right, size: 18, color: context.colors.textMuted),
            onTap: _checkingForUpdate ? null : _checkForAppUpdate,
          ),
          Divider(height: 1, color: context.colors.line),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: context.colors.textMuted),
            title: Text('Privacy Policy', style: JKBMSRTypography.body),
            trailing: Icon(Icons.open_in_new, size: 16, color: context.colors.textMuted),
            onTap: () => _openLink('https://jkbmsr.com/privacy/'),
          ),
          Divider(height: 1, color: context.colors.line),
          ListTile(
            leading: Icon(Icons.gavel_outlined, color: context.colors.textMuted),
            title: Text('Terms of Service', style: JKBMSRTypography.body),
            trailing: Icon(Icons.open_in_new, size: 16, color: context.colors.textMuted),
            onTap: () => _openLink('https://jkbmsr.com/terms/'),
          ),
          Divider(height: 1, color: context.colors.line),
          ListTile(
            leading: Icon(Icons.support_agent_outlined, color: context.colors.textMuted),
            title: Text('Support', style: JKBMSRTypography.body),
            trailing: Icon(Icons.open_in_new, size: 16, color: context.colors.textMuted),
            onTap: () => _openLink('https://jkbmsr.com/contact/'),
          ),
        ],
      ),
    );
  }

  // Sign Out lives on the root Settings screen now (see _logoutButton) so
  // it's reachable in one tap; this card is Account's other destructive
  // action, which stays a deliberate drill-in rather than a root action.
  Widget _deleteAccountCard() {
    return Card(
      child: ListTile(
        leading: Icon(Icons.delete_forever_outlined, color: context.colors.critical),
        title: Text(
          'Delete Account Permanently',
          style: JKBMSRTypography.body.copyWith(color: context.colors.critical),
        ),
        trailing: _fetchingAuthMethod
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        onTap: _fetchingAuthMethod ? null : _showDeleteAccountDialog,
      ),
    );
  }
}

/// Confirmation for DELETE /user/me. Stays open through the request (unlike
/// JKBMSRDialog's fire-and-forget onConfirm) so a wrong password or a
/// mistyped confirmation email surfaces inline and the user can retry
/// without having to re-open the whole flow.
class _DeleteAccountDialog extends StatefulWidget {
  final String accountEmail;
  final bool requiresPassword;
  final Future<void> Function(String confirmEmail, String? currentPassword) onConfirm;

  const _DeleteAccountDialog({
    required this.accountEmail,
    required this.requiresPassword,
    required this.onConfirm,
  });

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_busy) return false;
    final emailMatches = _emailController.text.trim().toLowerCase() == widget.accountEmail.toLowerCase();
    final passwordOk = !widget.requiresPassword || _passwordController.text.isNotEmpty;
    return emailMatches && passwordOk;
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onConfirm(
        _emailController.text.trim(),
        widget.requiresPassword ? _passwordController.text : null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        side: BorderSide(color: context.colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delete Account Permanently', style: JKBMSRTypography.cardHeading),
            const SizedBox(height: JKBMSRTokens.space12),
            Container(
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              decoration: BoxDecoration(
                color: context.colors.critical.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
                border: Border.all(color: context.colors.critical.withValues(alpha: 0.4)),
              ),
              child: Text(
                "You'll be signed out everywhere immediately. Your gateways, telemetry history, and account "
                'data are kept for 30 days in case this wasn\'t intentional, then permanently deleted.',
                style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.critical),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text('Type ${widget.accountEmail} to confirm', style: JKBMSRTypography.label),
            const SizedBox(height: JKBMSRTokens.space8),
            TextField(
              controller: _emailController,
              autocorrect: false,
              enabled: !_busy,
              textInputAction: widget.requiresPassword ? TextInputAction.next : TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Account email'),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.requiresPassword) ...[
              const SizedBox(height: JKBMSRTokens.space16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                enabled: !_busy,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Current password'),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: JKBMSRTokens.space12),
              Text(_error!, style: JKBMSRTypography.bodySecondary.copyWith(color: context.colors.critical)),
            ],
            const SizedBox(height: JKBMSRTokens.space24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: JKBMSRTokens.space12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: context.colors.critical),
                  onPressed: _canSubmit ? _submit : null,
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Delete Account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the Recent Sign-ins list — mirrors jkbmsr-web's account
/// settings equivalent: device/browser + location + method, a badge for
/// "This device"/"Signed out"/"Expired", and a Sign Out action when the
/// session is still live and not the one currently viewing this screen.
class _SessionTile extends StatelessWidget {
  final RecentSession session;
  final bool busy;
  final VoidCallback onSignOut;

  const _SessionTile({
    required this.session,
    required this.busy,
    required this.onSignOut,
  });

  String _formatBrowser(String? userAgent) {
    if (userAgent == null || userAgent.isEmpty) return 'Unknown device';
    if (userAgent.contains('iPhone') || userAgent.contains('iPad')) return 'iOS';
    if (userAgent.contains('Android')) return 'Android';
    if (userAgent.contains('Edg/')) return 'Edge';
    if (userAgent.contains('Chrome/')) return 'Chrome';
    if (userAgent.contains('Firefox/')) return 'Firefox';
    if (userAgent.contains('Safari/')) return 'Safari';
    return 'Unknown device';
  }

  String _formatDateTime(String createdAt) {
    final parsed = DateTime.tryParse(createdAt.contains('T') ? createdAt : '${createdAt.replaceFirst(' ', 'T')}Z')?.toLocal();
    if (parsed == null) return createdAt;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final canSignOut = !session.revoked && !session.expired;
    return Container(
      margin: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
      padding: const EdgeInsets.all(JKBMSRTokens.space12),
      decoration: BoxDecoration(
        color: context.colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius8),
        border: Border.all(color: context.colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: JKBMSRTokens.space8,
                  runSpacing: JKBMSRTokens.space4,
                  children: [
                    Text(
                      '${_formatBrowser(session.userAgent)} · ${session.location ?? 'Unknown location'}',
                      style: JKBMSRTypography.body,
                    ),
                    if (session.isCurrent)
                      _SessionBadge(label: 'This device', color: context.colors.accent),
                    if (session.revoked)
                      _SessionBadge(label: 'Signed out', color: context.colors.textMuted)
                    else if (session.expired)
                      _SessionBadge(label: 'Expired', color: context.colors.textMuted),
                  ],
                ),
                const SizedBox(height: JKBMSRTokens.space4),
                Text(
                  'Signed in with ${session.method} · ${_formatDateTime(session.createdAt)}',
                  style: JKBMSRTypography.bodySecondary,
                ),
              ],
            ),
          ),
          if (canSignOut) ...[
            const SizedBox(width: JKBMSRTokens.space8),
            busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : TextButton(
                    onPressed: onSignOut,
                    child: const Text('Sign out'),
                  ),
          ],
        ],
      ),
    );
  }
}

class _SessionBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SessionBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius4),
      ),
      child: Text(
        label,
        style: JKBMSRTypography.label.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
