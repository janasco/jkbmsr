import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import '../services/brand_registry.dart';
import 'motion_kit.dart';

/// Compact brand-identity strip shown above the battery hero on the Status
/// tab: the detected brand's icon + name + tagline tinted with the brand
/// accent, a "live data verified" / detection-state chip, and (when known)
/// a model-series chip derived from the decoded model name.
class BrandHeroStrip extends StatelessWidget {
  final BmsBrand brand;
  final String modelName;
  final bool hasLiveData;

  const BrandHeroStrip({
    super.key,
    required this.brand,
    required this.modelName,
    required this.hasLiveData,
  });

  @override
  Widget build(BuildContext context) {
    final design = BrandRegistry.designFor(brand);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final (String stateLabel, Color stateColor, IconData stateIcon) = !hasLiveData
        ? ('DETECTING', const Color(0xFFF59E0B), Icons.radar_rounded)
        : ('LIVE DATA VERIFIED', const Color(0xFF10B981), Icons.shield_rounded);

    final model = modelName.isEmpty ? '' : BrandRegistry.seriesHint(brand, modelName);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: design.accent.withValues(alpha: hasLiveData ? 0.55 : 0.25)),
        boxShadow: [
          BoxShadow(
            color: design.accent.withValues(alpha: isDark ? 0.18 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: design.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(design.icon, color: design.accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.isPublic
                          ? design.name.toUpperCase()
                          : 'UNSUPPORTED DEVICE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      brand.isPublic
                          ? design.tagline
                          : 'Identified as an unsupported battery system. '
                              'JKBMSR supports JK-BMS only.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.0, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: stateColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasLiveData)
                      // Breathing confirmation dot next to the shield once
                      // real telemetry is flowing.
                      const PulseDot(color: Color(0xFF10B981), size: 7)
                    else
                      Icon(stateIcon, size: 12, color: stateColor),
                    const SizedBox(width: 4),
                    Text(
                      stateLabel,
                      style: TextStyle(fontSize: 11.0, fontWeight: FontWeight.w900, color: stateColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (model.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.memory_rounded, size: 13, color: design.accent),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    model,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: design.accent,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}