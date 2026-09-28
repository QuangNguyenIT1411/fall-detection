import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/telemetry.dart';

class RealtimeChart extends StatelessWidget {
  const RealtimeChart({
    super.key,
    required this.title,
    required this.unit,
    required this.color,
    required this.data,
    required this.selector,
  });

  final String title;
  final String unit;
  final Color color;
  final List<Telemetry> data;
  final double Function(Telemetry) selector;

  @override
  Widget build(BuildContext context) {
    final values = data.isEmpty ? <double>[0] : data.map(selector).toList();
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final chartMax = maxValue <= 1 ? 1.2 : maxValue * 1.18;
    final spots = [
      for (var index = 0; index < values.length; index++)
        FlSpot(index.toDouble(), values[index]),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${values.last.toStringAsFixed(1)} $unit',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 190,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  maxX: (values.length - 1).clamp(1, 60).toDouble(),
                  minY: 0,
                  maxY: chartMax,
                  clipData: const FlClipData.all(),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: chartMax / 4,
                    getDrawingHorizontalLine: (_) =>
                        const FlLine(color: Color(0xFFE8EEF5), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        maxIncluded: false,
                      ),
                    ),
                  ),
                  lineTouchData: const LineTouchData(enabled: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.25,
                      color: color,
                      barWidth: 2.5,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.22),
                            color.withValues(alpha: 0.01),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
