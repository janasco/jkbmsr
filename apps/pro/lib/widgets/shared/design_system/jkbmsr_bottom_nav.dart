import 'package:flutter/material.dart';

import 'colors.dart';

/// A destination for [JKBMSRBottomNav].
class JKBMSRBottomNavItem {
  final IconData icon;
  final String label;

  const JKBMSRBottomNavItem({required this.icon, required this.label});
}

/// Pill-shaped bottom navigation where the selected destination is shown as a
/// filled circular badge (icon only), and the rest are plain icons — the
/// "bottom navigation" reference style. Falls back to a plain icon row for
/// screen readers via the per-item tooltip/semantics label.
class JKBMSRBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final List<JKBMSRBottomNavItem> items;

  const JKBMSRBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: colors.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selectedIndex,
                    label: items[i].label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(32),
                      onTap: () => onTap(i),
                      child: Center(
                        child: AnimatedContainer(
                          duration: MediaQuery.of(context).disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: i == selectedIndex
                                ? colors.accent
                                : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            items[i].icon,
                            size: 22,
                            color: i == selectedIndex
                                ? colors.onAccent
                                : colors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
