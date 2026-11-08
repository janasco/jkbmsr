import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A rounded panel. Every grouped block on the redesigned screens is one of
/// these, so padding, radius, border and surface tone cannot drift between them.
class AppSurface extends StatelessWidget {
  const AppSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
    this.color,
    this.radius = AppTheme.radius,
    this.border = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  final bool border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decorated = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? scheme.surfaceContainerLow) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55))
            : null,
      ),
      // A transparent Material ancestor: a ListTile inside a decorated box
      // otherwise asserts, because it paints its ink on the nearest Material
      // and this box's background would hide it.
      child: Material(type: MaterialType.transparency, child: child),
    );
    if (onTap == null) return decorated;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: decorated,
      ),
    );
  }
}

/// One number with its label, used in the summary rows.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
  });

  final String value;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(height: 8),
        ],
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// `label            value` with the value allowed to wrap.
///
/// A value too long for its column wraps at whatever word happens to fit, which
/// on a right-aligned row reads as a typo — `2 (deviceInfo x1, cellInfo / x1)`.
/// Set [stacked] for those: the label goes above and the value gets the full
/// width, which is the shape a receipt uses for a long line.
class DetailRow extends StatelessWidget {
  const DetailRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.stacked = false,
  });

  final String label;
  final String value;
  final bool emphasis;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
      color: emphasis ? theme.colorScheme.primary : theme.colorScheme.onSurface,
    );

    if (stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: 3),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(label, style: labelStyle),
          ),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: valueStyle),
          ),
        ],
      ),
    );
  }
}

/// An icon, a short promise and one line of detail — the idle screen's three
/// assurances. Deliberately plain: these are claims the app has to keep.
class AssuranceRow extends StatelessWidget {
  const AssuranceRow({
    super.key,
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
