import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/haptics.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';

/// First-launch onboarding.
///
/// Redesigned around the five things this app actually asks of a new owner, one
/// per step, each with a **name** — the previous version was five anonymous dots
/// over a lone icon, so nothing told you where you were or what was left.
///
/// What changed and why:
///  * every step carries a label ("MONITOR", "FLEET", …) and a "STEP 2 OF 5"
///    counter, so the flow has a shape you can see;
///  * a composed hero panel replaces the small icon in a circle — the app has no
///    illustration assets and should not get any, so the composition is built from
///    the design system (gradient, ring, watermark glyph);
///  * the copy leads with the benefit and then says what it is, instead of
///    restating the feature name;
///  * the dots became a segmented progress bar, which reads as progress and
///    survives a 2x text scale without changing size.
///
/// Behaviour is unchanged: Skip anywhere, Next through the steps, and Get started
/// on the last one marks it complete and goes to /login.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();

  /// Check if the user has completed onboarding.
  static Future<bool> hasCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('jkbmsr.onboardingComplete') ?? false;
  }

  /// Mark onboarding as complete.
  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('jkbmsr.onboardingComplete', true);
  }
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// One idea per step, in the order an owner meets them. The label is the thing
  /// the counter names; the title is the benefit; the body says how.
  static const List<_OnboardingStep> _steps = [
    _OnboardingStep(
      icon: Icons.bolt_rounded,
      label: 'Monitor',
      title: 'Your pack, from anywhere',
      description:
          'Live voltage, current, temperature and state of charge — from every '
          'gateway you own, on one screen.',
    ),
    _OnboardingStep(
      icon: Icons.devices_other_rounded,
      label: 'Fleet',
      title: 'Every gateway in one place',
      description:
          'Add packs as you build them. Each one shows its own telemetry, status '
          'and alerts, so one weak pack cannot hide behind the others.',
    ),
    _OnboardingStep(
      icon: Icons.notifications_active_outlined,
      label: 'Alerts',
      title: 'Told before it matters',
      description:
          'Over-voltage, high temperature, a gateway that stopped reporting — you '
          'get the alert instead of the surprise.',
    ),
    _OnboardingStep(
      icon: Icons.show_chart_rounded,
      label: 'History',
      title: 'A year, not a snapshot',
      description:
          'Up to 365 days of telemetry with charts and CSV export, so a slow drift '
          'is something you can see rather than something you remember.',
    ),
    _OnboardingStep(
      icon: Icons.shield_outlined,
      label: 'Privacy',
      title: 'Yours, and locked',
      description:
          'Biometric unlock keeps the app closed to everyone else, and you can '
          'export or delete your history from your account at any time.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    setState(() => _currentPage = page);
    JKBMSRHaptics.lightImpact();
  }

  Future<void> _completeOnboarding() async {
    JKBMSRHaptics.success();
    await OnboardingScreen.markComplete();
    if (mounted) {
      context.go('/login');
    }
  }

  void _next() {
    if (_currentPage < _steps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isLast = _currentPage == _steps.length - 1;

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                JKBMSRTokens.space24,
                JKBMSRTokens.space8,
                JKBMSRTokens.space12,
                0,
              ),
              child: Row(
                children: [
                  Icon(Icons.bolt_rounded, size: 20, color: colors.accent),
                  const SizedBox(width: JKBMSRTokens.space8),
                  // Expanded, not a Spacer: at 2x text the wordmark plus Skip
                  // exceeds 360dp with the real (bundled) typeface, and a Spacer
                  // cannot shrink its siblings.
                  Expanded(
                    child: Text(
                      'JK BMS Remote',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: JKBMSRTypography.bodySecondary.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _completeOnboarding,
                    child: Text(
                      'Skip',
                      style: JKBMSRTypography.bodySecondary.copyWith(
                        color: colors.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _steps.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) => _StepView(
                  step: _steps[index],
                  index: index,
                  total: _steps.length,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                JKBMSRTokens.space24,
                0,
                JKBMSRTokens.space24,
                JKBMSRTokens.space24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProgressSegments(
                      current: _currentPage, total: _steps.length),
                  const SizedBox(height: JKBMSRTokens.space24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _next,
                      child: Text(isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One step: the composed hero, then the counter, the benefit, and how it works.
///
/// A ListView rather than a centred Column so that a 2x text scale scrolls
/// instead of overflowing — the same rule the rest of this app follows.
class _StepView extends StatelessWidget {
  const _StepView(
      {required this.step, required this.index, required this.total});

  final _OnboardingStep step;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    // Centred when it fits, scrolls when it does not (large text). A ListView
    // pinned the block to the top and left a dead quarter-screen below it.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          JKBMSRTokens.space24,
          JKBMSRTokens.space16,
          JKBMSRTokens.space24,
          JKBMSRTokens.space24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                constraints.maxHeight > 48 ? constraints.maxHeight - 40 : 0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepHero(icon: step.icon),
              const SizedBox(height: JKBMSRTokens.space32),
              Text(
                'STEP ${index + 1} OF $total  ·  ${step.label.toUpperCase()}',
                style: JKBMSRTypography.bodySecondary.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Text(
                step.title,
                style: JKBMSRTypography.pageHeading
                    .copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: JKBMSRTokens.space12),
              Text(
                step.description,
                style: JKBMSRTypography.body.copyWith(
                  color: colors.textSecondary,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero. No illustration assets — the app has none and should not gain any —
/// so the composition is the design system: a soft gradient panel, a ring, an
/// oversized watermark glyph and the step's icon in front of it.
class _StepHero extends StatelessWidget {
  const _StepHero({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return ClipRRect(
      borderRadius: BorderRadius.circular(JKBMSRTokens.radius16),
      child: Container(
        // Full width: inside a start-aligned Column the panel would otherwise
        // shrink to its children (a 104 px circle and a watermark glyph).
        width: double.infinity,
        height: 232,
        decoration: BoxDecoration(
          border: Border.all(color: colors.line),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.accent.withValues(alpha: 0.14),
              colors.signal.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Watermark, large and faint: gives the panel depth without a picture.
            Transform.translate(
              offset: const Offset(78, 44),
              child: Icon(icon,
                  size: 132, color: colors.accent.withValues(alpha: 0.07)),
            ),
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.panel,
                border:
                    Border.all(color: colors.accent.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 46, color: colors.accent),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented progress: one segment per step, so the flow's length is visible.
class _ProgressSegments extends StatelessWidget {
  const _ProgressSegments({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      label: 'Step ${current + 1} of $total',
      child: Row(
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const SizedBox(width: JKBMSRTokens.space8),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                height: 4,
                decoration: BoxDecoration(
                  color: i <= current ? colors.accent : colors.line,
                  borderRadius: BorderRadius.circular(JKBMSRTokens.radius2),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingStep {
  final IconData icon;
  final String label;
  final String title;
  final String description;

  const _OnboardingStep({
    required this.icon,
    required this.label,
    required this.title,
    required this.description,
  });
}
