import 'package:flutter/material.dart';

import '../../models/device.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/labelled_progress.dart';
import '../alerts/pack_check_input.dart';
import 'diagnose_report.dart';
import 'diagnose_source.dart';

/// The guided diagnosis.
///
/// Every pack finding comes from the same `evaluatePackCheck` the Alerts screen
/// and the dashboard use; this screen adds the two questions a reading cannot
/// answer on its own, whether the gateway reached the battery and whether it
/// reached us, and states which measurement produced each finding.
class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key, this.deviceId, this.source});

  /// Open straight onto one gateway. Null shows a picker when there is more
  /// than one, because diagnosing the wrong pack is worse than one extra tap.
  final String? deviceId;

  final DiagnoseSource? source;

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  late final DiagnoseSource _source = widget.source ?? ApiDiagnoseSource();

  List<Device> _devices = const [];
  Device? _selected;
  DiagnoseReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({Device? device}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final devices = await _source.devices();
      if (!mounted) return;

      Device? target = device ?? _selected;
      target ??= widget.deviceId == null
          ? null
          : devices.where((d) => d.id == widget.deviceId).firstOrNull;

      // More than one gateway and no choice yet: ask, rather than guessing.
      if (target == null && devices.length > 1) {
        setState(() {
          _devices = devices;
          _loading = false;
        });
        return;
      }
      target ??= devices.isEmpty ? null : devices.first;

      if (target == null) {
        setState(() {
          _devices = const [];
          _loading = false;
        });
        return;
      }

      final telemetry = await _source.latestTelemetry(target.id);
      if (!mounted) return;

      if (telemetry == null) {
        setState(() {
          _devices = devices;
          _selected = target;
          _report = null;
          _loading = false;
          _error = 'The latest readings could not be loaded from ${target!.name}.';
        });
        return;
      }

      final report = buildDiagnoseReport(
        pack: packCheckInputFor(target, telemetry),
        gatewayOnline: target.status == 'online',
        link: telemetry.linkDiagnostics,
      );

      setState(() {
        _devices = devices;
        _selected = target;
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'The gateway list could not be loaded. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnose'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Check again',
          ),
        ],
      ),
      body: SafeArea(child: _body(context)),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: LabelledProgress(label: 'Reading the latest values'));
    }
    if (_error != null) {
      return _Message(
        icon: Icons.error_outline,
        title: 'Could not read this gateway',
        detail: _error!,
        action: FilledButton(
          onPressed: () => _load(),
          child: const Text('Try again'),
        ),
      );
    }
    if (_devices.isEmpty) {
      return const _Message(
        icon: Icons.router_outlined,
        title: 'No gateway yet',
        detail:
            'Diagnose reads the latest values from a gateway. Set one up first, then come back.',
      );
    }
    if (_report == null) {
      return _picker(context);
    }
    return _reportBody(context, _report!);
  }

  Widget _picker(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      children: [
        Text(
          'Which gateway?',
          style: JKBMSRTypography.pageHeading.copyWith(
            color: Theme.of(context).extension<JKBMSRColors>()!.textPrimary,
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        Text(
          'Diagnose one pack at a time.',
          style: JKBMSRTypography.bodySecondary,
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        for (final device in _devices)
          Card(
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(bottom: JKBMSRTokens.space8),
            child: ListTile(
              leading: const Icon(Icons.router_outlined),
              title: Text(device.name),
              subtitle: Text(device.status == 'online' ? 'Online' : 'Offline'),
              onTap: () => _load(device: device),
            ),
          ),
      ],
    );
  }

  Widget _reportBody(BuildContext context, DiagnoseReport report) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        JKBMSRTokens.space16,
        JKBMSRTokens.space8,
        JKBMSRTokens.space16,
        JKBMSRTokens.space32,
      ),
      children: [
        if (_selected != null)
          Text(
            _selected!.name,
            style: JKBMSRTypography.bodySecondary.copyWith(
              color: colors.textMuted,
            ),
          ),
        const SizedBox(height: JKBMSRTokens.space8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToneMark(tone: report.tone),
            const SizedBox(width: JKBMSRTokens.space12),
            Expanded(
              child: Text(
                report.headline,
                style: JKBMSRTypography.pageHeading.copyWith(
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        for (final check in report.checks) ...[
          _CheckCard(check: check),
          const SizedBox(height: JKBMSRTokens.space8),
        ],
        if (report.facts.isNotEmpty) ...[
          const SizedBox(height: JKBMSRTokens.space8),
          Text(
            'What these were read from',
            style: JKBMSRTypography.cardHeading.copyWith(
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: JKBMSRTokens.space8),
          for (final fact in report.facts)
            Padding(
              padding: const EdgeInsets.only(bottom: JKBMSRTokens.space4),
              child: Text(
                fact,
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: colors.textMuted,
                ),
              ),
            ),
        ],
        const SizedBox(height: JKBMSRTokens.space16),
        OutlinedButton(
          onPressed: () => _load(),
          child: const Text('Check again'),
        ),
      ],
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.check});

  final DiagnoseCheck check;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(JKBMSRTokens.space16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ToneMark(tone: check.tone, small: true),
            const SizedBox(width: JKBMSRTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    check.title,
                    style: JKBMSRTypography.body.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: JKBMSRTokens.space4),
                  Text(
                    check.detail,
                    style: JKBMSRTypography.bodySecondary.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  if (check.nextStep != null) ...[
                    const SizedBox(height: JKBMSRTokens.space8),
                    Text(
                      check.nextStep!,
                      style: JKBMSRTypography.bodySecondary.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToneMark extends StatelessWidget {
  const _ToneMark({required this.tone, this.small = false});

  final DiagnoseTone tone;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    final color = switch (tone) {
      DiagnoseTone.clear => colors.accent,
      DiagnoseTone.attention => colors.warning,
      DiagnoseTone.critical => colors.critical,
      DiagnoseTone.unknown => colors.textSubtle,
    };
    final icon = switch (tone) {
      DiagnoseTone.clear => Icons.check_circle_outline,
      DiagnoseTone.attention => Icons.info_outline,
      DiagnoseTone.critical => Icons.error_outline,
      DiagnoseTone.unknown => Icons.help_outline,
    };
    return Icon(icon, color: color, size: small ? 20 : 26);
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(JKBMSRTokens.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: colors.textSubtle),
            const SizedBox(height: JKBMSRTokens.space16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: JKBMSRTypography.pageHeading.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: JKBMSRTypography.bodySecondary.copyWith(
                color: colors.textMuted,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: JKBMSRTokens.space24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
