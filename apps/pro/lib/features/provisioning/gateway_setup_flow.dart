import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import 'discovered_gateway.dart';
import 'gateway_provisioner.dart';

/// One zone per label, in the format the gateway can actually apply.
///
/// These are POSIX TZ strings, not IANA names: the ESP32 has no time zone
/// database and cannot resolve "Asia/Manila". A trailing rule-less form is
/// deliberate - a stable offset is easier to explain than a DST rule that
/// silently drifts.
class GatewayTimeZone {
  const GatewayTimeZone(this.label, this.posix);

  final String label;
  final String posix;

  static const all = <GatewayTimeZone>[
    GatewayTimeZone('UTC', 'UTC0'),
    GatewayTimeZone('Philippines, Singapore (UTC+8)', 'PST-8'),
    GatewayTimeZone('Japan, Korea (UTC+9)', 'JST-9'),
    GatewayTimeZone('India (UTC+5:30)', 'IST-5:30'),
    GatewayTimeZone('Central Europe (UTC+1/+2)', 'CET-1CEST,M3.5.0,M10.5.0/3'),
    GatewayTimeZone('United Kingdom (UTC+0/+1)', 'GMT0BST,M3.5.0/1,M10.5.0'),
    GatewayTimeZone('US Eastern (UTC-5/-4)', 'EST5EDT,M3.2.0,M11.1.0'),
    GatewayTimeZone('US Pacific (UTC-8/-7)', 'PST8PDT,M3.2.0,M11.1.0'),
    GatewayTimeZone('Australia, Sydney (UTC+10/+11)', 'AEST-10AEDT,M10.1.0,M4.1.0/3'),
  ];
}

enum _Step { code, network, connect }

class GatewaySetupFlow extends StatefulWidget {
  const GatewaySetupFlow({
    super.key,
    required this.gateway,
    this.provisioner,
  });

  final DiscoveredGateway gateway;
  final GatewayProvisioner? provisioner;

  @override
  State<GatewaySetupFlow> createState() => _GatewaySetupFlowState();
}

class _GatewaySetupFlowState extends State<GatewaySetupFlow> {
  late final GatewayProvisioner _provisioner =
      widget.provisioner ?? const UnavailableGatewayProvisioner();

  final _codeController = TextEditingController();
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  GatewayTimeZone _zone = GatewayTimeZone.all[1];

  _Step _step = _Step.code;
  bool _showPassword = false;
  bool _busy = false;
  String? _error;
  final Set<ProvisioningStage> _reached = {};
  StreamSubscription<ProvisioningStage>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    _codeController.dispose();
    _ssidController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool get _codeValid => _codeController.text.length == 6;
  bool get _networkValid => _ssidController.text.trim().isNotEmpty;

  void _next() {
    if (_step == _Step.code && _codeValid) {
      setState(() => _step = _Step.network);
      return;
    }
    if (_step == _Step.network && _networkValid) {
      _provision();
    }
  }

  void _back() {
    if (_step == _Step.code) {
      Navigator.of(context).pop();
      return;
    }
    if (_busy) return;
    setState(() {
      _step = _step == _Step.connect ? _Step.network : _Step.code;
      _error = null;
    });
  }

