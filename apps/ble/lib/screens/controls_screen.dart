import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import '../services/ble_service.dart';
import '../services/theme_service.dart';
import '../widgets/motion_kit.dart';
import 'bms_parameters_screen.dart';
import 'control_screen.dart';

/// The merged hardware surface: MOSFET switch toggles and the BMS parameters
/// editor, presented as two clearly-labelled inner sections on one tab.
///
/// Security is unchanged: neither section prompts on entry, and opening this
/// tab, switching sections, or browsing live values never asks for the PIN.
/// The PIN is demanded only on each section's own write path (see
/// `ControlScreen._ensureWriteAccess` and `BmsParametersScreen._unlockParameter`).
class ControlsScreen extends StatefulWidget {
  /// Optional shortcut offered by the no-BMS empty state. When null the
  /// button is omitted (the status message still renders).
  final VoidCallback? onNavigateToDevices;

  const ControlsScreen({super.key, this.onNavigateToDevices});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

enum _ControlsSection { switches, parameters }

class _ControlsScreenState extends State<ControlsScreen> {
  final _bleService = BleBmsService();
  _ControlsSection _section = _ControlsSection.switches;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<BmsStatus>(
      stream: _bleService.statusStream,
      initialData: _bleService.currentStatus,
      builder: (context, snapshot) {
        if (!_bleService.isConnected) {
          return _NoBmsState(onNavigateToDevices: widget.onNavigateToDevices);
        }

        return JkAmbientBackground(
          child: Column(
            children: [
              _buildSectionSelector(context),
              Expanded(
                child: _section == _ControlsSection.switches
                    ? const ControlScreen(embedded: true)
                    : const BmsParametersScreen(embedded: true),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionSelector(BuildContext context) {
    final borderColor = AppColors.borderColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.bgNested(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            _buildSectionOption(
              context: context,
              label: 'SWITCHES',
              icon: Icons.toggle_on_rounded,
              section: _ControlsSection.switches,
            ),
            _buildSectionOption(
              context: context,
              label: 'PARAMETERS',
              icon: Icons.tune_rounded,
              section: _ControlsSection.parameters,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionOption({
    required BuildContext context,
    required String label,
    required IconData icon,
    required _ControlsSection section,
  }) {
    final isSelected = _section == section;
    final onColor = isSelected ? const Color(0xFF090D10) : AppColors.textMuted(context);
    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (_section == section) return;
            setState(() => _section = section);
          },
          child: SizedBox(
            height: 46,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 15, color: onColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: onColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Honest empty state for the Controls tab when nothing is connected: there is
/// no hardware to show controls for, so it says exactly that rather than
/// rendering an empty or half-built layout.
class _NoBmsState extends StatelessWidget {
  final VoidCallback? onNavigateToDevices;

  const _NoBmsState({this.onNavigateToDevices});

  @override
  Widget build(BuildContext context) {
    return JkAmbientBackground(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.bluetooth_disabled_rounded,
                  color: Color(0xFF64748B),
                  size: 32,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Connect to a BMS to use controls',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a device on the Devices tab first. Switch toggles and '
                'BMS parameters become available once a battery is connected.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: AppColors.textMuted(context),
                ),
              ),
              if (onNavigateToDevices != null) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: const Color(0xFF090D10),
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: onNavigateToDevices,
                  icon: const Icon(Icons.bluetooth_searching_rounded, size: 18),
                  label: const Text('GO TO DEVICES',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w900)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
