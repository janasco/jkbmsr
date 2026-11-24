import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/simulation_claim.dart';
import '../../services/api_client.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';

/// A pack that does not exist, on purpose.
///
/// The value is learning on the interface someone will actually use: alarms, a
/// weak cell, a hot pack and a dropped link, without a real battery in the room.
/// Everything here is generated locally and read-only. Nothing is sent to a
/// gateway, and the only network call is the daily points claim.
///
/// The reward is deliberately close to nothing: 10 points a day, after a session
/// of at least a minute. A donated pack is worth 250. This is for patience, not a
/// way around the work.
class SimulationScreen extends StatefulWidget {
  const SimulationScreen({super.key, this.claimReward});

  /// Injectable so the screen can be tested without a network.
  final Future<SimulationClaimResult> Function(int seconds)? claimReward;

  @override
  State<SimulationScreen> createState() => _SimulationScreenState();
}

class _SimulationScreenState extends State<SimulationScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _running = false;

  _Mode _mode = _Mode.discharge;
  bool _weakCell = false;
  bool _overheated = false;
  bool _linkDropped = false;

  double _soc = 78.0;
  double _temperature = 28.0;
  final List<double> _cells = List<double>.filled(16, 3.32);
  int _weakCellIndex = 5;

  bool _claiming = false;
  String? _claimMessage;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _toggleRunning() {
    setState(() => _running = !_running);
    if (_running) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      // A paused session is paused: the clock and the readings stop, and a
      // paused minute must not unlock the claim.
      _timer?.cancel();
      _timer = null;
    }
  }

  /// One second of a pack that behaves plausibly, so the numbers move in a way
  /// worth reading rather than random noise: charging raises the voltage and the
  /// state of charge, discharging lowers both, and a hot pack drifts up.
  void _tick() {
    if (!mounted || !_running) return;
    setState(() {
      _elapsedSeconds += 1;
      if (_linkDropped) {
        // A dropped link means no readings change. That is the lesson: the screen
        // freezes, which is exactly what a real gateway looks like when the BLE
        // link dies while Wi-Fi is still up.
        _temperature = (_temperature + 0.05).clamp(20.0, 70.0);
        return;
      }

      final drift = _mode == _Mode.charge ? 0.0009 : _mode == _Mode.discharge ? -0.0009 : 0.0;
      for (var i = 0; i < _cells.length; i++) {
        final wobble = ((i * 7 + _elapsedSeconds) % 5 - 2) * 0.0004;
        _cells[i] = (_cells[i] + drift + wobble).clamp(2.6, 3.65);
      }
      _soc = (_soc + drift * 900).clamp(0.0, 100.0);
      _temperature = _overheated ? 58.0 : (_temperature + 0.02).clamp(20.0, 70.0);
    });
  }

  double get _packVoltage {
    var sum = 0.0;
    for (var i = 0; i < _cells.length; i++) {
      sum += i == _weakCellIndex && _weakCell ? _cells[i] - 0.22 : _cells[i];
    }
    return sum;
  }

  double get _currentA {
    switch (_mode) {
      case _Mode.charge:
        return 18.0;
      case _Mode.discharge:
        return -24.0;
      case _Mode.idle:
        return 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Simulate')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          children: [
            _banner(colors),
            const SizedBox(height: JKBMSRTokens.space12),
            _readings(colors),
            const SizedBox(height: JKBMSRTokens.space12),
            _cellsCard(colors),
            const SizedBox(height: JKBMSRTokens.space12),
            _controls(colors),
            const SizedBox(height: JKBMSRTokens.space12),
            _reward(colors),
          ],
        ),
      ),
    );
  }

  Widget _banner(dynamic colors) => Container(
        padding: const EdgeInsets.all(JKBMSRTokens.space12),
        decoration: BoxDecoration(
          color: colors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
          border: Border.all(color: colors.warning.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.science_outlined, size: 20, color: colors.warning),
            const SizedBox(width: JKBMSRTokens.space8),
            Expanded(
              child: Text(
                'Simulation. These numbers are made up. Nothing here touches a gateway '
                'or a real battery.',
                style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      );

  Widget _readings(dynamic colors) {
    String fmt(double value, int places) => value.toStringAsFixed(places);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pack', style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary)),
            const SizedBox(height: JKBMSRTokens.space8),
            Wrap(
              spacing: JKBMSRTokens.space16,
              runSpacing: JKBMSRTokens.space8,
              children: [
                _metric(colors, 'Voltage', '${fmt(_packVoltage, 2)} V'),
                _metric(colors, 'Current', '${fmt(_currentA, 0)} A'),
                _metric(colors, 'Charge', '${fmt(_soc, 0)} %'),
                _metric(colors, 'MOS temp', '${fmt(_temperature, 1)} °C'),
                _metric(colors, 'Link', _linkDropped ? 'down' : 'up'),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              _linkDropped
                  ? 'The battery link is down. The readings stop moving, which is what a '
                      'real gateway looks like when Bluetooth drops and Wi-Fi does not.'
                  : 'Run a session, then try a fault: a weak cell, heat, or a dropped link.',
              style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(dynamic colors, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted)),
          Text(
            value,
            style: JKBMSRTypography.body.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );

  Widget _cellsCard(dynamic colors) {
    final shown = [
      for (var i = 0; i < _cells.length; i++)
        i == _weakCellIndex && _weakCell ? _cells[i] - 0.22 : _cells[i],
    ];
    final min = shown.reduce((a, b) => a < b ? a : b);
    final max = shown.reduce((a, b) => a > b ? a : b);
    // With every cell at the same voltage, `shown[i] == min` is true for all of
    // them and the whole grid rendered critical red, which says "everything is
    // wrong" about a pack that is perfectly balanced. Colour is a signal, so it
    // only appears when there is something to signal.
    final hasSpread = (max - min) > 0.005;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cells', style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary)),
            const SizedBox(height: JKBMSRTokens.space8),
            Wrap(
              spacing: JKBMSRTokens.space8,
              runSpacing: JKBMSRTokens.space4,
              children: [
                for (var i = 0; i < shown.length; i++)
                  Text(
                    '${i + 1}: ${shown[i].toStringAsFixed(3)}',
                    style: JKBMSRTypography.monoTechnical.copyWith(
                      color: !hasSpread
                          ? colors.textPrimary
                          : shown[i] == min
                              ? colors.critical
                              : shown[i] == max
                                  ? colors.signal
                                  : colors.textPrimary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              'Weakest ${min.toStringAsFixed(3)} V, strongest ${max.toStringAsFixed(3)} V, '
              'spread ${((max - min) * 1000).toStringAsFixed(0)} mV.',
              style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(dynamic colors) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Session ${_elapsedSeconds}s',
                    style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary),
                  ),
                ),
                FilledButton(
                  onPressed: _toggleRunning,
                  child: Text(_running ? 'Pause' : 'Run'),
                ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            // Choice chips rather than a SegmentedButton: three labels as wide as
            // these do not fit one row at a phone's width, and a segmented control
            // breaks the long one mid-word ("Discha / rge"). A wrap moves whole
            // chips to a second line instead.
            Wrap(
              spacing: JKBMSRTokens.space8,
              children: [
                for (final mode in _Mode.values)
                  ChoiceChip(
                    label: Text(switch (mode) {
                      _Mode.charge => 'Charge',
                      _Mode.idle => 'Idle',
                      _Mode.discharge => 'Discharge',
                    }),
                    selected: _mode == mode,
                    onSelected: (_) => setState(() => _mode = mode),
                  ),
              ],
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Wrap(
              spacing: JKBMSRTokens.space8,
              runSpacing: JKBMSRTokens.space8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => setState(() => _weakCell = !_weakCell),
                  icon: const Icon(Icons.battery_alert_outlined, size: 18),
                  label: Text(_weakCell ? 'Weak cell (on)' : 'Weaken a cell'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _overheated = !_overheated),
                  icon: const Icon(Icons.local_fire_department_outlined, size: 18),
                  label: Text(_overheated ? 'Heat (on)' : 'Heat the pack'),
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => _linkDropped = !_linkDropped),
                  icon: const Icon(Icons.bluetooth_disabled, size: 18),
                  label: Text(_linkDropped ? 'Link (down)' : 'Drop the link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _reward(dynamic colors) {
    final canClaim = _elapsedSeconds >= 60 && !_claiming;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Today\'s points',
              style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: JKBMSRTokens.space4),
            Text(
              '10 points a day, once, after a session of a minute or more. Needs a gateway '
              'on your account, and stops at 300 points in total. A donated pack is worth '
              '250, so this is patience rather than a shortcut.',
              style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Row(
              children: [
                FilledButton(
                  onPressed: canClaim ? _claim : null,
                  child: Text(_claiming ? 'Claiming…' : 'Claim 10 points'),
                ),
                const SizedBox(width: JKBMSRTokens.space12),
                Expanded(
                  child: Text(
                    _claimMessage ??
                        (_elapsedSeconds >= 60
                            ? ''
                            : 'Run for another ${60 - _elapsedSeconds}s.'),
                    style: JKBMSRTypography.bodySecondary.copyWith(
                      color: _claimMessage == null ? colors.textMuted : colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claim() async {
    setState(() {
      _claiming = true;
      _claimMessage = null;
    });
    try {
      final result = await (widget.claimReward ?? _defaultClaim)(_elapsedSeconds);
      if (!mounted) return;
      setState(() {
        // The reason comes from the server, so the sentence cannot drift from the
        // rule that refused the claim.
        switch (result.reason) {
          case 'no gateway':
            _claimMessage = 'Claim a gateway on this account first. Points are only '
                'spendable on a gateway, so it is required before earning them here.';
          case 'lifetime cap reached':
            _claimMessage = 'You have reached the simulation limit of 300 points. '
                'Donated packs still earn.';
          default:
            _claimMessage = result.credited > 0
                ? '${result.credited} points added. Balance ${result.balance}.'
                : 'Already claimed today. Come back tomorrow.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _claimMessage = 'The claim failed. Your session is still counted, so try again.';
      });
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  Future<SimulationClaimResult> _defaultClaim(int seconds) =>
      APIClient().claimSimulationReward(seconds);
}

enum _Mode { charge, idle, discharge }
