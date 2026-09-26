import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bms_models.dart';
import '../services/ble_service.dart';
import '../services/security_service.dart';
import '../widgets/auth_pin_dialog.dart';
import '../widgets/info_banner.dart';
import '../widgets/motion_kit.dart';

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  final _bleService = BleBmsService();
  final _security = SecurityService();
  bool _isUnlocked = false;
  String _pin = '1234';

  void _requestUnlock() {
    if (!_bleService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connect a BMS from the Devices tab before unlocking controls.'),
          backgroundColor: Color(0xFFF59E0B),
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AuthPinDialog(
        target: 'CONTROL',
        onVerifyPin: (enteredPin) => _security.verifyPin(enteredPin),
        onVerified: (enteredPin) {
          setState(() {
            _isUnlocked = true;
            _pin = enteredPin;
          });
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Controls Unlocked!'),
              backgroundColor: Color(0xFF10B981),
            ),
          );
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    );
  }

  void _handleToggle(String switchKey, bool currentValue, {bool? peerMosEnabled}) async {
    if (!_isUnlocked) {
      _requestUnlock();
      return;
    }

    final newValue = !currentValue;
    HapticFeedback.mediumImpact();
    final ok = await _bleService.toggleSwitch(switchKey, newValue, _pin, peerMosEnabled: peerMosEnabled);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      ok
          ? SnackBar(
              content: Text('$switchKey toggled to ${newValue ? 'ON' : 'OFF'}'),
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 1),
            )
          : SnackBar(
              content: Text(
                  'Not sent — $switchKey isn\'t supported on this BMS, or the write failed.'),
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 3),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    return StreamBuilder<BmsStatus>(
      stream: _bleService.statusStream,
      initialData: _bleService.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data ?? _bleService.currentStatus;
        final isConnected = _bleService.isConnected;
        final brand = _bleService.connectedBrand;
        final capabilities = isConnected ? BmsCapabilities.forBrand(brand) : const BmsCapabilities();

        // Controls re-lock whenever the BMS disconnects — an unlock from a
        // previous session shouldn't silently carry over to a new device.
        if (!isConnected && _isUnlocked) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isUnlocked = false);
          });
        }

        final switchConfigs = <_SwitchItem>[
          if (capabilities.canToggleCharge)
            _SwitchItem(key: 'charge', label: 'Charge Switch', desc: 'Enable battery charge MOSFET', isChecked: status.chargeMosEnabled),
          if (capabilities.canToggleDischarge)
            _SwitchItem(key: 'discharge', label: 'Discharge Switch', desc: 'Enable load discharge MOSFET', isChecked: status.dischargeMosEnabled),
          if (capabilities.canToggleBalance)
            _SwitchItem(key: 'balance', label: 'Balance Switch', desc: 'Enable active cell balancing', isChecked: status.balanceEnabled),
        ];

        return JkAmbientBackground(
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SECURITY BANNER (Properly aligned with responsive flex)
              TileEntrance(
                delayIndex: 0,
                child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isUnlocked
                      ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFFDCFCE7))
                      : cardBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _isUnlocked
                        ? const Color(0xFF10B981).withValues(alpha: 0.5)
                        : isConnected
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
                            : borderColor,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _isUnlocked
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : isConnected
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.2)
                                : const Color(0xFF64748B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _isUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                        color: _isUnlocked
                            ? const Color(0xFF10B981)
                            : isConnected
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF64748B),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isUnlocked ? 'CONTROL UNLOCKED' : 'CONTROL LOCKED',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: _isUnlocked
                                  ? const Color(0xFF10B981)
                                  : isConnected
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF64748B),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isUnlocked
                                ? 'PIN verified. You can toggle switches.'
                                : isConnected
                                    ? 'Security PIN required to alter MOSFETs.'
                                    : 'Connect a BMS to unlock controls.',
                            style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isUnlocked
                            ? const Color(0xFF10B981).withValues(alpha: 0.2)
                            : isConnected
                                ? const Color(0xFFF59E0B)
                                : (isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0)),
                        foregroundColor: _isUnlocked
                            ? const Color(0xFF10B981)
                            : isConnected
                                ? const Color(0xFF090D10)
                                : const Color(0xFF64748B),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        elevation: _isUnlocked || !isConnected ? 0 : 2,
                      ),
                      onPressed: _isUnlocked
                          ? () => setState(() => _isUnlocked = false)
                          : isConnected
                              ? _requestUnlock
                              : null,
                      child: Text(
                        _isUnlocked ? 'LOCK' : 'UNLOCK',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
              ),
              const SizedBox(height: 18),

              if (!isConnected)
                const InfoBanner(
                  icon: Icons.bluetooth_disabled_rounded,
                  title: 'NO BMS CONNECTED',
                  message: 'Connect to a BMS from the Devices tab to see its available controls.',
                )
              else if (!capabilities.hasAnyControl)
                InfoBanner(
                  icon: Icons.visibility_rounded,
                  title: 'MONITORING ONLY',
                  message: brand.isPublic
                      ? "Live control isn't supported for this firmware yet — you can still view telemetry on the Status tab."
                      : 'JK BMS Remote supports JK-BMS only. This device was identified as an '
                          'unsupported battery system, so it is read-only here and no '
                          'commands will be sent to it.',
                )
              else ...[
                // SWITCHES LIST
                TileEntrance(
                  delayIndex: 1,
                  child: const Text(
                    'BMS CONTROL SWITCHES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: switchConfigs.length,
                itemBuilder: (context, idx) {
                  final item = switchConfigs[idx];
                  // JBD writes charge+discharge as one combined register, so
                  // toggling one must carry the other's current commanded
                  // state forward instead of clobbering it.
                  final peerMosEnabled = brand != BmsBrand.jbd
                      ? null
                      : (item.key == 'charge'
                          ? status.dischargeMosEnabled
                          : item.key == 'discharge'
                              ? status.chargeMosEnabled
                              : null);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TileEntrance(
                      delayIndex: 2 + idx,
                      child: _TactileSwitchRow(
                      onTap: () => _handleToggle(item.key, item.isChecked, peerMosEnabled: peerMosEnabled),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: item.isChecked
                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                : borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: textPrimary),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.desc,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: item.isChecked,
                              activeThumbColor: const Color(0xFF10B981),
                              activeTrackColor: const Color(0xFF064E3B),
                              inactiveThumbColor: const Color(0xFF64748B),
                              inactiveTrackColor: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0),
                              onChanged: (_) => _handleToggle(item.key, item.isChecked, peerMosEnabled: peerMosEnabled),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  );
                },
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      );
      },
    );
  }
}

class _SwitchItem {
  final String key;
  final String label;
  final String desc;
  final bool isChecked;

  _SwitchItem({
    required this.key,
    required this.label,
    required this.desc,
    required this.isChecked,
  });
}

/// Press-scale wrapper that makes the whole switch row feel tactile: it
/// compresses slightly while pressed, springs back on release, and fires a
/// medium haptic on tap so toggling registers in the hand. (Tapping the
/// Switch itself goes through Switch.onChanged — _handleToggle haptics
/// covers that path; only one of the two fires per interaction.)
class _TactileSwitchRow extends StatefulWidget {
  final VoidCallback onTap;
  final Widget child;

  const _TactileSwitchRow({required this.onTap, required this.child});

  @override
  State<_TactileSwitchRow> createState() => _TactileSwitchRowState();
}

class _TactileSwitchRowState extends State<_TactileSwitchRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