  Future<void> _provision() async {
    setState(() {
      _step = _Step.connect;
      _busy = true;
      _error = null;
      _reached.clear();
    });
    final request = ProvisioningRequest(
      gateway: widget.gateway,
      setupCode: _codeController.text,
      ssid: _ssidController.text.trim(),
      password: _passwordController.text,
      timeZone: _zone.posix,
    );
    _subscription = _provisioner.provision(request).listen(
      (stage) {
        if (!mounted) return;
        setState(() => _reached.add(stage));
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : error.toString();
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _busy = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
          tooltip: 'Back',
        ),
        title: Text('Gateway ${widget.gateway.shortCode}'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _stepLabel,
                style: text.labelLarge?.copyWith(
                  color: colors.textSubtle,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Text(
                _headline,
                style: text.displayMedium?.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: JKBMSRTokens.space16),
              Expanded(child: SingleChildScrollView(child: _body(context))),
              _bottomAction(context),
            ],
          ),
        ),
      ),
    );
  }

  String get _stepLabel {
    switch (_step) {
      case _Step.code:
        return 'STEP 1 OF 3 - SETUP CODE';
      case _Step.network:
        return 'STEP 2 OF 3 - NETWORK';
      case _Step.connect:
        return 'STEP 3 OF 3 - CONNECTING';
    }
  }

  String get _headline {
    switch (_step) {
      case _Step.code:
        return 'Enter the setup code';
      case _Step.network:
        return 'Which Wi-Fi should it use?';
      case _Step.connect:
        return _error == null ? 'Setting up' : 'Setup stopped';
    }
  }

  Widget _body(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;
    switch (_step) {
      case _Step.code:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'It is six digits, printed when the gateway starts up. In the flasher page it looks like this:',
              style: text.bodyMedium?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: JKBMSRTokens.space12),
            Container(
              padding: const EdgeInsets.all(JKBMSRTokens.space12),
              decoration: BoxDecoration(
                color: colors.inset,
                borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
              ),
              child: Text(
                '[info] Setup code: 418302',
                style: text.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space24),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Setup code',
                counterText: '',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        );
      case _Step.network:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ssidController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Wi-Fi name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            TextField(
              controller: _passwordController,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Wi-Fi password',
                helperText: 'Leave empty for an open network.',
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                ),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            DropdownButtonFormField<GatewayTimeZone>(
              initialValue: _zone,
              decoration: const InputDecoration(labelText: 'Time zone'),
              items: [
                for (final zone in GatewayTimeZone.all)
                  DropdownMenuItem(value: zone, child: Text(zone.label)),
              ],
              onChanged: (zone) {
                if (zone != null) setState(() => _zone = zone);
              },
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            Text(
              'The gateway keeps its clock in UTC. The time zone only changes how times are written in its log.',
              style: text.bodySmall?.copyWith(color: colors.textSubtle),
            ),
          ],
        );
      case _Step.connect:
        return _connectBody(context);
    }
  }

  Widget _connectBody(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final text = Theme.of(context).textTheme;
    const order = [
      ProvisioningStage.saving,
      ProvisioningStage.restarting,
      ProvisioningStage.joiningNetwork,
      ProvisioningStage.registering,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final stage in order) ...[
          Row(
            children: [
              _StageMark(
                state: _reached.contains(stage)
                    ? _StageState.done
                    : (_busy ? _StageState.pending : _StageState.skipped),
              ),
              const SizedBox(width: JKBMSRTokens.space12),
              Expanded(
                child: Text(
                  _stageLabel(stage),
                  style: text.bodyMedium?.copyWith(
                    color: _reached.contains(stage)
                        ? colors.textPrimary
                        : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
        ],
        if (_reached.contains(ProvisioningStage.done)) ...[
          const SizedBox(height: JKBMSRTokens.space8),
          Container(
            padding: const EdgeInsets.all(JKBMSRTokens.space16),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: colors.accent),
                const SizedBox(width: JKBMSRTokens.space12),
                Expanded(
                  child: Text(
                    'Gateway added. It will appear on your dashboard once it has sent its first reading.',
                    style: text.bodyMedium?.copyWith(color: colors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: JKBMSRTokens.space8),
          Text(
            _error!,
            style: text.bodyMedium?.copyWith(color: colors.critical),
          ),
        ],
      ],
    );
  }

  String _stageLabel(ProvisioningStage stage) {
    switch (stage) {
      case ProvisioningStage.saving:
        return 'Sending the settings';
      case ProvisioningStage.restarting:
        return 'Restarting the gateway';
      case ProvisioningStage.joiningNetwork:
        return 'Joining your Wi-Fi';
      case ProvisioningStage.registering:
        return 'Adding it to your account';
      case ProvisioningStage.done:
        return 'Done';
    }
  }

  Widget _bottomAction(BuildContext context) {
    if (_reached.contains(ProvisioningStage.done)) {
      return FilledButton(
        onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
        child: const Text('Done'),
      );
    }
    if (_step == _Step.connect) {
      if (_error == null) return const SizedBox(height: 52);
      return FilledButton(
        onPressed: () => setState(() {
          _step = _Step.network;
          _error = null;
        }),
        child: const Text('Change settings'),
      );
    }
    final enabled = _step == _Step.code ? _codeValid : _networkValid;
    return FilledButton(
      onPressed: enabled ? _next : null,
      child: Text(_step == _Step.code ? 'Continue' : 'Start setup'),
    );
  }
}

enum _StageState { done, pending, skipped }

class _StageMark extends StatelessWidget {
  const _StageMark({required this.state});

  final _StageState state;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    switch (state) {
      case _StageState.done:
        return Icon(Icons.check_circle, size: 20, color: colors.accent);
      case _StageState.pending:
        return SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.textSubtle,
          ),
        );
      case _StageState.skipped:
        return Icon(Icons.circle_outlined, size: 20, color: colors.textSubtle);
    }
  }
}
