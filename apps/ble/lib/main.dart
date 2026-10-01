import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'services/ble_service.dart';
import 'services/entitlement_service.dart';
import 'services/theme_service.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/bms_drawer.dart';
import 'widgets/software_update_modal.dart';
import 'widgets/support_modal.dart';
import 'widgets/about_modal.dart';
import 'screens/status_screen.dart';
import 'screens/cells_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/welcome_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve the Supporter (ad-removal) entitlement during startup, concurrently
  // with the theme load, so the first frame already knows whether this copy is
  // ad-free. Both futures are safe to await: the entitlement lookup is bounded
  // by EntitlementService.billingTimeout per call, swallows every Play failure
  // (offline, no Play services, missing product) and resolves to "not
  // entitled" — so a broken store delays the app by seconds at worst, and
  // never crashes or blocks it.
  final themeLoad = ThemeService().init();
  final entitlementLoad = EntitlementService.instance.resolve();
  await Future.wait([themeLoad, entitlementLoad]);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF090D10),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const JkbmsrBleApp());
}

class JkbmsrBleApp extends StatelessWidget {
  const JkbmsrBleApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = ThemeService();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeService.themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'JK BMS Local',
          debugShowCheckedModeBanner: false,
          // Follow the active theme so the status-bar icons never disappear
          // over a light header (they were hardcoded light in main()).
          builder: (context, child) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor:
                    isDark ? const Color(0xFF090D10) : const Color(0xFFF1F5F9),
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF8FAFC),
            primaryColor: const Color(0xFF10B981),
            cardColor: const Color(0xFFFFFFFF),
            dividerColor: const Color(0xFFE2E8F0),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.light().textTheme,
            ),
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF10B981),
              secondary: Color(0xFF0284C7),
              surface: Color(0xFFFFFFFF),
              error: Color(0xFFEF4444),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF090D10),
            primaryColor: const Color(0xFF10B981),
            cardColor: const Color(0xFF131A20),
            dividerColor: const Color(0xFF1E2830),
            textTheme: GoogleFonts.plusJakartaSansTextTheme(
              ThemeData.dark().textTheme,
            ),
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF10B981),
              secondary: Color(0xFF38BDF8),
              surface: Color(0xFF131A20),
              error: Color(0xFFEF4444),
            ),
          ),
          home: const MainHomeScreen(),
        );
      },
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  final _bleService = BleBmsService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  NavTab _currentTab = NavTab.status;

  // First-run gate: show the welcome screen until a BMS has been connected
  // at least once (a remembered last-device id exists) or the user proceeds.
  bool _showWelcome = true;
  bool _welcomeChecked = false;

  // Key to force recreation/relock of screens when tab is changed
  int _tabChangeCounter = 0;

  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  bool _bluetoothOff = false;

  @override
  void initState() {
    super.initState();
    _adapterStateSub = _bleService.adapterStateStream.listen((state) {
      if (!mounted) return;
      setState(() => _bluetoothOff = state != BluetoothAdapterState.on);
    });
    // Attempt to reconnect to whichever BMS was connected last session.
    _bleService.autoReconnectLastDevice().then((_) {
      if (mounted) setState(() {});
    });
    // Gate the welcome screen on whether a BMS has ever been connected.
    _bleService.getLastDeviceId().then((id) {
      if (!mounted) return;
      setState(() {
        _showWelcome = id == null;
        _welcomeChecked = true;
      });
    });
  }

  @override
  void dispose() {
    _adapterStateSub?.cancel();
    super.dispose();
  }

  void _switchTab(NavTab newTab) {
    if (_currentTab != newTab) {
      setState(() {
        _currentTab = newTab;
        _tabChangeCounter++; // Automatically causes child screens to re-lock
      });
    }
  }

  String _getTabTitle(NavTab tab) {
    switch (tab) {
      case NavTab.status:
        return 'STATUS';
      case NavTab.cells:
        return 'CELLS';
      case NavTab.devices:
        return 'DEVICES';
      case NavTab.settings:
        return 'SETTINGS';
    }
  }

  void _showSoftwareUpdateModal() {
    showDialog(
      context: context,
      builder: (ctx) => SoftwareUpdateModal(onClose: () => Navigator.pop(ctx)),
    );
  }

  void _showSupportModal() {
    showDialog(
      context: context,
      builder: (ctx) => SupportModal(onClose: () => Navigator.pop(ctx)),
    );
  }

  void _showAboutModal() {
    showDialog(
      context: context,
      builder: (ctx) => AboutModal(onClose: () => Navigator.pop(ctx)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _bleService.isConnected;
    final BluetoothDevice? device = _bleService.connectedDevice;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // First-run welcome gate: never hide the main UI entirely (auto-reconnect
    // may be mid-flight), but overlay the welcome screen until dismissed.
    if (!_welcomeChecked || _showWelcome) {
      return Stack(
        children: [
          _buildMainScaffold(isConnected: isConnected, device: device, isDark: isDark),
          if (_showWelcome)
            WelcomeScreen(
              onStartScanning: () {
                setState(() {
                  _showWelcome = false;
                  _welcomeChecked = true;
                  _currentTab = NavTab.devices;
                  _tabChangeCounter++;
                });
              },
            ),
        ],
      );
    }
    return _buildMainScaffold(isConnected: isConnected, device: device, isDark: isDark);
  }

  Widget _buildMainScaffold({
    required bool isConnected,
    required BluetoothDevice? device,
    required bool isDark,
  }) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? const Color(0xFF090D10) : const Color(0xFFF8FAFC),
      drawer: BmsDrawer(
        onNavigateToDevices: () => _switchTab(NavTab.devices),
        onOpenSoftwareUpdate: _showSoftwareUpdateModal,
        onOpenSupport: _showSupportModal,
        onOpenAbout: _showAboutModal,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // TOP APPLICATION HEADER
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF090D10) : const Color(0xFFFFFFFF),
                    border: Border(
                      bottom: BorderSide(
                        color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => _scaffoldKey.currentState?.openDrawer(),
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Center(
                                child: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF131A20) : const Color(0xFFF1F5F9),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.menu_rounded,
                                    color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                    size: 20,
                                    // The InkWell carries no label of its own;
                                    // this is what a screen reader announces.
                                    semanticLabel: 'Open menu',
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getTabTitle(_currentTab),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.4,
                                  color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
                                ),
                              ),
                              Text(
                                isConnected && device != null
                                    ? device.remoteId.str
                                    : 'DISCONNECTED',
                                style: const TextStyle(
                                  fontSize: 11.0,
                                  fontFamily: 'monospace',
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => _switchTab(NavTab.devices),
                            child: SizedBox(
                              height: 48,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: isConnected
                                        ? const Color(0xFF064E3B)
                                        : isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isConnected
                                          ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                          : const Color(0xFF64748B).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.bluetooth_rounded,
                                        size: 14,
                                        color: isConnected ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        isConnected ? 'ON' : 'OFF',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: isConnected ? const Color(0xFF10B981) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'More options',
                            icon: const Icon(Icons.more_vert_rounded, color: Color(0xFF64748B)),
                            onPressed: () => _switchTab(NavTab.devices),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // BLUETOOTH DISABLED NOTICE
                if (_bluetoothOff)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.bluetooth_disabled_rounded, color: Color(0xFFEF4444), size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Bluetooth is off. Turn it on to scan for BMS devices.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFEF4444)),
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            try {
                              await FlutterBluePlus.turnOn();
                            } catch (_) {}
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                          ),
                          child: const Text(
                            'TURN ON',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),

                // MAIN CONTENT VIEW (Keyed with _tabChangeCounter to automatically re-lock when switching screens)
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('tab_${_currentTab.name}_$_tabChangeCounter'),
                    child: _buildCurrentTabContent(),
                  ),
                ),
              ],
            ),

            // BOTTOM FLOATING NAVIGATION BAR
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: BottomNavBar(
                currentTab: _currentTab,
                onTabSelect: _switchTab,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTabContent() {
    switch (_currentTab) {
      case NavTab.status:
        return const StatusScreen();
      case NavTab.cells:
        return const CellsScreen();
      case NavTab.settings:
        return const SettingsScreen();
      case NavTab.devices:
        return DevicesScreen(
          onConnected: () => _switchTab(NavTab.status),
        );
    }
  }
}
