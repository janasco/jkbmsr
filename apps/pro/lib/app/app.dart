import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/api_client.dart';
import '../widgets/shared/design_system/colors.dart';
import '../widgets/shared/design_system/components.dart';
import '../widgets/shared/design_system/jkbmsr_bottom_nav.dart';
import 'back_intent.dart';

/// The root layout shell for the JK BMS Remote app.
/// Implements a responsive and unified layout frame.
class JKBMSRShellLayout extends StatefulWidget {
  final Widget child;
  final String currentRoute;
  final Function(String) onNavigate;

  const JKBMSRShellLayout({
    Key? key,
    required this.child,
    required this.currentRoute,
    required this.onNavigate,
  }) : super(key: key);

  @override
  State<JKBMSRShellLayout> createState() => _JKBMSRShellLayoutState();
}

class _JKBMSRShellLayoutState extends State<JKBMSRShellLayout> {
  int _getSelectedIndex() {
    final r = widget.currentRoute;
    if (r.startsWith('/cells')) return 1;
    if (r.startsWith('/alerts')) return 2;
    if (r.startsWith('/settings') || r.startsWith('/ota') || r.startsWith('/firmware')) return 3;
    if (r.startsWith('/devices')) return -1; // gateway list — not one of the four tabs
    return 0; // Dashboard (and /history, which is dashboard-scoped)
  }

  // Routes that are scoped to a single gateway — navigating between them
  // should carry the currently-selected deviceId forward instead of falling
  // back to "first gateway in the account" (which silently swaps to a
  // different gateway's data on any multi-gateway account). /devices (the
  // gateway list) and /alerts (account-wide, not per-gateway) are
  // deliberately excluded.
  static const _deviceScopedRoutes = {'/dashboard', '/cells', '/ota', '/settings', '/history'};

  String _routeWithDevice(String route) {
    if (!_deviceScopedRoutes.contains(route)) return route;
    final selectedDeviceId = Uri.tryParse(widget.currentRoute)?.queryParameters['deviceId'];
    if (selectedDeviceId == null) return route;
    return '$route?deviceId=${Uri.encodeComponent(selectedDeviceId)}';
  }

  void _onBottomNavTapped(int index) {
    switch (index) {
      case 0:
        widget.onNavigate(_routeWithDevice('/dashboard'));
        break;
      case 1:
        widget.onNavigate(_routeWithDevice('/cells'));
        break;
      case 2:
        widget.onNavigate(_routeWithDevice('/alerts'));
        break;
      case 3:
        widget.onNavigate(_routeWithDevice('/settings'));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTablet = size.width >= 600;

    // The single back guard for the whole shell. It has to live here, inside
    // the shell route, or the Android back button never reaches it (a PopScope
    // in MaterialApp.builder has no ModalRoute; and go_router's popRoute only
    // consults a PopScope when a Navigator canPop, so the guard also observes
    // didPopRoute — see JKBMSRBackGuard).
    return JKBMSRBackGuard(
      child: Scaffold(
        appBar: isTablet
            ? null
            : JKBMSRNavigationBar(
                title: _getAppBarTitle(),
                actions: [
                  IconButton(
                    icon: Icon(Icons.search, color: context.colors.textSecondary),
                    tooltip: 'Search gateways',
                    onPressed: () => _openSearch(context),
                  ),
                ],
              ),
        body: Row(
          children: [
            if (isTablet)
              JKBMSRSidebar(
                currentRoute: widget.currentRoute,
                onNavigate: (route) => widget.onNavigate(_routeWithDevice(route)),
              ),
            Expanded(
              child: widget.child,
            ),
          ],
        ),
        bottomNavigationBar: isTablet
            ? null
            : JKBMSRBottomNav(
                selectedIndex: _getSelectedIndex(),
                onTap: _onBottomNavTapped,
                items: const [
                  JKBMSRBottomNavItem(icon: Icons.home_outlined, label: 'Dashboard'),
                  JKBMSRBottomNavItem(icon: Icons.grid_view_rounded, label: 'Cells'),
                  JKBMSRBottomNavItem(icon: Icons.notifications_none, label: 'Alerts'),
                  JKBMSRBottomNavItem(icon: Icons.settings_outlined, label: 'Settings'),
                ],
              ),
      ),
    );
  }

  String _getAppBarTitle() {
    final r = widget.currentRoute;
    if (r.startsWith('/cells')) return 'Cell Voltages';
    if (r.startsWith('/alerts')) return 'Alerts';
    if (r.startsWith('/ota')) return 'Firmware & OTA';
    if (r.startsWith('/firmware')) return 'Firmware Releases';
    if (r.startsWith('/settings')) return 'Settings';
    if (r.startsWith('/history')) return 'Cloud History';
    if (r.startsWith('/devices')) return 'Gateways';
    return 'Dashboard';
  }

  // Opens the search sheet immediately (the previous command palette was just
  // five nav strings — a duplicate of the bottom nav). Gateways are fetched
  // live inside the sheet and merged in ahead of those quick-nav actions; the
  // sheet opens with the actions already in place so a slow or failed fetch
  // never leaves the user staring at an empty palette.
  void _openSearch(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _GatewaySearchSheet(
          routeWithDevice: _routeWithDevice,
          onNavigate: widget.onNavigate,
        );
      },
    );
  }
}

/// One row in the search sheet: a label to filter on and the route to open.
class _SearchEntry {
  final String label;
  final String route;

  const _SearchEntry(this.label, this.route);
}

/// Search sheet body: quick-nav actions are available from the first frame and
/// the user's gateways are added above them as soon as `getDevices()` returns.
class _GatewaySearchSheet extends StatefulWidget {
  final String Function(String route) routeWithDevice;
  final Function(String route) onNavigate;

  const _GatewaySearchSheet({
    Key? key,
    required this.routeWithDevice,
    required this.onNavigate,
  }) : super(key: key);

  @override
  State<_GatewaySearchSheet> createState() => _GatewaySearchSheetState();
}

class _GatewaySearchSheetState extends State<_GatewaySearchSheet> {
  List<_SearchEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries = _navEntries();
    _loadGateways();
  }

  List<_SearchEntry> _navEntries() => [
        _SearchEntry('Go to Dashboard', widget.routeWithDevice('/dashboard')),
        _SearchEntry('View Cell Voltages', widget.routeWithDevice('/cells')),
        _SearchEntry('Check Alerts', widget.routeWithDevice('/alerts')),
        _SearchEntry('Firmware & OTA', widget.routeWithDevice('/ota')),
        _SearchEntry('Settings', widget.routeWithDevice('/settings')),
      ];

  Future<void> _loadGateways() async {
    List<Device> devices = [];
    try {
      devices = await APIClient().getDevices();
    } catch (_) {
      // Offline/unauthenticated — fall through to the nav actions only.
    }
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final device in devices)
          _SearchEntry(
            '${device.name} · ${device.id}',
            '/dashboard?deviceId=${Uri.encodeComponent(device.id)}',
          ),
        ..._navEntries(),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return JKBMSRCommandPalette<_SearchEntry>(
      items: _entries,
      itemToString: (entry) => entry.label,
      onSelected: (entry) {
        Navigator.of(context).pop();
        widget.onNavigate(entry.route);
      },
      placeholder: 'Search gateways...',
    );
  }
}
