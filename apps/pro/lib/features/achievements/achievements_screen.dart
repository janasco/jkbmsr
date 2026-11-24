import 'package:flutter/material.dart';

import '../../models/achievement.dart';
import '../../services/api_client.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';

/// The contributor game, as the account sees it.
///
/// Scope note that is repeated on screen: these are ACCOUNT milestones. The
/// ledger is keyed by user id, so the same list is shown whichever gateway is
/// open, and a gateway only appears here as the pack that completed a condition.
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  AchievementSummary? _summary;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final summary = await APIClient().getAchievements();
      if (!mounted) return;
      setState(() => _summary = summary);
    } catch (_) {
      // A failed read is not "nothing earned". Saying that to someone who has
      // donated would be a false claim about their own record.
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: SafeArea(child: _body(context, colors)),
    );
  }

  Widget _body(BuildContext context, dynamic colors) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(JKBMSRTokens.space24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded, size: 40, color: colors.textMuted),
              const SizedBox(height: JKBMSRTokens.space12),
              Text(
                'Your achievements could not be loaded.',
                textAlign: TextAlign.center,
                style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: JKBMSRTokens.space8),
              Text(
                'This is not an empty record. Check your connection and try again.',
                textAlign: TextAlign.center,
                style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
              ),
              const SizedBox(height: JKBMSRTokens.space16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final summary = _summary;
    if (summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      children: [
        _header(colors, summary),
        const SizedBox(height: JKBMSRTokens.space16),
        for (final achievement in summary.achievements) ...[
          _AchievementRow(achievement: achievement),
          const SizedBox(height: JKBMSRTokens.space8),
        ],
        const SizedBox(height: JKBMSRTokens.space8),
        Text(
          'Points belong to your account, not to one gateway. Donate a pack in the '
          'JK BMS Contributor app with your code and the milestones complete on their own.',
          style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
        ),
      ],
    );
  }

  Widget _header(dynamic colors, AchievementSummary summary) {
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${summary.earnedCount} of ${summary.achievements.length} earned',
            style: JKBMSRTypography.cardHeading.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: JKBMSRTokens.space4),
          Text(
            '${summary.pointsEarned} points from achievements',
            style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({required this.achievement});

  final Achievement achievement;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final earned = achievement.earned;
    return Container(
      padding: const EdgeInsets.all(JKBMSRTokens.space16),
      decoration: BoxDecoration(
        color: earned ? colors.panel : colors.inset,
        borderRadius: BorderRadius.circular(JKBMSRTokens.radius12),
        border: Border.all(color: earned ? colors.accent.withValues(alpha: 0.35) : colors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            earned ? Icons.verified_rounded : Icons.lock_outline_rounded,
            size: 20,
            color: earned ? colors.accent : colors.textMuted,
          ),
          const SizedBox(width: JKBMSRTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievement.title,
                  style: JKBMSRTypography.body.copyWith(
                    color: earned ? colors.textPrimary : colors.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  achievement.detail,
                  style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: JKBMSRTokens.space8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${achievement.points}',
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: earned ? colors.accent : colors.textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (earned)
                Text(
                  'earned',
                  style: JKBMSRTypography.bodySecondary.copyWith(color: colors.textMuted),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
