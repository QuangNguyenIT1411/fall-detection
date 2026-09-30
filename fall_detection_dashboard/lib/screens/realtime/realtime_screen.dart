import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
                    if (provider.source == TelemetrySource.mqtt &&
                        provider.devicePresence != DevicePresence.online)
                      Text(
                        provider.devicePresence == DevicePresence.offline
                            ? 'OFFLINE'
                            : 'KHÔNG CÓ KẾT NỐI',
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    else
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
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Nhật ký trạng thái gần đây',
                                style: TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('clear-recent-states'),
                              onPressed: provider.recentStates.isEmpty
                                  ? null
                                  : provider.clearRecentStates,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Xóa nhật ký'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Giúp kiểm tra các trạng thái trung gian khi thiết bị hoạt động bằng pin và không kết nối Serial Monitor.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Trạng thái trung gian không đồng nghĩa đã tạo sự kiện té ngã.',
                          style: TextStyle(color: AppColors.muted),
                        ),
                        const SizedBox(height: 16),
                        if (provider.recentStates.isEmpty)
                          const Text(
                            'Chưa nhận được trạng thái nào từ thiết bị.',
                          )
                        else
                          SizedBox(
                            height: (provider.recentStates.length * 52.0).clamp(
                              52.0,
                              312.0,
                            ),
                            child: ListView.builder(
                              key: const Key('recent-state-list'),
                              itemCount: provider.recentStates.length,
                              itemBuilder: (context, index) {
                                final entry = provider.recentStates[index];
                                return SizedBox(
                                  height: 52,
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 90,
                                        child: Text(
                                          DateFormat(
                                            'HH:mm:ss',
                                          ).format(entry.receivedAt.toLocal()),
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ),
                                      StateBadge(state: entry.state),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
