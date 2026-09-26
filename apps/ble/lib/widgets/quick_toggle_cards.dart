import 'package:flutter/material.dart';
import '../models/bms_models.dart';
import 'motion_kit.dart';

/// Read-only status display — not tappable. Actual control only happens on
/// the Control tab, behind PIN verification.
class QuickToggleCards extends StatelessWidget {
  final BmsStatus switches;
  final bool isConnected;

  const QuickToggleCards({
    super.key,
    required this.switches,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF);
    final borderColor = isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0);
    final textPrimary = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);

    final cards = [
      _ToggleCardData(
        title: 'Charge',
        isOn: isConnected && switches.chargeMosEnabled,
        icon: Icons.bolt_rounded,
      ),
      _ToggleCardData(
        title: 'Discharge',
        isOn: isConnected && switches.dischargeMosEnabled,
        icon: Icons.electric_bolt_rounded,
      ),
      _ToggleCardData(
        title: 'Balance',
        isOn: isConnected && switches.balanceEnabled,
        icon: Icons.balance_rounded,
      ),
    ];

    return Row(
      children: cards.asMap().entries.map((entry) {
        final index = entry.key;
        final card = entry.value;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: TileEntrance(
              delayIndex: index,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isConnected ? cardBg : cardBg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: card.isOn
                        ? const Color(0xFF10B981).withValues(alpha: 0.6)
                        : borderColor,
                  ),
                  boxShadow: card.isOn
                      ? [
                          BoxShadow(
                            color: const Color(0xFF10B981).withValues(alpha: 0.08),
                            blurRadius: 10,
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Green pulse while the MOS/balancer is ON,
                        // static grey when off.
                        PulseDot(
                          color: card.isOn ? const Color(0xFF10B981) : const Color(0xFF64748B),
                          size: 7,
                          active: card.isOn,
                        ),
                        Flexible(
                          child: Text(
                            isConnected ? 'LIVE' : 'OFFLINE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.0,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Icon(
                      card.icon,
                      color: card.isOn ? const Color(0xFF10B981) : const Color(0xFF64748B),
                      size: 26,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      card.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isConnected ? textPrimary : const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !isConnected ? '—' : (card.isOn ? 'ON' : 'OFF'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: card.isOn ? const Color(0xFF10B981) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ToggleCardData {
  final String title;
  final bool isOn;
  final IconData icon;

  _ToggleCardData({
    required this.title,
    required this.isOn,
    required this.icon,
  });
}
