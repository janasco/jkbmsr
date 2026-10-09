import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../models/firmware_release.dart';
import '../../utils/error_messages.dart';

/// Shows the same firmware release visibility data used by the web
/// dashboard: version, target hardware, rollout channel, release date, and
/// public-mirror verification state, scoped to the selected device's
/// hardware/channel when one is available.
class FirmwareReleasesScreen extends StatefulWidget {
  final String? deviceId;

  const FirmwareReleasesScreen({Key? key, this.deviceId}) : super(key: key);

  @override
  State<FirmwareReleasesScreen> createState() => _FirmwareReleasesScreenState();
}

class _FirmwareReleasesScreenState extends State<FirmwareReleasesScreen> {
  final APIClient _apiClient = APIClient();
  bool _isLoading = true;
  List<FirmwareRelease> _releases = [];
  String? _scopedHardware;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      String? targetHardware;
      String? rolloutChannel;

      if (widget.deviceId != null && widget.deviceId!.isNotEmpty) {
        final config = await _apiClient.getDeviceConfig(widget.deviceId!);
        targetHardware = config['targetHardware'] as String?;
        rolloutChannel = config['otaChannel'] as String?;
      }

      final releases = await _apiClient.getFirmwareReleases(
        targetHardware: targetHardware,
        rolloutChannel: rolloutChannel,
      );

      setState(() {
        _releases = releases;
        _scopedHardware = targetHardware;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
      JKBMSRToast.show(context, _error ?? 'Failed to load firmware releases', isError: true);
    }
  }

  ({Color color, String label}) _verificationStyle(BuildContext context, String status) {
    switch (status) {
      case 'verified':
        return (color: context.colors.accent, label: 'Verified');
      case 'mismatch':
        return (color: context.colors.critical, label: 'Mismatch');
      case 'missing':
        return (color: context.colors.warning, label: 'Missing');
      case 'unsigned':
        return (color: context.colors.textMuted, label: 'Unsigned');
      default:
        return (color: context.colors.warning, label: 'Unavailable');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      appBar: JKBMSRNavigationBar(title: 'Firmware Releases'),
      body: _isLoading
          ? ListView(
              padding: const EdgeInsets.all(JKBMSRTokens.space16),
              children: [
                // Three release cards, mirroring the version + verification
                // header, the Field/Value table and the detail line.
                for (var i = 0; i < 3; i++) ...[
                  const _ReleaseCardSkeleton(),
                  const SizedBox(height: JKBMSRTokens.space12),
                ],
              ],
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: context.colors.accent,
              backgroundColor: context.colors.panel,
              child: ListView(
                padding: const EdgeInsets.all(JKBMSRTokens.space16),
                children: [
                  if (_error != null && _releases.isEmpty)
                    JKBMSREmptyState(
                      icon: Icons.error_outline,
                      title: 'Could not load releases',
                      description: _error!,
                      action: OutlinedButton(
                        onPressed: _load,
                        child: const Text('Try Again'),
                      ),
                    )
                  else if (_releases.isEmpty)
                    const JKBMSREmptyState(
                      icon: Icons.system_update_outlined,
                      title: 'No firmware releases yet',
                      description: 'Published firmware builds will appear here once released.',
                    )
                  else ...[
                    if (_scopedHardware != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
                        child: Text(
                          'Scoped to $_scopedHardware',
                          style: JKBMSRTypography.label.copyWith(color: context.colors.textMuted),
                        ),
                      ),
                    ..._releases.map((release) {
                      final verification = _verificationStyle(context, release.publicMirrorStatus);
                      return Container(
                        margin: const EdgeInsets.only(bottom: JKBMSRTokens.space12),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(JKBMSRTokens.space16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'v${release.version}',
                                          style: JKBMSRTypography.cardHeading,
                                        ),
                                        if (release.isLatest) ...[
                                          const SizedBox(width: JKBMSRTokens.space8),
                                          JKBMSRStatusBadge(status: JKBMSRStatus.online),
                                        ],
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: JKBMSRTokens.space8,
                                        vertical: JKBMSRTokens.space2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: verification.color.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(JKBMSRTokens.radiusFull),
                                        border: Border.all(color: verification.color.withValues(alpha: 0.4)),
                                      ),
                                      child: Text(
                                        verification.label,
                                        style: JKBMSRTypography.label.copyWith(color: verification.color, fontSize: 11.0),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: JKBMSRTokens.space12),
                                JKBMSRDataTable(
                                  headers: const ['Field', 'Value'],
                                  rows: [
                                    [
                                      Text('Target Hardware', style: JKBMSRTypography.body),
                                      Text(release.targetHardware, style: JKBMSRTypography.monoTechnical),
                                    ],
                                    [
                                      Text('Rollout Channel', style: JKBMSRTypography.body),
                                      Text(release.rolloutChannel, style: JKBMSRTypography.monoTechnical),
                                    ],
                                    [
                                      Text('Released', style: JKBMSRTypography.body),
                                      Text(release.releasedAt, style: JKBMSRTypography.monoTechnical),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: JKBMSRTokens.space8),
                                Text(
                                  release.publicMirrorDetail,
                                  style: JKBMSRTypography.bodySecondary.copyWith(fontSize: 12.0),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
    );
  }
}

/// Loading silhouette of one firmware-release card: the version + status
/// badges, the Field/Value table and the detail line — mirroring the loaded
/// [Card]'s order and 16dp padding.
class _ReleaseCardSkeleton extends StatelessWidget {
  const _ReleaseCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return JKBMSRSkeletonCard(
      children: [
        Row(
          children: const [
            JKBMSRSkeleton(width: 52, height: 18),
            SizedBox(width: JKBMSRTokens.space8),
            JKBMSRSkeleton(
                width: 60,
                height: 22,
                borderRadius: JKBMSRTokens.radiusFull),
            Spacer(),
            JKBMSRSkeleton(
                width: 72,
                height: 22,
                borderRadius: JKBMSRTokens.radiusFull),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space12),
        // Field/Value table: a header plus three rows.
        for (var i = 0; i < 4; i++) ...[
          Row(
            children: const [
              JKBMSRSkeleton(width: 108, height: 12),
              Spacer(),
              JKBMSRSkeleton(width: 92, height: 12),
            ],
          ),
          const SizedBox(height: JKBMSRTokens.space12),
        ],
        const JKBMSRSkeleton(height: 12, width: 220),
      ],
    );
  }
}
