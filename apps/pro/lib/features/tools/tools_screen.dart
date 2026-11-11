import 'package:flutter/material.dart';

import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../diagnose/diagnose_screen.dart';
import '../guide/guide_screen.dart';
import '../provisioning/gateway_scan_screen.dart';

/// One place for the things that are not the dashboard.
///
/// Deliberately small. A monitoring app that grows a tab per feature ends up
/// with a navigation bar nobody can read on a phone, and the dashboard is the
/// screen an owner actually lives on. Three entries, each a verb.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tools'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            JKBMSRTokens.space16,
            JKBMSRTokens.space8,
            JKBMSRTokens.space16,
            JKBMSRTokens.space24,
          ),
          children: [
            Text(
              'Checks, answers and setup.',
              style: JKBMSRTypography.bodySecondary.copyWith(
                color: colors.textMuted,
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space16),
            _ToolCard(
              icon: Icons.monitor_heart_outlined,
              title: 'Diagnose',
              detail:
                  'Read the latest values from one gateway and see what is worth checking, with the measurement behind each finding.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const DiagnoseScreen()),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            _ToolCard(
              icon: Icons.menu_book_outlined,
              title: 'Guide',
              detail:
                  'Short answers: cell spread, current direction, a lost battery link, time zones and the trial.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const GuideScreen()),
              ),
            ),
            const SizedBox(height: JKBMSRTokens.space8),
            _ToolCard(
              icon: Icons.add_link,
              title: 'Add a gateway',
              detail:
                  'Set up a new ESP32 gateway over Bluetooth and link it to this account.',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const GatewayScanScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space16),
          child: Row(
            children: [
              Icon(icon, size: 24, color: colors.accent),
              const SizedBox(width: JKBMSRTokens.space16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: JKBMSRTypography.body.copyWith(
                        fontWeight: FontWeight.w500,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: JKBMSRTokens.space4),
                    Text(
                      detail,
                      style: JKBMSRTypography.bodySecondary.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: JKBMSRTokens.space8),
              Icon(Icons.chevron_right, size: 20, color: colors.textSubtle),
            ],
          ),
        ),
      ),
    );
  }
}
