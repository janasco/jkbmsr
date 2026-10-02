import 'package:flutter/material.dart';
import '../services/security_service.dart';
import '../services/theme_service.dart';
import '../widgets/motion_kit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _themeService = ThemeService();
  final _security = SecurityService();

  // Tracks the in-flight save of the control PIN so the button can show a
  // spinner. The PIN field itself is always editable: changing the app's own
  // (local, non-account) PIN is a preference, not a BMS write, so it is not
  // gated behind the control PIN. The write path still verifies the PIN
  // before any command reaches hardware.
  final Set<String> _savingFields = {};

  static const String _pinFieldKey = 'security_pin';

  final _newPinController = TextEditingController();

  @override
  void dispose() {
    _newPinController.dispose();
    super.dispose();
  }

  void _savePinField() {
    final newPin = _newPinController.text.trim();
    if (newPin.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN must be at least 4 characters.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }
    _persistPinField(newPin);
  }

  Future<void> _persistPinField(String newPin) async {
    setState(() => _savingFields.add(_pinFieldKey));
    await _security.setPin(newPin);
    _newPinController.clear();
    if (!mounted) return;
    setState(() => _savingFields.remove(_pinFieldKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Control PIN updated.'),
        backgroundColor: Color(0xFF10B981),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final nestedBg = isDark ? const Color(0xFF090D10) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeService.themeModeNotifier,
      builder: (context, themeMode, _) {
        // Reserve more bottom space as the floating nav bar grows with the
        // OS text scale, so it never overlaps the last content.
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

        return JkAmbientBackground(
          child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 120 + 62 * (textScale - 1)),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // APPEARANCE THEME SELECTOR
              TileEntrance(
                delayIndex: 0,
                child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'APPEARANCE THEME',
                      style: TextStyle(
                        fontSize: 11.0,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: nestedBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor),
                      ),
                      child: Row(
                        children: [
                          _buildThemeOption('SYSTEM', Icons.monitor_rounded, themeMode == ThemeMode.system, () {
                            _themeService.setThemeMode(ThemeMode.system);
                          }),
                          _buildThemeOption('LIGHT', Icons.wb_sunny_rounded, themeMode == ThemeMode.light, () {
                            _themeService.setThemeMode(ThemeMode.light);
                          }),
                          _buildThemeOption('DARK', Icons.nightlight_round, themeMode == ThemeMode.dark, () {
                            _themeService.setThemeMode(ThemeMode.dark);
                          }),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 14),

              // CONTROL PIN — an app-local gate on sending commands, not an
              // account. It is intentionally NOT required to view or change
              // any app preference: only a write to a connected BMS verifies
              // it (see ControlScreen / BmsParametersScreen).
              TileEntrance(
                delayIndex: 1,
                child: _buildSettingsGroup(
                context: context,
                title: 'Control PIN',
                icon: Icons.password_rounded,
                iconColor: const Color(0xFFF59E0B),
                children: [
                  const Text(
                    'Authorises control commands and parameter writes to a '
                    'connected BMS. It never blocks viewing or app settings.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B), height: 1.35),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newPinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                          decoration: InputDecoration(
                            hintText: 'New PIN (min. 4 digits)',
                            hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            filled: true,
                            fillColor: nestedBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: borderColor),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSavePinButton(),
                    ],
                  ),
                ],
              ),
              ),
              const SizedBox(height: 14),

              // BMS hardware configuration (cell count, capacity, balance
              // and protection thresholds) lives in the Controls tab
              // (BmsParametersScreen) — enabled only for brands with a
              // verified settings read/write path (JK02, Daly, KS).
            ],
          ),
        ),
      );
      },
    );
  }

  Widget _buildThemeOption(String mode, IconData icon, bool isSelected, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: SizedBox(
          height: 48,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 14, color: isSelected ? const Color(0xFF090D10) : const Color(0xFF64748B)),
                  const SizedBox(width: 4),
                  Text(
                    mode,
                    style: TextStyle(
                      fontSize: 11.0,
                      fontWeight: FontWeight.w900,
                      color: isSelected ? const Color(0xFF090D10) : const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsGroup({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 8),
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.9,
                  color: textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  /// Always-available save control for the local control PIN. There is no
  /// preceding unlock step: the field is editable and this button saves it.
  Widget _buildSavePinButton() {
    if (_savingFields.contains(_pinFieldKey)) {
      return const SizedBox(
        width: 64,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
          ),
        ),
      );
    }

    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: const Color(0xFF090D10),
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: _savePinField,
      child: const Text('SAVE', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
    );
  }
}

/// Navigation wrapper for the app-settings body, opened from the drawer's
/// "App settings" entry. [SettingsScreen] stays a pure body (it is mounted
/// directly by tests and could be re-hosted), so the Scaffold and back
/// affordance that a pushed route needs live here instead.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgCanvas(context),
      appBar: AppBar(
        backgroundColor: AppColors.bgCanvas(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.maybePop(context),
        ),
        title: const Text(
          'APP SETTINGS',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.1),
        ),
      ),
      body: const SettingsScreen(),
    );
  }
}
