import 'package:flutter/material.dart';
import '../services/security_service.dart';
import '../services/theme_service.dart';
import '../widgets/auth_pin_dialog.dart';
import '../widgets/motion_kit.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _themeService = ThemeService();
  final _security = SecurityService();

  // Per-field lock state. Nothing here is persisted — every field starts
  // locked again on app relaunch, and a field re-locks itself the moment
  // it's saved.
  final Set<String> _unlockedFields = {};
  final Set<String> _savingFields = {};

  static const String _pinFieldKey = 'security_pin';

  final _newPinController = TextEditingController();

  @override
  void dispose() {
    _newPinController.dispose();
    super.dispose();
  }

  void _unlockField(String fieldKey) {
    showDialog(
      context: context,
      builder: (ctx) => AuthPinDialog(
        target: 'SETTINGS',
        onVerifyPin: (enteredPin) => _security.verifyPin(enteredPin),
        onVerified: (enteredPin) {
          setState(() => _unlockedFields.add(fieldKey));
          Navigator.pop(ctx);
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _savePinField() async {
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
    setState(() => _savingFields.add(_pinFieldKey));
    await _security.setPin(newPin);
    _newPinController.clear();
    if (!mounted) return;
    setState(() {
      _savingFields.remove(_pinFieldKey);
      _unlockedFields.remove(_pinFieldKey);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Security PIN updated.'),
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

              // SECURITY PIN (gates Control tab's switches)
              TileEntrance(
                delayIndex: 1,
                child: _buildSettingsGroup(
                context: context,
                title: 'Security PIN',
                icon: Icons.password_rounded,
                iconColor: const Color(0xFFF59E0B),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newPinController,
                          enabled: _unlockedFields.contains(_pinFieldKey),
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
                      _buildLockIcon(_pinFieldKey, _savePinField),
                    ],
                  ),
                ],
              ),
              ),
              const SizedBox(height: 14),

              // BMS hardware configuration (cell count, capacity, balance
              // and protection thresholds) lives in the "BMS parameters"
              // drawer entry (BmsParametersScreen) — enabled only for brands
              // with a verified settings read/write path (JK02, Daly, KS).
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

  /// Small per-row lock/save control: closed padlock (locked, tap prompts
  /// PIN entry) <-> open padlock (unlocked, tap saves the field's current
  /// value and re-locks it). Nothing here persists across app restarts.
  Widget _buildLockIcon(String fieldKey, Future<void> Function() onSave) {
    final isUnlocked = _unlockedFields.contains(fieldKey);
    final isSaving = _savingFields.contains(fieldKey);

    if (isSaving) {
      return const SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
        ),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        tooltip: isUnlocked ? 'Save & lock' : 'Unlock to edit',
        icon: Icon(isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
        color: isUnlocked ? const Color(0xFF10B981) : const Color(0xFF64748B),
        onPressed: isUnlocked ? () => onSave() : () => _unlockField(fieldKey),
      ),
    );
  }
}
