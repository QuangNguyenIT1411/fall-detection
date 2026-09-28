import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../models/realtime_update.dart';
import '../../providers/telemetry_provider.dart';
import '../../widgets/realtime_chart.dart';
import '../../widgets/state_badge.dart';

class RealtimeScreen extends StatelessWidget {
  const RealtimeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TelemetryProvider>();
    final width = MediaQuery.sizeOf(context).width;
    final history = provider.history;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(width < 600 ? 16 : 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Theo dõi realtime',
                            style: TextStyle(
                              color: AppColors.navy,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '60 điểm gần nhất • Nguồn '
                            '${provider.source == TelemetrySource.mqtt ? 'MQTT' : 'MOCK'}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    StateBadge(
                      state: provider.current.state,
                      large: width > 500,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final chartWidth = constraints.maxWidth >= 1050
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: chartWidth,
                          child: RealtimeChart(
                            title: 'Gia tốc tổng (ACC)',
                            unit: 'g',
                            color: AppColors.blue,
                            data: history,
                            selector: (item) => item.acc,
                          ),
                        ),
                        SizedBox(
                          width: chartWidth,
                          child: RealtimeChart(
                            title: 'Vận tốc góc (GYRO)',
                            unit: 'dps',
                            color: AppColors.cyan,
                            data: history,
                            selector: (item) => item.gyro,
                          ),
                        ),
                        SizedBox(
                          width: chartWidth,
                          child: RealtimeChart(
                            title: 'Góc tư thế (POSE)',
                            unit: '°',
                            color: const Color(0xFF7C3AED),
                            data: history,
                            selector: (item) => item.pose,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
