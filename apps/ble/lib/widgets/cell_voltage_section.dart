import 'package:flutter/material.dart';
import '../models/bms_models.dart';

class CellVoltageSection extends StatelessWidget {
  final BmsStatus status;
  const CellVoltageSection({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final cells = status.cells;
    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title & High/Low Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.grid_view_rounded, color: Color(0xFF10B981), size: 16),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'CELL VOLTAGES & BALANCING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${cells.length} Series Cells',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Cell Voltage Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.3,
            ),
            itemBuilder: (context, index) {
              final cell = cells[index];
              final isMax = index == status.maxCellIndex;
              final isMin = index == status.minCellIndex;

              // Normalized bar fill between 2.80V (0%) and 3.65V (100%) for LiFePO4
              final fill = ((cell.voltage - 2.80) / (3.65 - 2.80)).clamp(0.05, 1.0);

              Color barColor = const Color(0xFF38BDF8);
              if (isMax) barColor = const Color(0xFF10B981); // Emerald Green
              if (isMin) barColor = const Color(0xFFF59E0B); // Amber

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMax
                        ? const Color(0xFF10B981).withValues(alpha: 0.6)
                        : (isMin
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.6)
                            : Colors.white.withValues(alpha: 0.05)),
                    width: (isMax || isMin) ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Cell Header (Index + Wire Res + Bal Badge)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Cell ${(index + 1).toString().padLeft(2, '0')}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isMax
                                    ? const Color(0xFF10B981)
                                    : (isMin ? const Color(0xFFF59E0B) : Colors.white70),
                              ),
                            ),
                            if (isMax)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text('▲', style: TextStyle(color: Color(0xFF10B981), fontSize: 11.0)),
                              ),
                            if (isMin)
                              const Padding(
                                padding: EdgeInsets.only(left: 4),
                                child: Text('▼', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11.0)),
                              ),
                          ],
                        ),
                        if (cell.isBalancing)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                            ),
                            child: const Text(
                              'BAL',
                              style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                            ),
                          )
                        else
                          Text(
                            '${cell.resistanceMOhms.toStringAsFixed(1)} mΩ',
                            style: const TextStyle(fontSize: 11.0, color: Colors.white38),
                          ),
                      ],
                    ),

                    // Voltage Text
                    Text(
                      '${cell.voltage.toStringAsFixed(3)} V',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),

                    // Visual Horizontal Voltage Gauge Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            height: 4,
                            color: Colors.white10,
                          ),
                          FractionallySizedBox(
                            widthFactor: fill,
                            child: Container(
                              height: 4,
                              color: barColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
