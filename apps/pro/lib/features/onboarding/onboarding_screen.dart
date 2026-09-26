import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/shared/design_system/colors.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../utils/haptics.dart';

/// First-launch onboarding screen that introduces new users to JKBMSR.
/// Shows a series of feature highlights with a swipeable page view,
/// then a "Get Started" button that marks onboarding as complete.
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

  final List<_OnboardingPage> _pages = const [
    _OnboardingPage(
      icon: Icons.bolt,
      title: 'Welcome to JKBMSR Pro',
      subtitle: 'JK Battery Management System Remote',
      description: 'Monitor your battery systems in real-time from anywhere. Track voltage, temperature, and health across all your gateways.',
    ),
    _OnboardingPage(
      icon: Icons.devices_other,
      title: 'Your Gateway Fleet',
      description: 'Add and manage multiple battery gateways. Each device shows live telemetry, status, and alerts at a glance.',
    ),
    _OnboardingPage(
      icon: Icons.notifications_active_outlined,
      title: 'Smart Alerts',
      description: 'Get instant notifications for critical events like over-voltage, high temperature, or offline status. Never miss an important alert.',
    ),
    _OnboardingPage(
      icon: Icons.cloud_outlined,
      title: 'Cloud History',
      description: 'Access up to 365 days of telemetry history. Export data as CSV and spot trends with interactive charts.',
    ),
    _OnboardingPage(
      icon: Icons.shield_outlined,
      title: 'Secure & Private',
      description: 'Your data is encrypted and protected. Enable biometric unlock for quick, secure access to your battery systems.',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // Skip button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(JKBMSRTokens.space16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    'Skip',
                    style: JKBMSRTypography.body.copyWith(color: context.colors.textMuted),
                  ),
                ),
              ),
            ),

            // Page view
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Icon
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: context.colors.accent.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.colors.accent.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            page.icon,
                            size: 48,
                            color: context.colors.accent,
                          ),
                        ),
                        const SizedBox(height: JKBMSRTokens.space32),

                        // Title
                        if (page.title != null)
                          Text(
                            page.title!,
                            style: JKBMSRTypography.pageHeading.copyWith(
                              color: context.colors.textPrimary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        if (page.subtitle != null) ...[
                          const SizedBox(height: JKBMSRTokens.space8),
                          Text(
                            page.subtitle!,
                            style: JKBMSRTypography.body.copyWith(
                              color: context.colors.accent,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                        const SizedBox(height: JKBMSRTokens.space16),

                        // Description
                        Text(
                          page.description,
                          style: JKBMSRTypography.bodySecondary.copyWith(
                            color: context.colors.textSecondary,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Page indicators + button
            Padding(
              padding: const EdgeInsets.all(JKBMSRTokens.space32),
              child: Column(
                children: [
                  // Page indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? context.colors.accent
                              : context.colors.line,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: JKBMSRTokens.space32),

                  // Get Started button (on last page) or Next button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < _pages.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          _completeOnboarding();
                        }
                      },
                      child: Text(
                        _currentPage < _pages.length - 1 ? 'Next' : 'Get Started',
                      ),
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

class _OnboardingPage {
  final IconData icon;
  final String? title;
  final String? subtitle;
  final String description;

  const _OnboardingPage({
    required this.icon,
    this.title,
    this.subtitle,
    required this.description,
  });
}
