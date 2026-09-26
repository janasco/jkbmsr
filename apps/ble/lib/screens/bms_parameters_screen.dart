import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import '../models/bms_parameter.dart';
import '../services/ble_service.dart';
import '../services/security_service.dart';
import '../widgets/auth_pin_dialog.dart';
import '../widgets/motion_kit.dart';

/// Live editor for the connected BMS's configuration parameters (JK02
/// settings frame / Daly holding registers / KS config frames).
///
/// This is only enabled for brands whose settings read + write path has been
/// byte-verified against the syssi/esphome-*-bms component sources — the
/// values shown come from real decoded hardware frames (`settingsStream`),
/// never placeholders, and writes go through `BleBmsService.writeParameter`.
class BmsParametersScreen extends StatefulWidget {
  const BmsParametersScreen({super.key});

  @override
  State<BmsParametersScreen> createState() => _BmsParametersScreenState();
}

class _BmsParametersScreenState extends State<BmsParametersScreen> {
  final _bleService = BleBmsService();
  final _security = SecurityService();

  final Set<String> _unlockedIds = {};
  final Set<String> _savingIds = {};

  List<BmsParameter>? get _parameters {
    final brand = _bleService.connectedBrand;
    return BmsParameterSchema.forBrand(brand);
  }

  void _unlockParameter(BmsParameter p) {
    showDialog(
      context: context,
      builder: (ctx) => AuthPinDialog(
        target: 'BMS PARAMETERS',
        onVerifyPin: (enteredPin) => _security.verifyPin(enteredPin),
        onVerified: (enteredPin) {
          setState(() => _unlockedIds.add(p.id));
          Navigator.pop(ctx);
        },
        onDismiss: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _editParameter(BmsParameter p) async {
    final current = _bleService.currentSettings.valueFor(p);
    final controller = TextEditingController(
      text: current == null ? '' : _formatValue(p, current),
    );

    if (p.type == BmsParameterType.choice) {
      await _showChoiceEditor(p, current);
      return;
    }

    final entered = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          p.label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          decoration: InputDecoration(
            labelText: 'Value (${p.unit.isEmpty ? '-' : p.unit})',
            helperText: 'Range ${_formatValue(p, p.minValue)} – ${_formatValue(p, p.maxValue)}',
            helperStyle: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.trim())),
            child: const Text('WRITE TO BMS'),
          ),
        ],
      ),
    );
    if (entered == null) return;
    await _saveParameter(p, entered.clamp(p.minValue, p.maxValue));
  }

  Future<void> _showChoiceEditor(BmsParameter p, double? current) async {
    final options = p.options ?? const [];
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(p.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++)
              ListTile(
                dense: true,
                leading: Icon(
                  current?.toInt() == i ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: current?.toInt() == i ? const Color(0xFF10B981) : const Color(0xFF64748B),
                  size: 20,
                ),
                title: Text(options[i], style: const TextStyle(fontSize: 13)),
                onTap: () => Navigator.pop(ctx, i),
              ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (selected == null) return;
    await _saveParameter(p, selected.toDouble());
  }

  Future<void> _saveParameter(BmsParameter p, double value) async {
    setState(() => _savingIds.add(p.id));
    final ok = await _bleService.writeParameter(p, value);
    if (!mounted) return;
    setState(() {
      _savingIds.remove(p.id);
      if (ok) _unlockedIds.remove(p.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      ok
          ? SnackBar(
              content: Text(
                  '${p.label}: ${value.toStringAsFixed(2)} ${p.unit} sent to hardware.'),
              backgroundColor: const Color(0xFF10B981),
            )
          : const SnackBar(
              content: Text(
                  'Not sent — this parameter isn\'t supported on this BMS, or the write failed.'),
              backgroundColor: Color(0xFFEF4444),
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

    final brand = _bleService.connectedBrand;
    final hasLiveData = _bleService.hasLiveData;
    final params = _parameters;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090D10) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF090D10) : const Color(0xFFFFFFFF),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('BMS PARAMETERS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
        actions: [
          IconButton(
            tooltip: 'Sync from hardware',
            icon: const Icon(Icons.sync_rounded),
            onPressed: hasLiveData ? () => _bleService.requestSettings() : null,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: StreamBuilder<BmsSettingsSnapshot>(
          stream: _bleService.settingsStream,
          initialData: _bleService.currentSettings,
          builder: (context, snapshot) {
            final settings = snapshot.data ?? _bleService.currentSettings;

            if (brand == BmsBrand.unknown || params == null || params.isEmpty) {
              return _buildUnsupported(brand, textPrimary, cardBg, borderColor);
            }

            if (!hasLiveData) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bluetooth_searching_rounded, size: 40, color: const Color(0xFF10B981)),
                      const SizedBox(height: 12),
                      Text(
                        'Connect to a ${brand.name.toUpperCase()} BMS first',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Live settings appear here once telemetry is flowing.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              );
            }

            final groups = <String, List<BmsParameter>>{};
            for (final p in params) {
              groups.putIfAbsent(p.group, () => []).add(p);
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              physics: const BouncingScrollPhysics(),
              child: StaggerIn(
                stepMs: 55,
                children: [
                  if (settings.values.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.25)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.sync_problem_rounded, color: Color(0xFFF59E0B), size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Waiting for the settings frame — tap Sync to request it now.',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFF59E0B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  for (final group in groups.keys) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 2, top: 16, bottom: 8),
                      child: Text(
                        group.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < groups[group]!.length; i++)
                            _buildParameterRow(
                              groups[group]![i],
                              settings,
                              textPrimary,
                              nestedBg,
                              borderColor,
                              divider: i < groups[group]!.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Values are read from real hardware frames and written with the verified ${brand.name.toUpperCase()} command path.',
                    style: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildParameterRow(
    BmsParameter p,
    BmsSettingsSnapshot settings,
    Color textPrimary,
    Color nestedBg,
    Color borderColor, {
    required bool divider,
  }) {
    final value = settings.valueFor(p);
    final isUnlocked = _unlockedIds.contains(p.id);
    final isSaving = _savingIds.contains(p.id);

    return Container(
      decoration: BoxDecoration(
        border: divider
            ? Border(bottom: BorderSide(color: borderColor, width: 0.5))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.label,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatParameterValue(p, value),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: value == null ? const Color(0xFF64748B) : const Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isSaving)
            const SizedBox(
              width: 32,
              height: 32,
              child: Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF10B981)),
              ),
            )
          else ...[
            _LockButton(
              unlocked: isUnlocked,
              onPressed: isUnlocked
                  ? () => _editParameter(p)
                  : () => _unlockParameter(p),
            ),
            if (!isUnlocked)
              Tooltip(
                message: 'Unlock with PIN to edit',
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: nestedBg, borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.edit_rounded, size: 16, color: const Color(0xFF64748B)),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _formatParameterValue(BmsParameter p, double? value) {
    if (value == null) return p.type == BmsParameterType.choice ? 'Not read yet' : '—';
    if (p.type == BmsParameterType.choice) {
      final options = p.options ?? const [];
      final idx = value.toInt();
      return (idx >= 0 && idx < options.length) ? options[idx] : 'Option $idx';
    }
    return p.type == BmsParameterType.toggle
        ? (value >= 0.5 ? 'On' : 'Off')
        : '${_formatValue(p, value)}${p.unit.isEmpty ? '' : ' ${p.unit}'}';
  }

  String _formatValue(BmsParameter p, double value) {
    final rawDecimals = p.step >= 1 || p.step == 0
        ? 0
        : p.step >= 0.1
            ? 1
            : 3;
    final decimals = rawDecimals.clamp(0, 4).toInt();
    return value.toStringAsFixed(decimals);
  }

  Widget _buildUnsupported(BmsBrand brand, Color textPrimary, Color cardBg, Color borderColor) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.settings_input_component_rounded, size: 38, color: const Color(0xFF64748B)),
              const SizedBox(height: 12),
              Text(
                brand == BmsBrand.unknown ? 'No BMS connected' : 'Settings not supported',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                brand.isPublic
                    ? "This JK-BMS firmware doesn't expose a verified settings read/write path. "
                        'JK BMS Remote will not send unverified command bytes to your battery.'
                    : 'JK BMS Remote supports JK-BMS only. Live parameter editing is not '
                        'available for this battery system.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockButton extends StatelessWidget {
  final bool unlocked;
  final VoidCallback onPressed;

  const _LockButton({required this.unlocked, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 20,
        tooltip: unlocked ? 'Edit value' : 'Unlock to edit',
        icon: Icon(unlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded),
        color: unlocked ? const Color(0xFF10B981) : const Color(0xFF64748B),
        onPressed: onPressed,
      ),
    );
  }
}