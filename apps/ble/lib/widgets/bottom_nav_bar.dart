import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum NavTab {
  status,
  cells,
  devices,
  controls,
}

class BottomNavBar extends StatefulWidget {
  final NavTab currentTab;
  final ValueChanged<NavTab> onTabSelect;

  const BottomNavBar({
    super.key,
    required this.currentTab,
    required this.onTabSelect,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  static const _items = [
    (NavTab.status, Icons.dashboard_rounded, 'STATUS'),
    (NavTab.cells, Icons.grid_view_rounded, 'CELLS'),
    (NavTab.devices, Icons.bluetooth_rounded, 'DEVICES'),
    (NavTab.controls, Icons.tune_rounded, 'CONTROLS'),
  ];

  Alignment _alignmentFor(int index) {
    final n = _items.length;
    return Alignment(-1 + 2 * index / (n - 1), 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark
        ? const Color(0xFF131A20).withValues(alpha: 0.95)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.95);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final currentIndex = _items.indexWhere((i) => i.$1 == widget.currentTab);

    // Grow the fixed bar height with the OS text scale so the icon + label
    // never clip at large accessibility sizes. At the default scale this is
    // exactly 1.0, so the bar is unchanged.
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: navBg,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: SizedBox(
            height: 62 * textScale,
            child: Stack(
              children: [
                // Sliding pill — glides between destinations with an
                // ease-out curve; each selection change re-pops the icon.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutCubic,
                      alignment: _alignmentFor(currentIndex),
                      child: FractionallySizedBox(
                        widthFactor: 1 / _items.length,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFF10B981).withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < _items.length; i++)
                      Expanded(
                        child: _NavItem(
                          icon: _items[i].$2,
                          label: _items[i].$3,
                          selected: i == currentIndex,
                          onTap: () {
                            if (i == currentIndex) return;
                            HapticFeedback.selectionClick();
                            widget.onTabSelect(_items[i].$1);
                          },
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF10B981) : const Color(0xFF64748B);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Springy pop on every selection change — keyed so the tween
            // re-runs from the small scale each time.
            TweenAnimationBuilder<double>(
              key: ValueKey(selected),
              tween: Tween(begin: 0.75, end: 1.0),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Icon(icon, size: 22, color: color),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                // Inherit the typeface from the ambient DefaultTextStyle.
                // AnimatedDefaultTextStyle REPLACES the inherited style rather
                // than merging, so omitting fontFamily here silently dropped
                // these labels back to the platform default (Roboto) while the
                // rest of the app rendered in its own typeface. Found while
                // rendering store screenshots headlessly — the nav labels did
                // not match the screen around them.
                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                fontSize: 11.0,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                letterSpacing: 1.1,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
